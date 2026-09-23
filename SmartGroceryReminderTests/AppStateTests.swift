import XCTest
@testable import SmartGroceryReminder

// AppState.signIn/signUp are deliberately not exercised here: they request location and
// notification permission, and the system alerts would hang a simulator test run.
final class AppStateTests: XCTestCase {
    @MainActor
    func testStoreReminderRespectsToggleAndItemCount() async {
        var prefs = UserPreferences.default
        XCTAssertTrue(AppState.shouldSendStoreReminder(preferences: prefs, openItemCount: 3))
        XCTAssertFalse(AppState.shouldSendStoreReminder(preferences: prefs, openItemCount: 0))

        prefs.storeEntryReminderEnabled = false
        XCTAssertFalse(AppState.shouldSendStoreReminder(preferences: prefs, openItemCount: 3))
    }

    @MainActor
    func testCarUnloadPlanIsNilWhenEverythingIsCompleted() async {
        let items = [GroceryItem(title: "Milk", isCompleted: true)]
        XCTAssertNil(AppState.carUnloadReminderPlan(preferences: .default, items: items))
    }

    @MainActor
    func testCarUnloadPlanUsesPreferences() async throws {
        var prefs = UserPreferences.default
        prefs.repeatCarUnloadReminder = false
        prefs.carUnloadRepeatInterval = 120
        let items = [GroceryItem(title: "Milk"), GroceryItem(title: "Eggs"), GroceryItem(title: "Done", isCompleted: true)]

        let plan = try XCTUnwrap(AppState.carUnloadReminderPlan(preferences: prefs, items: items))
        XCTAssertEqual(plan.itemCount, 2)
        XCTAssertFalse(plan.repeats)
        XCTAssertEqual(plan.repeatInterval, 120)
    }

    @MainActor
    func testMarkDoneActionStopsTimer() async {
        let state = AppState()
        state.homeArrivalTimer.start(duration: 60)

        await state.handleNotificationAction(NotificationAction.markDone, category: NotificationCategory.carUnload)

        XCTAssertFalse(state.homeArrivalTimer.isActive)
    }

    @MainActor
    func testActionFromOtherCategoryIsIgnored() async {
        let state = AppState()
        state.homeArrivalTimer.start(duration: 60)
        defer { state.homeArrivalTimer.cancel() }

        await state.handleNotificationAction(NotificationAction.markDone, category: NotificationCategory.storeVisit)

        XCTAssertTrue(state.homeArrivalTimer.isActive)
    }

    @MainActor
    func testSnoozeActionCompletes() async {
        let state = AppState()
        await state.handleNotificationAction(NotificationAction.snooze, category: NotificationCategory.carUnload)
    }

    @MainActor
    func testSignOutClearsSession() async {
        let state = AppState()
        state.isAuthenticated = true
        state.currentUser = AppUser(id: "u1", email: "a@b.c", displayName: "A")
        state.homeArrivalTimer.start(duration: 60)

        state.signOut()

        XCTAssertFalse(state.isAuthenticated)
        XCTAssertNil(state.currentUser)
        XCTAssertFalse(state.homeArrivalTimer.isActive)
    }

    @MainActor
    func testSignOutClearsTheAccountsData() async {
        let state = AppState()
        state.isAuthenticated = true
        state.currentUser = AppUser(id: "a", email: "a@b.c", displayName: "A")
        state.shoppingList = [GroceryItem(title: "A's item")]
        state.preferences.homeLocation = GeoPlace(name: "A's home", latitude: 1, longitude: 2, kind: .home)

        state.signOut()

        XCTAssertTrue(state.shoppingList.isEmpty)
        XCTAssertEqual(state.preferences, .default)
    }

    @MainActor
    func testPreferencesAreNotSavedBeforeTheyLoad() async throws {
        let state = AppState()
        state.currentUser = AppUser(id: "unloaded", email: "u@b.c", displayName: "U")
        state.preferences.homeArrivalDelay = 42

        await state.savePreferences()

        let stored = try await state.listService.observePreferences(userId: "unloaded").first { _ in true }
        XCTAssertEqual(stored, .default)
    }

    @MainActor
    func testPreferencesSaveOnceLoaded() async throws {
        let state = AppState()
        let user = AppUser(id: "loaded", email: "l@b.c", displayName: "L")
        state.currentUser = user
        state.startSync(for: user)
        try await waitUntil { state.preferencesLoaded }

        state.preferences.homeArrivalDelay = 42
        await state.savePreferences()

        let stored = try await state.listService.observePreferences(userId: user.id).first { _ in true }
        XCTAssertEqual(stored?.homeArrivalDelay, 42)
        state.signOut()
    }

    @MainActor
    func testSyncDeliversListChangesUntilSignOut() async throws {
        let state = AppState()
        let user = AppUser(id: "sync-user", email: "s@b.c", displayName: "S")
        state.currentUser = user
        state.isAuthenticated = true
        state.startSync(for: user)
        try await waitUntil { state.preferencesLoaded && state.shoppingList.isEmpty }

        let apples = GroceryItem(title: "Apples")
        try await state.listService.upsert(item: apples, userId: user.id)
        try await waitUntil { state.shoppingList == [apples] }

        state.signOut()
        try await state.listService.upsert(item: GroceryItem(title: "Pears"), userId: user.id)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(state.shoppingList.isEmpty)
        XCTAssertFalse(state.preferencesLoaded)
    }

    /// Sync results arrive asynchronously; poll on the main actor until `condition` holds.
    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for condition")
    }

    @MainActor
    func testRestoreSessionWithMockBackendStaysSignedOut() async {
        let state = AppState()
        state.restoreSession()

        XCTAssertFalse(state.isAuthenticated)
        XCTAssertNil(state.currentUser)
    }

    func testDefaultPreferencesCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(UserPreferences.default)
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: data)
        XCTAssertEqual(decoded, .default)
    }
}
