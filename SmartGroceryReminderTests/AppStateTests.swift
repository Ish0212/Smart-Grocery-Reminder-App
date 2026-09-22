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

    func testDefaultPreferencesCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(UserPreferences.default)
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: data)
        XCTAssertEqual(decoded, .default)
    }
}
