import XCTest
import CoreLocation
@testable import SmartGroceryReminder

enum Reliability {
    static let home = GeoPlace(id: "rel-home", name: "Home", latitude: 40.7, longitude: -74.0, kind: .home)
    static let store = GeoPlace(id: "rel-store", name: "Market", latitude: 40.71, longitude: -74.01, kind: .groceryStore)
    static let userId = "reliability-user"

    /// Home and one store saved; the daily reminder off so it doesn't add requests to check.
    static var preferences: UserPreferences {
        var prefs = UserPreferences.default
        prefs.homeLocation = home
        prefs.savedStores = [store]
        prefs.dailyListReminderEnabled = false
        return prefs
    }

    /// Something this user just checked off: a home arrival is a trip worth an unload reminder.
    static var justBought: [GroceryItem] {
        [GroceryItem(title: "Milk", isCompleted: true, completedBy: userId)]
    }
}

extension XCTestCase {
    /// A signed-in session whose preferences and list have loaded, on a fake location manager.
    @MainActor
    func reliabilitySession(
        manager: FakeLocationManager = FakeLocationManager(),
        items: [GroceryItem] = Reliability.justBought,
        stateDirectory: URL? = nil
    ) async throws -> AppState {
        let state = AppState.forTesting(stateDirectory: stateDirectory, locationManager: manager)
        let user = AppUser(id: Reliability.userId, email: "r@b.c", displayName: "R")
        try await state.listService.savePreferences(Reliability.preferences, userId: user.id)
        for item in items {
            try await state.listService.upsert(item: item, listId: user.id)
        }
        state.currentUser = user
        state.isAuthenticated = true
        state.startSync(for: user)
        try await waitUntil { state.sessionDataLoaded && state.shoppingList.count == items.count }
        return state
    }

    /// The Reminder health checklist as the Diagnostics screen would build it.
    @MainActor
    func health(of service: LocationService, expectedRegionCount: Int = 2) -> [String: HealthItem] {
        let items = ReminderHealth.check(
            authorization: service.authorizationStatus,
            accuracy: service.accuracyAuthorization,
            notifications: .authorized,
            backgroundRefresh: .available,
            lowPowerMode: false,
            hasHome: true,
            systemRegionCount: service.systemRegionCount,
            expectedRegionCount: expectedRegionCount
        )
        return Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    /// A temporary directory removed after the test, for state that must survive a "relaunch".
    func temporaryDirectory() -> URL {
        temporaryFileURL("unused").deletingLastPathComponent()
    }
}
