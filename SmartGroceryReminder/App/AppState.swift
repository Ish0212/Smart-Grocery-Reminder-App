import Foundation
import Combine
import WidgetKit

@MainActor
final class AppState: ObservableObject {
    @Published var isAuthenticated: Bool
    @Published var currentUser: AppUser?
    @Published var shoppingList: [GroceryItem]
    @Published var preferences: UserPreferences
    @Published var useMockBackend: Bool
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

    /// Location events wait here until the session's list and preferences have loaded.
    private(set) var pendingLocationEvents: [LocationEvent] = []
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
    init(
        useMockBackend: Bool = true,
        mockStorageDirectory: URL? = nil,
        diagnostics: DiagnosticsLog? = nil,
        backgroundActivity: BackgroundActivityProviding? = nil,
        stateDirectory: URL? = nil,
        widgetStore: WidgetSnapshotStore? = nil
    ) {
        // Defaults are created here: in Swift 5 mode a default argument can't call a main-actor initializer.
        let diagnostics = diagnostics ?? DiagnosticsLog()
        self.useMockBackend = useMockBackend
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
        self.locationService = LocationService(diagnostics: diagnostics)
        self.notificationService = NotificationService()
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

        bindServices()
    }

    private func bindServices() {
        // Delivered synchronously on the main actor, so no event is lost before it is handled.
        locationService.events
            .sink { [weak self] event in
                self?.handleLocationEvent(event)
            }
            .store(in: &cancellables)

        // Coalesced, so a sync burst or a background relaunch reloads the widget once.
        guard widgetStore != nil else { return }
        Publishers.CombineLatest4($shoppingList, $isAuthenticated, $itemsLoaded, homeArrivalTimer.$endDate)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] items, isSignedIn, itemsLoaded, endDate in
                // Until the list arrives it's empty; keep showing the last snapshot instead.
                guard !isSignedIn || itemsLoaded else { return }
                self?.updateWidget(Self.widgetSnapshot(items: items, isSignedIn: isSignedIn, unloadEndDate: endDate))
            }
            .store(in: &cancellables)
    }

    // MARK: - Widget

    static func widgetSnapshot(items: [GroceryItem], isSignedIn: Bool, unloadEndDate: Date?, now: Date = Date()) -> WidgetSnapshot {
        guard isSignedIn else { return .signedOut }
        return WidgetSnapshot(
            openTitles: items.filter { !$0.isCompleted }.map(\.title),
            unloadEndDate: unloadEndDate,
            now: now
        )
    }

    private func updateWidget(_ snapshot: WidgetSnapshot) {
        guard snapshot != lastWidgetSnapshot, let widgetStore else { return }
        lastWidgetSnapshot = snapshot
        try? widgetStore.save(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.groceries)
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

    /// - Parameters:
    ///   - lastHandled: when this place last produced a reminder.
    ///   - lastUnloadDone: when the groceries were last marked brought in. For home it also starts
    ///     the cooldown, and items checked off before it are already inside.
    ///   - userId: whose phone this is; on a shared list, other people's check-offs aren't in this car.
    static func decision(
        for event: LocationEvent,
        preferences: UserPreferences,
        items: [GroceryItem],
        now: Date,
        lastHandled: Date? = nil,
        lastUnloadDone: Date? = nil,
        userId: String? = nil
    ) -> LocationEventDecision {
        guard event.transition == .enter else { return .ignore(reason: "left a place") }
        let elapsed = now.timeIntervalSince(event.date)
        guard elapsed <= maxEventAge else { return .ignore(reason: "the event is over an hour old") }
        let cooldownStart = event.kind == .home
            ? [lastHandled, lastUnloadDone].compactMap { $0 }.max()
            : lastHandled
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
                preferences: preferences, items: items, now: now, lastUnloadDone: lastUnloadDone, userId: userId
            ) else {
                return .ignore(reason: "nothing bought recently and no unchecked items")
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

    private func processPendingLocationEvents() {
        guard sessionDataLoaded, !pendingLocationEvents.isEmpty else { return }
        let now = Date()
        let decisions = Self.coalesced(pendingLocationEvents).map { event in
            (event, Self.decision(
                for: event,
                preferences: preferences,
                items: shoppingList,
                now: now,
                lastHandled: cooldowns.lastHandled[Self.cooldownKey(event.kind, event.placeId)],
                lastUnloadDone: cooldowns.lastUnloadDone,
                userId: currentUser?.id
            ))
        }
        pendingLocationEvents.removeAll()
        Task {
            for (event, decision) in decisions {
                await self.apply(decision, for: event)
            }
            self.endBackgroundActivity()
        }
    }

    private func apply(_ decision: LocationEventDecision, for event: LocationEvent) async {
        switch decision {
        case let .scheduleUnload(delay, itemCount, repeats, repeatInterval):
            homeArrivalTimer.start(duration: preferences.homeArrivalDelay, startedAt: event.date)
            await notificationService.scheduleHomeArrivalReminder(
                after: delay,
                itemCount: itemCount,
                repeats: repeats,
                repeatInterval: repeatInterval
            )
            diagnostics.record(.unloadScheduled, "Unload reminder in \(Self.describe(seconds: delay)) for \(itemCount) item(s)", placeKind: .home)
            recordHandled(event.kind, event.placeId, at: event.date)
        case .notifyStore(let itemCount):
            await notificationService.sendGroceryStoreReminder(itemCount: itemCount)
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
    }

    static func cooldownKey(_ kind: GeoPlace.PlaceKind, _ placeId: String) -> String {
        "\(kind.rawValue):\(placeId)"
    }

    private func recordHandled(_ kind: GeoPlace.PlaceKind, _ placeId: String, at date: Date) {
        let key = Self.cooldownKey(kind, placeId)
        cooldowns.lastHandled[key] = max(cooldowns.lastHandled[key] ?? date, date)
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

    /// Items checked off this recently were bought on this trip, so they're in the car.
    static let recentPurchaseWindow: TimeInterval = 3 * 60 * 60

    /// Counts what was just bought (and not yet brought in); with nothing bought recently, falls
    /// back to the unchecked items. Returns nil when there is nothing to unload.
    /// - Parameter userId: only this user's check-offs count (items with no `completedBy` count too).
    static func carUnloadReminderPlan(
        preferences: UserPreferences,
        items: [GroceryItem],
        now: Date = Date(),
        lastUnloadDone: Date? = nil,
        userId: String? = nil
    ) -> (itemCount: Int, repeats: Bool, repeatInterval: TimeInterval)? {
        let boughtCount = items.filter { item in
            let age = now.timeIntervalSince(item.updatedAt)
            let alreadyInside = lastUnloadDone.map { item.updatedAt <= $0 } ?? false
            let boughtBySomeoneElse = item.completedBy.map { $0 != userId } ?? false
            return item.isCompleted && age >= 0 && age <= recentPurchaseWindow && !alreadyInside && !boughtBySomeoneElse
        }.count
        let itemCount = boughtCount > 0 ? boughtCount : items.filter { !$0.isCompleted }.count
        guard itemCount > 0 else { return nil }
        return (itemCount, preferences.repeatCarUnloadReminder, preferences.carUnloadRepeatInterval)
    }

    // MARK: - Notification actions

    /// - Parameter itemCount: the count stored in the notification. After a cold launch the list
    ///   may not have loaded yet, so it is preferred over counting `shoppingList`.
    func handleNotificationAction(_ actionIdentifier: String, category: String, itemCount: Int? = nil) async {
        guard category == NotificationCategory.carUnload else { return }
        switch actionIdentifier {
        case NotificationAction.markDone:
            markUnloadComplete(source: "notification")
        case NotificationAction.snooze:
            let openCount = itemCount ?? (itemsLoaded ? shoppingList.filter { !$0.isCompleted }.count : 0)
            guard openCount > 0 else {
                diagnostics.record(.skipped, "Remind again: no item count and the list hasn't loaded", placeKind: .home)
                return
            }
            await notificationService.scheduleHomeArrivalReminder(
                after: preferences.carUnloadRepeatInterval,
                itemCount: openCount,
                repeats: false,
                repeatInterval: 0
            )
            diagnostics.record(.snoozed, "Remind again in \(Self.describe(seconds: preferences.carUnloadRepeatInterval))", placeKind: .home)
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
    }

    /// When the groceries were last marked brought in.
    var lastUnloadDone: Date? { cooldowns.lastUnloadDone }


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
        endBackgroundActivity()
        isAuthenticated = false
        currentUser = nil
        // Don't leave this account's list or places on screen for whoever signs in next.
        shoppingList = []
        preferences = .default
        locationService.stopMonitoring()
        homeArrivalTimer.cancel()
        cooldowns = ReminderCooldowns()
        cooldownStore?.remove()
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
                        self.observeItems(of: listId)
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

    private func observeItems(of listId: String) {
        itemsSyncTask?.cancel()
        activeListId = listId
        sharedList = nil
        itemsSyncTask = Task { [weak self, listService] in
            do {
                for try await items in await listService.observeItems(listId: listId) {
                    // A value buffered before sign-out or a list switch must not bring the old list back.
                    guard !Task.isCancelled, let self else { return }
                    self.shoppingList = items
                    self.itemsLoaded = true
                    self.processPendingLocationEvents()
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.syncErrorMessage = "Couldn't sync your list: \(error.localizedDescription)"
            }
        }
        Task { await refreshSharedList() }
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
        do {
            try await change(listService, userId)
        } catch {
            if itemsSyncTask == nil, let previous {
                observeItems(of: previous)
            }
            throw error
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
        try? await listService.upsert(item: shoppingList[index], listId: listId)
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

    func savePreferences() async {
        guard preferencesLoaded, let userId = currentUser?.id else { return }
        try? await listService.savePreferences(preferences, userId: userId)
        locationService.startMonitoring(home: preferences.homeLocation, stores: preferences.savedStores)
        await notificationService.rescheduleRepeatingReminders(preferences: preferences, items: shoppingList)
    }
}
