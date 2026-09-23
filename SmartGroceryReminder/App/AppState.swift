import Foundation
import Combine

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
    private var preferencesSyncTask: Task<Void, Never>?
    private let backgroundActivity: BackgroundActivityProviding
    private var backgroundActivityToken: Int?

    /// - Parameters:
    ///   - mockStorageDirectory: where the demo backend saves accounts, lists and preferences.
    ///     `nil` (tests, previews) keeps them in memory.
    ///   - diagnostics: the event log; `nil` keeps entries in memory.
    ///   - backgroundActivity: extra background time while a location wake-up waits for data; `nil` for none.
    init(
        useMockBackend: Bool = true,
        mockStorageDirectory: URL? = nil,
        diagnostics: DiagnosticsLog? = nil,
        backgroundActivity: BackgroundActivityProviding? = nil
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
        self.backgroundActivity = backgroundActivity ?? NoBackgroundActivity()
        self.locationService = LocationService(diagnostics: diagnostics)
        self.notificationService = NotificationService()
        self.homeArrivalTimer = HomeArrivalTimerService()

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

    static func decision(
        for event: LocationEvent,
        preferences: UserPreferences,
        items: [GroceryItem],
        now: Date
    ) -> LocationEventDecision {
        guard event.transition == .enter else { return .ignore(reason: "left a place") }
        let elapsed = now.timeIntervalSince(event.date)
        guard elapsed <= maxEventAge else { return .ignore(reason: "the event is over an hour old") }
        switch event.kind {
        case .home:
            guard let plan = carUnloadReminderPlan(preferences: preferences, items: items) else {
                return .ignore(reason: "no unchecked items on the list")
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
            (event, Self.decision(for: event, preferences: preferences, items: shoppingList, now: now))
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
        case .notifyStore(let itemCount):
            await notificationService.sendGroceryStoreReminder(itemCount: itemCount)
            diagnostics.record(.storeReminderSent, "Store reminder sent for \(itemCount) item(s)", placeKind: .groceryStore)
        case .ignore(let reason):
            diagnostics.record(.skipped, "No reminder for the \(Self.describe(event)): \(reason)", placeKind: event.kind)
        }
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

    /// Returns nil when there is nothing left to unload.
    static func carUnloadReminderPlan(
        preferences: UserPreferences,
        items: [GroceryItem]
    ) -> (itemCount: Int, repeats: Bool, repeatInterval: TimeInterval)? {
        let openCount = items.filter { !$0.isCompleted }.count
        guard openCount > 0 else { return nil }
        return (openCount, preferences.repeatCarUnloadReminder, preferences.carUnloadRepeatInterval)
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
    func markUnloadComplete(source: String) {
        homeArrivalTimer.completeUnload()
        notificationService.markCarUnloadComplete()
        diagnostics.record(.unloadDone, "Groceries brought in (\(source))", placeKind: .home)
    }

    // MARK: - Session

    /// Called at launch: a user still signed in from last time (Firebase, or the saved demo backend)
    /// skips the sign-in screen.
    func restoreSession() {
        authService.restoreSession { [weak self] user in
            guard let self, self.canRestoreSession else { return }
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
    /// Geofences are (re)armed whenever the preferences arrive or change.
    func startSync(for user: AppUser) {
        stopSync()
        itemsSyncTask = Task { [weak self, listService] in
            do {
                for try await items in await listService.observeItems(userId: user.id) {
                    // A value buffered before sign-out must not bring the old list back.
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

    private func stopSync() {
        itemsSyncTask?.cancel()
        preferencesSyncTask?.cancel()
        itemsSyncTask = nil
        preferencesSyncTask = nil
        preferencesLoaded = false
        itemsLoaded = false
        syncErrorMessage = nil
    }

    // MARK: - Editing

    func addItem(_ title: String, notes: String = "", aisle: String = "") async {
        let item = GroceryItem(title: title, notes: notes, aisle: aisle)
        shoppingList.insert(item, at: 0)
        guard let userId = currentUser?.id else { return }
        try? await listService.upsert(item: item, userId: userId)
    }

    func toggleItem(_ item: GroceryItem) async {
        guard let index = shoppingList.firstIndex(where: { $0.id == item.id }) else { return }
        shoppingList[index].isCompleted.toggle()
        shoppingList[index].updatedAt = Date()
        guard let userId = currentUser?.id else { return }
        try? await listService.upsert(item: shoppingList[index], userId: userId)
    }

    func deleteItems(at offsets: IndexSet) async {
        let removed = offsets.map { shoppingList[$0] }
        shoppingList.remove(atOffsets: offsets)
        guard let userId = currentUser?.id else { return }
        for item in removed {
            try? await listService.delete(itemId: item.id, userId: userId)
        }
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
