import Foundation
import Combine
import CoreLocation
import UserNotifications
import WidgetKit

@MainActor
final class AppState: ObservableObject {
    @Published var isAuthenticated: Bool
    @Published var currentUser: AppUser?
    @Published var shoppingList: [GroceryItem]
    @Published var preferences: UserPreferences
    @Published var useMockBackend: Bool
    /// The simulate buttons and the demo store (see `showsTestTools(useMockBackend:isDebugBuild:takingScreenshots:)`).
    let showsTestTools: Bool
    /// True once the signed-in user's saved preferences have arrived. Until then `preferences`
    /// holds defaults, so nothing is saved (it would overwrite the real ones).
    @Published private(set) var preferencesLoaded = false
    /// True once the signed-in user's list has arrived from sync.
    @Published private(set) var itemsLoaded = false
    /// Set when live sync with the backend fails (e.g. Firestore rules deny access).
    @Published private(set) var syncErrorMessage: String?
    /// The list being shown and edited: the user's own (ID = their uid) or one they joined.
    @Published private(set) var activeListId: String?
    /// Who shares the active list; nil until it has been fetched.
    @Published private(set) var sharedList: SharedListInfo?
    /// An unload reminder was scheduled in the last 3 h and the groceries haven't been marked
    /// brought in since, so "Mark groceries brought in" stays available after the countdown ends.
    @Published private(set) var unloadOutstanding = false
    /// A tab to show, e.g. Arrival after the unload reminder is tapped. MainTabView opens it and clears it.
    @Published var requestedTab: AppTab?

    /// Location events wait here until the session's list and preferences have loaded.
    private(set) var pendingLocationEvents: [LocationEvent] = []
    /// Applies the latest batch of location decisions; cancelled on sign-out.
    private(set) var locationBatchTask: Task<Void, Never>?
    var sessionDataLoaded: Bool { itemsLoaded && preferencesLoaded }

    let authService: AuthServiceProtocol
    let listService: ShoppingListServiceProtocol
    let locationService: LocationService
    let notificationService: NotificationService
    let homeArrivalTimer: HomeArrivalTimerService
    let diagnostics: DiagnosticsLog

    private var cancellables = Set<AnyCancellable>()
    /// Cleared once a session starts, so a late restore can't replace a manual sign-in.
    private var canRestoreSession = true
    private var itemsSyncTask: Task<Void, Never>?
    private var activeListTask: Task<Void, Never>?
    private var preferencesSyncTask: Task<Void, Never>?
    /// True while `switchList` waits on a join or leave. A join's new list can be denied for a moment
    /// (the listener may reach the server before the membership does), which isn't a removal.
    private var isSwitchingList = false
    private var itemsDeniedDuringSwitch = false
    private let backgroundActivity: BackgroundActivityProviding
    private var backgroundActivityToken: Int?
    private var cooldowns: ReminderCooldowns
    private let cooldownStore: JSONFileStore<ReminderCooldowns>?
    private let widgetStore: WidgetSnapshotStore?
    private var lastWidgetSnapshot: WidgetSnapshot?

    /// - Parameters:
    ///   - mockStorageDirectory: where the demo backend saves accounts, lists and preferences.
    ///     `nil` (tests, previews) keeps them in memory.
    ///   - diagnostics: the event log; `nil` keeps entries in memory.
    ///   - backgroundActivity: extra background time while a location wake-up waits for data; `nil` for none.
    ///   - stateDirectory: where the arrival countdown and reminder cooldowns are saved; `nil` keeps them in memory.
    ///   - widgetStore: where the home-screen widget's snapshot is written; `nil` for no widget.
    ///   - systemServices: `false` (tests) makes the location and notification services inert:
    ///     they only record what they would do, and never ask for permission.
    ///   - showsTestTools: whether the simulate buttons and the demo store are offered.
    ///   - locationManager: replaces the system location manager (tests); `nil` follows `systemServices`.
    init(
        useMockBackend: Bool = true,
        mockStorageDirectory: URL? = nil,
        diagnostics: DiagnosticsLog? = nil,
        backgroundActivity: BackgroundActivityProviding? = nil,
        stateDirectory: URL? = nil,
        widgetStore: WidgetSnapshotStore? = nil,
        systemServices: Bool = true,
        showsTestTools: Bool = true,
        locationManager: LocationManaging? = nil
    ) {
        // Defaults are created here: in Swift 5 mode a default argument can't call a main-actor initializer.
        let diagnostics = diagnostics ?? DiagnosticsLog()
        self.useMockBackend = useMockBackend
        self.showsTestTools = showsTestTools
        if useMockBackend {
            self.authService = MockAuthService(
                store: mockStorageDirectory.map { JSONFileStore<MockAuthSnapshot>(url: $0.appendingPathComponent("mock-auth.json")) }
            )
            self.listService = MockShoppingListService(
                store: mockStorageDirectory.map { JSONFileStore<MockListSnapshot>(url: $0.appendingPathComponent("mock-list.json")) }
            )
        } else {
            self.authService = FirebaseAuthService()
            self.listService = FirestoreShoppingListService()
        }
        self.diagnostics = diagnostics
        self.widgetStore = widgetStore
        self.backgroundActivity = backgroundActivity ?? NoBackgroundActivity()
        self.locationService = LocationService(
            diagnostics: diagnostics,
            manager: locationManager ?? (systemServices ? CLLocationManager() : nil)
        )
        self.notificationService = NotificationService(center: systemServices ? UNUserNotificationCenter.current() : nil)
        self.homeArrivalTimer = HomeArrivalTimerService(
            store: stateDirectory.map { JSONFileStore<ArrivalTimerState>(url: $0.appendingPathComponent("arrival-timer.json")) }
        )
        let cooldownStore = stateDirectory.map { JSONFileStore<ReminderCooldowns>(url: $0.appendingPathComponent("reminder-cooldowns.json")) }
        self.cooldownStore = cooldownStore
        if case .loaded(let saved) = cooldownStore?.load() {
            self.cooldowns = saved
        } else {
            self.cooldowns = ReminderCooldowns()
        }

        self.isAuthenticated = false
        self.currentUser = nil
        // The list arrives from sync once a session starts.
        self.shoppingList = []
        self.preferences = .default

        refreshUnloadOutstanding()
        bindServices()
    }

