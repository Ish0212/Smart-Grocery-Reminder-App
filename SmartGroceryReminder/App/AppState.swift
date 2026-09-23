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
    /// Set when live sync with the backend fails (e.g. Firestore rules deny access).
    @Published private(set) var syncErrorMessage: String?

    let authService: AuthServiceProtocol
    let listService: ShoppingListServiceProtocol
    let locationService: LocationService
    let notificationService: NotificationService
    let homeArrivalTimer: HomeArrivalTimerService

    private var cancellables = Set<AnyCancellable>()
    /// Cleared once a session starts, so a late restore can't replace a manual sign-in.
    private var canRestoreSession = true
    private var itemsSyncTask: Task<Void, Never>?
    private var preferencesSyncTask: Task<Void, Never>?

    init(useMockBackend: Bool = true) {
        self.useMockBackend = useMockBackend
        self.authService = useMockBackend ? MockAuthService() : FirebaseAuthService()
        self.listService = useMockBackend ? MockShoppingListService() : FirestoreShoppingListService()
        self.locationService = LocationService()
        self.notificationService = NotificationService()
        self.homeArrivalTimer = HomeArrivalTimerService()

        self.isAuthenticated = false
        self.currentUser = nil
        self.shoppingList = useMockBackend ? SampleData.groceryItems : []
        self.preferences = .default

        bindServices()
    }

    private func bindServices() {
        homeArrivalTimer.$isActive
            .receive(on: RunLoop.main)
            .sink { [weak self] active in
                guard let self, active else { return }
                Task { await self.scheduleCarUnloadReminderIfNeeded() }
            }
            .store(in: &cancellables)

        locationService.$didArriveHome
            .receive(on: RunLoop.main)
            .sink { [weak self] arrived in
                guard let self, arrived else { return }
                self.homeArrivalTimer.start(duration: self.preferences.homeArrivalDelay)
                self.locationService.consumeHomeArrival()
            }
            .store(in: &cancellables)

        locationService.$didEnterGroceryStore
            .receive(on: RunLoop.main)
            .sink { [weak self] entered in
                guard let self, entered else { return }
                let openCount = self.shoppingList.filter { !$0.isCompleted }.count
                self.locationService.consumeStoreEntry()
                guard Self.shouldSendStoreReminder(preferences: self.preferences, openItemCount: openCount) else { return }
                Task {
                    await self.notificationService.sendGroceryStoreReminder(itemCount: openCount)
                }
            }
            .store(in: &cancellables)
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

    func handleNotificationAction(_ actionIdentifier: String, category: String) async {
        guard category == NotificationCategory.carUnload else { return }
        switch actionIdentifier {
        case NotificationAction.markDone:
            homeArrivalTimer.completeUnload()
            notificationService.markCarUnloadComplete()
        case NotificationAction.snooze:
            let openCount = shoppingList.filter { !$0.isCompleted }.count
            guard openCount > 0 else { return }
            await notificationService.scheduleHomeArrivalReminder(
                after: preferences.carUnloadRepeatInterval,
                itemCount: openCount,
                repeats: false,
                repeatInterval: 0
            )
        default:
            break
        }
    }

    // MARK: - Session

    /// Called at launch: a user still signed in from last time (Firebase only) skips the sign-in screen.
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
                    guard !Task.isCancelled else { return }
                    self?.shoppingList = items
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
    }

    private func stopSync() {
        itemsSyncTask?.cancel()
        preferencesSyncTask?.cancel()
        itemsSyncTask = nil
        preferencesSyncTask = nil
        preferencesLoaded = false
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

    func savePreferences() async {
        guard preferencesLoaded, let userId = currentUser?.id else { return }
        try? await listService.savePreferences(preferences, userId: userId)
        locationService.startMonitoring(home: preferences.homeLocation, stores: preferences.savedStores)
        await notificationService.rescheduleRepeatingReminders(preferences: preferences, items: shoppingList)
    }

    private func scheduleCarUnloadReminderIfNeeded() async {
        guard let plan = Self.carUnloadReminderPlan(preferences: preferences, items: shoppingList) else { return }
        await notificationService.scheduleHomeArrivalReminder(
            after: preferences.homeArrivalDelay,
            itemCount: plan.itemCount,
            repeats: plan.repeats,
            repeatInterval: plan.repeatInterval
        )
    }
}
