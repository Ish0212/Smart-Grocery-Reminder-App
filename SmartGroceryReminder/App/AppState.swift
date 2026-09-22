import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var isAuthenticated: Bool
    @Published var currentUser: AppUser?
    @Published var shoppingList: [GroceryItem]
    @Published var preferences: UserPreferences
    @Published var useMockBackend: Bool

    let authService: AuthServiceProtocol
    let listService: ShoppingListServiceProtocol
    let locationService: LocationService
    let notificationService: NotificationService
    let homeArrivalTimer: HomeArrivalTimerService

    private var cancellables = Set<AnyCancellable>()

    init(useMockBackend: Bool = true) {
        self.useMockBackend = useMockBackend
        self.authService = useMockBackend ? MockAuthService() : FirebaseAuthService()
        self.listService = useMockBackend ? MockShoppingListService() : FirestoreShoppingListService()
        self.locationService = LocationService()
        self.notificationService = NotificationService()
        self.homeArrivalTimer = HomeArrivalTimerService()

        self.isAuthenticated = false
        self.currentUser = nil
        self.shoppingList = SampleData.groceryItems
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
            }
            .store(in: &cancellables)

        locationService.$didEnterGroceryStore
            .receive(on: RunLoop.main)
            .sink { [weak self] entered in
                guard let self, entered else { return }
                Task {
                    await self.notificationService.sendGroceryStoreReminder(
                        itemCount: self.shoppingList.filter { !$0.isCompleted }.count
                    )
                }
            }
            .store(in: &cancellables)
    }

    func signIn(email: String, password: String) async throws {
        let user = try await authService.signIn(email: email, password: password)
        currentUser = user
        isAuthenticated = true
        preferences = try await listService.fetchPreferences(userId: user.id)
        shoppingList = try await listService.fetchItems(userId: user.id)
        await notificationService.requestAuthorization()
        locationService.requestAuthorization()
        locationService.startMonitoring(home: preferences.homeLocation, stores: preferences.savedStores)
    }

    func signUp(email: String, password: String, displayName: String) async throws {
        let user = try await authService.signUp(email: email, password: password, displayName: displayName)
        currentUser = user
        isAuthenticated = true
        preferences = .default
        shoppingList = []
        await notificationService.requestAuthorization()
        locationService.requestAuthorization()
    }

    func signOut() {
        authService.signOut()
        isAuthenticated = false
        currentUser = nil
        locationService.stopMonitoring()
        homeArrivalTimer.cancel()
    }

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
        guard let userId = currentUser?.id else { return }
        try? await listService.savePreferences(preferences, userId: userId)
        locationService.startMonitoring(home: preferences.homeLocation, stores: preferences.savedStores)
        await notificationService.rescheduleRepeatingReminders(preferences: preferences, items: shoppingList)
    }

    private func scheduleCarUnloadReminderIfNeeded() async {
        let incomplete = shoppingList.filter { !$0.isCompleted }
        guard !incomplete.isEmpty else { return }
        await notificationService.scheduleHomeArrivalReminder(
            after: preferences.homeArrivalDelay,
            itemCount: incomplete.count,
            repeats: preferences.repeatCarUnloadReminder
        )
    }
}