    /// The simulate buttons and the demo store fake location events, which App Review and real users
    /// must never see: they're offered in the demo build (no Firebase) and Debug builds only, and
    /// hidden while the App Store screenshots are taken.
    static func showsTestTools(useMockBackend: Bool, isDebugBuild: Bool, takingScreenshots: Bool) -> Bool {
        !takingScreenshots && (useMockBackend || isDebugBuild)
    }

    private func bindServices() {
        // Delivered synchronously on the main actor, so no event is lost before it is handled.
        locationService.events
            .sink { [weak self] event in
                self?.handleLocationEvent(event)
            }
            .store(in: &cancellables)

        // The daily reminder has the open-item count in its text, so it's rescheduled a second after
        // the list or the preferences last change (a run of check-offs reschedules it once), and
        // when notifications become allowed. It reads the state then, once the loaded flags have settled.
        Publishers.Merge3(
            $shoppingList.map { _ in () },
            $preferences.map { _ in () },
            notificationService.$isAuthorized.removeDuplicates().map { _ in () }
        )
        .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            Task { await self?.updateDailyReminder() }
        }
        .store(in: &cancellables)

        // Coalesced, so a sync burst or a background relaunch reloads the widget once.
        guard widgetStore != nil else { return }
        let unload = Publishers.CombineLatest(homeArrivalTimer.$endDate, $unloadOutstanding)
        Publishers.CombineLatest4($shoppingList, $isAuthenticated, $itemsLoaded, unload)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] items, isSignedIn, itemsLoaded, unload in
                // Until the list arrives it's empty; keep showing the last snapshot instead.
                guard !isSignedIn || itemsLoaded else { return }
                self?.updateWidget(Self.widgetSnapshot(
                    items: items,
                    isSignedIn: isSignedIn,
                    unloadEndDate: unload.0,
                    unloadOutstanding: unload.1
                ))
            }
            .store(in: &cancellables)
    }

    // MARK: - Widget

    static func widgetSnapshot(
        items: [GroceryItem],
        isSignedIn: Bool,
        unloadEndDate: Date?,
        unloadOutstanding: Bool = false,
        now: Date = Date()
    ) -> WidgetSnapshot {
        guard isSignedIn else { return .signedOut }
        return WidgetSnapshot(
            openTitles: items.filter { !$0.isCompleted }.map(\.title),
            unloadEndDate: unloadEndDate,
            unloadOutstanding: unloadOutstanding,
            now: now
        )
    }

    private func updateWidget(_ snapshot: WidgetSnapshot) {
        guard snapshot != lastWidgetSnapshot, let widgetStore else { return }
        lastWidgetSnapshot = snapshot
        try? widgetStore.save(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.groceries)
    }

    // MARK: - Daily reminder

    /// Reschedules the daily reminder with the current count and settings, once the session's list
    /// and preferences have both loaded (before that the count would be wrong).
    private func updateDailyReminder() async {
        guard sessionDataLoaded, let userId = currentUser?.id else { return }
        await notificationService.rescheduleRepeatingReminders(preferences: preferences, items: shoppingList)
        // Signed out while iOS was adding it, after signOut had removed the reminders.
        if currentUser?.id != userId {
            notificationService.removeReminders([NotificationID.dailyList])
        }
    }

    // MARK: - Location events

    /// A geofence enter can wake the app before the list and preferences have loaded (e.g. right
    /// after iOS relaunched it). Enters are queued and handled once the data is in, inside a
    /// background task so iOS gives the app time to load it.
    func handleLocationEvent(_ event: LocationEvent) {
        guard event.transition == .enter else { return }
        guard currentUser != nil || canRestoreSession else {
            diagnostics.record(.dropped, "Ignored \(Self.describe(event)): signed out", placeKind: event.kind)
            return
        }
        pendingLocationEvents.append(event)
        if !sessionDataLoaded {
            diagnostics.record(.queued, "Waiting for your list to load before handling the \(Self.describe(event))", placeKind: event.kind)
            beginBackgroundActivityIfNeeded()
        }
        processPendingLocationEvents()
    }

    enum LocationEventDecision: Equatable {
        case scheduleUnload(delay: TimeInterval, itemCount: Int, repeats: Bool, repeatInterval: TimeInterval)
        case notifyStore(itemCount: Int)
        case ignore(reason: String)
    }

    /// Events older than this are dropped rather than acted on late.
    static let maxEventAge: TimeInterval = 60 * 60

    /// A real enter this soon after the same place last produced a reminder is GPS jitter at the
    /// edge of the geofence, not a new visit.
    static func cooldown(for kind: GeoPlace.PlaceKind) -> TimeInterval {
        switch kind {
        case .home: return 15 * 60
        case .groceryStore: return 60 * 60
        }
    }

    /// What the app remembers from earlier events, for deciding on a new one.
    struct ReminderContext: Equatable {
        /// When this place last produced a reminder.
        var lastHandled: Date?
        /// When the groceries were last marked brought in. For home it also starts the cooldown,
        /// and items checked off before it are already inside.
        var lastUnloadDone: Date?
        /// When the phone last really entered a saved grocery store.
        var lastStoreVisit: Date?
        /// Whose phone this is; on a shared list, other people's check-offs aren't in this car.
        var userId: String?
    }

    static func decision(
        for event: LocationEvent,
        preferences: UserPreferences,
        items: [GroceryItem],
        now: Date,
        context: ReminderContext = ReminderContext()
    ) -> LocationEventDecision {
        guard event.transition == .enter else { return .ignore(reason: "left a place") }
        let elapsed = now.timeIntervalSince(event.date)
        guard elapsed <= maxEventAge else { return .ignore(reason: "the event is over an hour old") }
        let cooldownStart = event.kind == .home
            ? [context.lastHandled, context.lastUnloadDone].compactMap { $0 }.max()
            : context.lastHandled
        if !event.isSimulated, let lastHandled = cooldownStart {
            // Also covers an event older than the last handled time, e.g. queued before "All brought in".
            let sinceLast = event.date.timeIntervalSince(lastHandled)
            if sinceLast < cooldown(for: event.kind) {
                return .ignore(reason: "already handled \(describe(seconds: max(sinceLast, 0))) earlier")
            }
        }
        switch event.kind {
        case .home:
            guard let plan = carUnloadReminderPlan(
                preferences: preferences, items: items, now: now, context: context, isSimulated: event.isSimulated
            ) else {
                return .ignore(reason: event.isSimulated ? "nothing bought recently and no unchecked items" : noShoppingTripReason)
            }
            return .scheduleUnload(
                delay: effectiveDelay(configured: preferences.homeArrivalDelay, elapsed: elapsed),
                itemCount: plan.itemCount,
                repeats: plan.repeats,
                repeatInterval: plan.repeatInterval
            )
        case .groceryStore:
            let openCount = items.filter { !$0.isCompleted }.count
            guard shouldSendStoreReminder(preferences: preferences, openItemCount: openCount) else {
                return .ignore(reason: preferences.storeEntryReminderEnabled ? "no unchecked items on the list" : "store reminders are off")
            }
            return .notifyStore(itemCount: openCount)
        }
    }

    /// The reminder is due `configured` seconds after the arrival itself, even when the event is
    /// handled late; never sooner than 5 s from now.
    static func effectiveDelay(configured: TimeInterval, elapsed: TimeInterval) -> TimeInterval {
        max(configured - max(elapsed, 0), 5)
    }

    /// Only the latest home arrival and the latest store entry matter.
    static func coalesced(_ events: [LocationEvent]) -> [LocationEvent] {
        let enters = events.filter { $0.transition == .enter }
        return [enters.last { $0.kind == .home }, enters.last { $0.kind == .groceryStore }]
            .compactMap { $0 }
            .sorted { $0.date < $1.date }
    }

    /// Whether the event's place is still saved. A queued event can be for a place the loaded
    /// preferences no longer have: an old home, or a store deleted since.
    static func isSaved(_ event: LocationEvent, in preferences: UserPreferences) -> Bool {
        switch event.kind {
        case .home: return preferences.homeLocation?.id == event.placeId
        case .groceryStore: return preferences.savedStores.contains { $0.id == event.placeId }
        }
    }

    private func processPendingLocationEvents() {
        guard sessionDataLoaded, !pendingLocationEvents.isEmpty else { return }
        var events: [LocationEvent] = []
        for event in pendingLocationEvents {
            // Simulated events have no saved place behind them.
            if event.isSimulated || Self.isSaved(event, in: preferences) {
                events.append(event)
            } else {
                diagnostics.record(.dropped, "Ignored \(Self.describe(event)): place no longer saved", placeKind: event.kind, placeId: event.placeId)
            }
        }
        pendingLocationEvents.removeAll()
        recordStoreVisits(in: events)
        let now = Date()
        let userId = currentUser?.id
        let decisions = Self.coalesced(events).map { event in
            (event, Self.decision(
                for: event,
                preferences: preferences,
                items: shoppingList,
                now: now,
                context: ReminderContext(
                    lastHandled: cooldowns.lastHandled[Self.cooldownKey(event.kind, event.placeId)],
                    lastUnloadDone: cooldowns.lastUnloadDone,
                    lastStoreVisit: cooldowns.lastStoreVisit,
                    userId: userId
                )
            ))
        }
        locationBatchTask = Task {
            for (event, decision) in decisions {
                // Signed out (or into another account) meanwhile: don't start the timer, schedule
                // the reminder or recreate the cleared cooldowns. signOut ended the background activity.
                guard !Task.isCancelled, let userId, self.currentUser?.id == userId else { return }
                await self.apply(decision, for: event, userId: userId)
            }
            self.endBackgroundActivity()
        }
    }

    private func apply(_ decision: LocationEventDecision, for event: LocationEvent, userId: String) async {
        switch decision {
        case let .scheduleUnload(delay, itemCount, repeats, repeatInterval):
            homeArrivalTimer.start(duration: preferences.homeArrivalDelay, startedAt: event.date)
            let scheduledAt = Date()
            let scheduled = await notificationService.scheduleHomeArrivalReminder(
                after: delay,
                itemCount: itemCount,
                repeats: repeats,
                repeatInterval: repeatInterval,
                scheduledAt: scheduledAt
            )
            // Signed out while iOS was adding it, after signOut had removed the reminders.
            guard currentUser?.id == userId else {
                if scheduled { notificationService.removeReminders(NotificationID.carUnloadReminders) }
                return
            }
            // Not counted and no cooldown, so the next arrival tries again.
            guard scheduled else {
                diagnostics.record(.error, "Couldn't schedule the unload reminder: notifications not allowed?", placeKind: .home)
                return
            }
            let what = itemCount == 0 ? "your groceries" : "\(itemCount) item(s)"
            diagnostics.record(.unloadScheduled, "Unload reminder in \(Self.describe(seconds: delay)) for \(what)", placeKind: .home)
            recordHandled(event.kind, event.placeId, at: event.date)
            recordUnloadScheduled(at: scheduledAt)
        case .notifyStore(let itemCount):
            let sent = await notificationService.sendGroceryStoreReminder(itemCount: itemCount)
            guard currentUser?.id == userId else {
                if sent { notificationService.removeReminders([NotificationID.storeVisit]) }
                return
            }
            guard sent else {
                diagnostics.record(.error, "Couldn't send the store reminder: notifications not allowed?", placeKind: .groceryStore)
                return
            }
            diagnostics.record(.storeReminderSent, "Store reminder sent for \(itemCount) item(s)", placeKind: .groceryStore)
            recordHandled(event.kind, event.placeId, at: event.date)
        case .ignore(let reason):
            diagnostics.record(.skipped, "No reminder for the \(Self.describe(event)): \(reason)", placeKind: event.kind)
        }
    }

    /// Saved on the device so the cooldown and "already brought in" survive a relaunch.
    struct ReminderCooldowns: Codable, Equatable {
        /// When each place (by region ID) last produced a reminder.
        var lastHandled: [String: Date] = [:]
        var lastUnloadDone: Date?
        /// The last real enter into a saved grocery store, whether or not it sent a reminder.
        var lastStoreVisit: Date?
        /// When an unload reminder (or "Remind again") was last scheduled.
        var lastUnloadScheduled: Date?
    }

    static func cooldownKey(_ kind: GeoPlace.PlaceKind, _ placeId: String) -> String {
        "\(kind.rawValue):\(placeId)"
    }

    private func recordHandled(_ kind: GeoPlace.PlaceKind, _ placeId: String, at date: Date) {
        let key = Self.cooldownKey(kind, placeId)
        cooldowns.lastHandled[key] = max(cooldowns.lastHandled[key] ?? date, date)
        try? cooldownStore?.save(cooldowns)
    }

    private func recordUnloadScheduled(at date: Date) {
        cooldowns.lastUnloadScheduled = date
        try? cooldownStore?.save(cooldowns)
        refreshUnloadOutstanding(now: date)
    }

    /// A real store enter is evidence of a shopping trip even when it sends no reminder (inside the
    /// cooldown, or with store reminders off). Recorded before the batch's decisions, so a home
    /// arrival queued along with it already sees the visit.
    private func recordStoreVisits(in events: [LocationEvent]) {
        let visits = events.filter { $0.kind == .groceryStore && !$0.isSimulated }.map(\.date)
        guard let latest = visits.max() else { return }
        cooldowns.lastStoreVisit = max(cooldowns.lastStoreVisit ?? latest, latest)
        try? cooldownStore?.save(cooldowns)
    }

    private func beginBackgroundActivityIfNeeded() {
        guard backgroundActivityToken == nil else { return }
        backgroundActivityToken = backgroundActivity.begin(name: "Location wake-up") { [weak self] in
            self?.backgroundActivityExpired()
        }
    }

    private func backgroundActivityExpired() {
        if !pendingLocationEvents.isEmpty {
            diagnostics.record(.dropped, "Ran out of background time before your list loaded; \(pendingLocationEvents.count) event(s) dropped")
            pendingLocationEvents.removeAll()
        }
        endBackgroundActivity()
    }

    private func endBackgroundActivity() {
        guard let token = backgroundActivityToken else { return }
        backgroundActivityToken = nil
        backgroundActivity.end(token)
    }

    private static func describe(_ event: LocationEvent) -> String {
        let place = event.kind == .home ? "home arrival" : "store visit"
        return event.isSimulated ? "simulated " + place : place
    }

    static func describe(seconds: TimeInterval) -> String {
        seconds >= 60 ? "\(Int((seconds / 60).rounded())) min" : "\(Int(seconds)) s"
    }

    // MARK: - Reminder policy

    static func shouldSendStoreReminder(preferences: UserPreferences, openItemCount: Int) -> Bool {
        preferences.storeEntryReminderEnabled && openItemCount > 0
    }

    /// Items checked off this recently were bought on this trip, so they're in the car; a saved
    /// store entered this recently was a shopping trip.
    static let recentPurchaseWindow: TimeInterval = 3 * 60 * 60

    /// Logged for a real home arrival with no sign of shopping, so a field tester can see why nothing came.
    static let noShoppingTripReason = "no shopping trip in the last 3 h (check off what you bought, or visit a saved store)"

    /// An unload reminder needs a shopping trip, or every commute and dog walk would ask about
    /// groceries. Counts what was just bought (and not yet brought in); with nothing checked off, a
    /// recent visit to a saved store counts the unchecked items, where 0 means "your groceries".
    /// Simulated arrivals (demos, field tests) fall back to the unchecked items instead.
    /// Returns nil when there is nothing to unload.
    /// Only the context's user's check-offs count (items with no `completedBy` count too).
    static func carUnloadReminderPlan(
        preferences: UserPreferences,
        items: [GroceryItem],
        now: Date = Date(),
        context: ReminderContext = ReminderContext(),
        isSimulated: Bool = false
    ) -> (itemCount: Int, repeats: Bool, repeatInterval: TimeInterval)? {
        let boughtCount = items.filter { item in
            let age = now.timeIntervalSince(item.updatedAt)
            let alreadyInside = context.lastUnloadDone.map { item.updatedAt <= $0 } ?? false
            let boughtBySomeoneElse = item.completedBy.map { $0 != context.userId } ?? false
            return item.isCompleted && age >= 0 && age <= recentPurchaseWindow && !alreadyInside && !boughtBySomeoneElse
        }.count
        let uncheckedCount = items.filter { !$0.isCompleted }.count
        let itemCount: Int
        if boughtCount > 0 {
            itemCount = boughtCount
        } else if isSimulated {
            guard uncheckedCount > 0 else { return nil }
            itemCount = uncheckedCount
        } else if let visit = context.lastStoreVisit,
                  (0...recentPurchaseWindow).contains(now.timeIntervalSince(visit)),
                  context.lastUnloadDone.map({ visit > $0 }) ?? true {
            // Shopped without checking anything off: the unchecked items are the best guess.
            itemCount = uncheckedCount
        } else {
            return nil
        }
        return (itemCount, preferences.repeatCarUnloadReminder, preferences.carUnloadRepeatInterval)
    }

    // MARK: - Notification actions

    /// After a cold launch the list and preferences may not have loaded yet, so what the
    /// notification carries is preferred.
    /// - Parameters:
    ///   - itemCount: the count stored in the notification, preferred over counting `shoppingList`.
    ///   - repeatInterval: the interval stored in the notification, preferred over the preferences'.
    ///   - scheduledAt: when the notification was scheduled; "Remind again" does nothing if the
    ///     groceries were marked brought in since.
    func handleNotificationAction(
        _ actionIdentifier: String,
        category: String,
        itemCount: Int? = nil,
        repeatInterval: TimeInterval? = nil,
        scheduledAt: Date? = nil
    ) async {
        guard category == NotificationCategory.carUnload else { return }
        // A reminder left over from a signed-out account must not snooze, or start the next
        // account's cooldown. After a cold launch the session may still be restoring: handle it then.
        guard currentUser != nil || canRestoreSession else {
            diagnostics.record(.skipped, "Ignored a reminder action: signed out", placeKind: .home)
            return
        }
        switch actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            // Tapping the reminder itself opens the tab with "Mark groceries brought in".
            requestedTab = .arrival
        case NotificationAction.markDone:
            // From any reminder, however old: the groceries are in now.
            markUnloadComplete(source: "notification")
        case NotificationAction.snooze:
            if let scheduledAt, let done = lastUnloadDone, done >= scheduledAt {
                diagnostics.record(.skipped, "Remind again: the groceries were already brought in", placeKind: .home)
                return
            }
            // Also catches a reminder from hours ago still sitting in Notification Center.
            refreshUnloadOutstanding()
            guard unloadOutstanding else {
                diagnostics.record(.skipped, "Remind again: nothing to unload (already brought in, or the reminder is over 3 h old)", placeKind: .home)
                return
            }
            // A count of 0 in the notification is a reminder about "your groceries"; it repeats as is.
            guard let openCount = itemCount ?? (itemsLoaded ? shoppingList.filter { !$0.isCompleted }.count : nil) else {
                diagnostics.record(.skipped, "Remind again: no item count and the list hasn't loaded", placeKind: .home)
                return
            }
            let stored = repeatInterval ?? 0
            let interval = stored > 0 ? stored : preferences.carUnloadRepeatInterval
            let snoozedAt = Date()
            // Keeps the interval in the new reminder, so "Remind again" on it repeats the same way.
            let scheduled = await notificationService.scheduleHomeArrivalReminder(
                after: interval,
                itemCount: openCount,
                repeats: false,
                repeatInterval: interval,
                scheduledAt: snoozedAt
            )
            guard scheduled else {
                diagnostics.record(.error, "Couldn't schedule the reminder again: notifications not allowed?", placeKind: .home)
                return
            }
            recordUnloadScheduled(at: snoozedAt)
            diagnostics.record(.snoozed, "Remind again in \(Self.describe(seconds: interval))", placeKind: .home)
        default:
            break
        }
    }

    /// Every "groceries are in" path (notification action or in-app button) goes through here.
    func markUnloadComplete(source: String, now: Date = Date()) {
        homeArrivalTimer.completeUnload()
        notificationService.markCarUnloadComplete()
        diagnostics.record(.unloadDone, "Groceries brought in (\(source))", placeKind: .home)
        // Not keyed by place: after a cold launch from the notification, the preferences (and the
        // real home ID) may not have loaded yet.
        cooldowns.lastUnloadDone = max(cooldowns.lastUnloadDone ?? now, now)
        try? cooldownStore?.save(cooldowns)
        refreshUnloadOutstanding()
    }

    /// When the groceries were last marked brought in.
    var lastUnloadDone: Date? { cooldowns.lastUnloadDone }

    /// When the phone last really entered a saved grocery store.
    var lastStoreVisit: Date? { cooldowns.lastStoreVisit }

    /// When an unload reminder (or "Remind again") was last scheduled.
    var lastUnloadScheduled: Date? { cooldowns.lastUnloadScheduled }

    /// How long after it was scheduled an unload reminder still counts as outstanding.
    static let outstandingUnloadWindow: TimeInterval = 3 * 60 * 60

    /// A reminder was scheduled in the last 3 h and nothing was marked brought in since.
    static func isUnloadOutstanding(scheduled: Date?, done: Date?, now: Date) -> Bool {
        guard let scheduled else { return false }
        let notDoneSince = done.map { $0 < scheduled } ?? true
        return notDoneSince && now.timeIntervalSince(scheduled) <= outstandingUnloadWindow
    }

    /// Also called when the app becomes active, since the 3 h can run out while it's in the background.
    func refreshUnloadOutstanding(now: Date = Date()) {
        let outstanding = Self.isUnloadOutstanding(scheduled: cooldowns.lastUnloadScheduled, done: cooldowns.lastUnloadDone, now: now)
        if outstanding != unloadOutstanding {
            unloadOutstanding = outstanding
        }
    }

    // MARK: - App lifecycle

    /// The app came to the foreground. The countdown's Timer doesn't fire in the background, the
    /// outstanding unload can expire and reminders can be delivered, so all three are refreshed.
    func appDidBecomeActive() {
        homeArrivalTimer.refresh()
        refreshUnloadOutstanding()
        Task { await notificationService.refreshPendingCount() }
    }

    // MARK: - Session

    /// Called at launch: a user still signed in from last time (Firebase, or the saved demo backend)
    /// skips the sign-in screen.
    func restoreSession() {
        authService.restoreSession { [weak self] user in
            guard let self, self.canRestoreSession else { return }
            self.diagnostics.record(.session, "Restored the saved sign-in")
            self.startSession(for: user)
        }
    }

    func signIn(email: String, password: String) async throws {
        canRestoreSession = false
        let user = try await authService.signIn(email: email, password: password)
        startSession(for: user)
    }

    func signUp(email: String, password: String, displayName: String) async throws {
        canRestoreSession = false
        let user = try await authService.signUp(email: email, password: password, displayName: displayName)
        startSession(for: user)
    }

    func signOut() {
        authService.signOut()
        stopSync()
        pendingLocationEvents.removeAll()
        locationBatchTask?.cancel()
        locationBatchTask = nil
        endBackgroundActivity()
        isAuthenticated = false
        currentUser = nil
        // Don't leave this account's list or places on screen for whoever signs in next.
        shoppingList = []
        preferences = .default
        locationService.stopMonitoring()
        homeArrivalTimer.cancel()
        // The daily list, unload and store reminders belong to this account.
        notificationService.removeAllReminders()
        cooldowns = ReminderCooldowns()
        cooldownStore?.remove()
        refreshUnloadOutstanding()
        requestedTab = nil
    }

    /// Emails a link to choose a new password.
    func sendPasswordReset(email: String) async throws {
        try await authService.sendPasswordReset(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Deletes the account and everything stored for it (App Store guideline 5.1.1(v)). The password
    /// is checked first, so a wrong one changes nothing.
    func deleteAccount(password: String) async throws {
        guard let user = currentUser else { throw SharedListError.notSignedIn }
        try await authService.reauthenticate(password: password)
        // The active-list listener would see the user document go and create the list again.
        stopSync()
        do {
            try await listService.deleteAllData(userId: user.id)
            try await authService.deleteAccount()
        } catch {
            // The account is still there: carry on with it, so deleting can be tried again.
            if currentUser?.id == user.id {
                startSync(for: user)
            }
            throw error
        }
        signOut()
        // The on-device log and stats describe this account's places and reminders.
        diagnostics.clear()
    }

    private func startSession(for user: AppUser) {
        canRestoreSession = false
        currentUser = user
        isAuthenticated = true
        startSync(for: user)
        Task {
            await self.notificationService.requestAuthorization()
            self.locationService.requestAuthorization()
        }
    }

    // MARK: - Sync

    /// Streams the user's list and preferences into published state until `stopSync()`.
    /// Geofences are (re)armed whenever the preferences arrive or change. The items follow the
    /// active list, which changes when the user joins or leaves a shared list.
    func startSync(for user: AppUser) {
        stopSync()
        activeListTask = Task { [weak self, listService] in
            do {
                for try await listId in await listService.observeActiveList(userId: user.id) {
                    guard !Task.isCancelled, let self else { return }
                    if listId != self.activeListId || self.itemsSyncTask == nil {
                        self.observeItems(of: listId, userId: user.id)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.syncErrorMessage = "Couldn't load your list: \(error.localizedDescription)"
            }
        }
        preferencesSyncTask = Task { [weak self, listService] in
            do {
                for try await preferences in await listService.observePreferences(userId: user.id) {
                    guard !Task.isCancelled else { return }
                    self?.applyLoadedPreferences(preferences)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.syncErrorMessage = "Couldn't sync your settings: \(error.localizedDescription)"
            }
        }
    }

    private func applyLoadedPreferences(_ loaded: UserPreferences) {
        // Echoes of our own saves (and Firestore metadata-only updates) change nothing.
        guard !preferencesLoaded || loaded != preferences else { return }
        preferences = loaded
        preferencesLoaded = true
        locationService.startMonitoring(home: loaded.homeLocation, stores: loaded.savedStores)
        processPendingLocationEvents()
    }

    private func observeItems(of listId: String, userId: String) {
        itemsSyncTask?.cancel()
        activeListId = listId
        sharedList = nil
        itemsSyncTask = Task { [weak self, listService] in
            do {
                for try await items in await listService.observeItems(listId: listId, userId: userId) {
                    // A value buffered before sign-out or a list switch must not bring the old list back.
                    guard !Task.isCancelled, let self else { return }
                    self.shoppingList = items
                    self.itemsLoaded = true
                    self.processPendingLocationEvents()
                }
            } catch {
                guard !Task.isCancelled, let self else { return }
                if error as? SharedListError == .removedFromList, listId != userId {
                    await self.handleRemoval(from: listId, userId: userId)
                } else {
                    self.syncErrorMessage = "Couldn't sync your list: \(error.localizedDescription)"
                }
            }
        }
        Task { await refreshSharedList() }
    }

    /// The owner removed this user from their list (or deleted it): the listener is denied, and
    /// Leave is the way back, which works for a removed member too.
    private func handleRemoval(from listId: String, userId: String) async {
        guard currentUser?.id == userId, activeListId == listId else { return }
        if isSwitchingList {
            // Likely a join the server hasn't applied yet; `switchList` tries again once it has.
            itemsSyncTask = nil
            itemsDeniedDuringSwitch = true
            return
        }
        syncErrorMessage = SharedListError.removedFromList.errorDescription
        try? await listService.leaveList(userId: userId)
    }

    func refreshSharedList() async {
        guard let listId = activeListId else { return }
        let info = try? await listService.listInfo(listId: listId)
        // The user may have switched lists while this was loading.
        guard listId == activeListId else { return }
        sharedList = info
    }

    private func stopSync() {
        activeListTask?.cancel()
        itemsSyncTask?.cancel()
        preferencesSyncTask?.cancel()
        activeListTask = nil
        itemsSyncTask = nil
        preferencesSyncTask = nil
        preferencesLoaded = false
        itemsLoaded = false
        syncErrorMessage = nil
        activeListId = nil
        sharedList = nil
    }

    // MARK: - Shared lists

    /// A code someone else can enter to join this user's own list.
    func createInvite() async throws -> String {
        guard let userId = currentUser?.id else { throw SharedListError.notSignedIn }
        return try await listService.createInvite(userId: userId)
    }

    func joinList(code: String) async throws {
        try await switchList { listService, userId in
            try await listService.joinList(code: code, userId: userId)
        }
    }

    func leaveSharedList() async throws {
        try await switchList { listService, userId in
            try await listService.leaveList(userId: userId)
        }
    }

    /// Stops listening to the current list's items before the membership changes, so the old
    /// listener doesn't report "permission denied" once the user is no longer a member. The
    /// active-list stream then starts the new list's items; on failure the old list resumes.
    private func switchList(_ change: (ShoppingListServiceProtocol, String) async throws -> Void) async throws {
        guard let userId = currentUser?.id else { throw SharedListError.notSignedIn }
        let previous = activeListId
        itemsSyncTask?.cancel()
        itemsSyncTask = nil
        isSwitchingList = true
        itemsDeniedDuringSwitch = false
        defer { isSwitchingList = false }
        do {
            try await change(listService, userId)
        } catch {
            if itemsSyncTask == nil, let previous {
                observeItems(of: previous, userId: userId)
            }
            throw error
        }
        if itemsDeniedDuringSwitch, itemsSyncTask == nil, currentUser?.id == userId, let listId = activeListId {
            observeItems(of: listId, userId: userId)
        }
    }

    // MARK: - Editing

    func addItem(_ title: String, notes: String = "", aisle: String = "") async {
        let item = GroceryItem(title: title, notes: notes, aisle: aisle)
        shoppingList.insert(item, at: 0)
        guard let listId = editableListId else { return }
        try? await listService.upsert(item: item, listId: listId)
    }

    func toggleItem(_ item: GroceryItem) async {
        guard let index = shoppingList.firstIndex(where: { $0.id == item.id }) else { return }
        shoppingList[index].isCompleted.toggle()
        shoppingList[index].completedBy = shoppingList[index].isCompleted ? currentUser?.id : nil
        shoppingList[index].updatedAt = Date()
        guard let listId = editableListId else { return }
        // An update, not an upsert: if someone else deleted the item meanwhile, it stays deleted.
        try? await listService.update(item: shoppingList[index], listId: listId)
    }

    func deleteItems(at offsets: IndexSet) async {
        let removed = offsets.map { shoppingList[$0] }
        shoppingList.remove(atOffsets: offsets)
        guard let listId = editableListId else { return }
        for item in removed {
            try? await listService.delete(itemId: item.id, listId: listId)
        }
    }

    /// Where edits go: the active list, or the user's own list before it has resolved.
    private var editableListId: String? {
        guard let userId = currentUser?.id else { return nil }
        return activeListId ?? userId
    }

    // MARK: - Siri & Shortcuts

    /// The running app's state, for entry points outside SwiftUI (App Intents). Set by `AppDelegate`.
    static weak var shared: AppState?

    /// Adds an item from Siri / Shortcuts and returns the trimmed title that was added.
    func quickAdd(_ rawTitle: String) async throws -> String {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw QuickAddError.emptyItem }
        guard isAuthenticated else { throw QuickAddError.notSignedIn }
        await addItem(title)
        return title
    }

    // MARK: - Places

    /// iOS monitors at most 20 regions per app; one is kept for home.
    static let maxStores = 19

    enum AddStoreResult: Equatable {
        case added, duplicate, limitReached
    }

    /// Adds a store unless one is already saved within 50 m or the geofence limit is reached.
    func addStore(_ store: GeoPlace) async -> AddStoreResult {
        if preferences.savedStores.contains(where: { $0.distance(to: store) < 50 }) {
            return .duplicate
        }
        guard preferences.savedStores.count < Self.maxStores else { return .limitReached }
        preferences.savedStores.append(store)
        await savePreferences()
        return .added
    }

    func setHome(_ home: GeoPlace) async {
        preferences.homeLocation = home
        await savePreferences()
    }

    /// The daily reminder follows the preferences on its own (see `bindServices`).
    func savePreferences() async {
        guard preferencesLoaded, let userId = currentUser?.id else { return }
        try? await listService.savePreferences(preferences, userId: userId)
        locationService.startMonitoring(home: preferences.homeLocation, stores: preferences.savedStores)
    }
}
