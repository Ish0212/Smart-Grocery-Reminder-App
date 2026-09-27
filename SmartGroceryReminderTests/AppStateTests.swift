import XCTest
import CoreLocation
import UserNotifications
@testable import SmartGroceryReminder

// Tests use AppState.forTesting: its location and notification services are inert, so signing in
// never requests permission (the system alerts would hang a simulator test run).
final class AppStateTests: XCTestCase {
    @MainActor
    func testTheTestHostRunsOnTheDemoBackendWithInertServices() throws {
        let host = try XCTUnwrap(AppState.shared)
        XCTAssertTrue(host.useMockBackend)
        XCTAssertTrue(host.locationService.isInert)
        XCTAssertTrue(host.notificationService.isInert)
        XCTAssertFalse(host.isAuthenticated)
    }

    @MainActor
    func testASessionArmsGeofencesWithoutTouchingTheSystem() async throws {
        let state = AppState.forTesting()
        try await state.signUp(email: "inert@example.com", password: "secret1", displayName: "Inert")
        try await waitUntil { state.preferencesLoaded }

        let home = GeoPlace(id: "inert-home", name: "Home", latitude: 40.7, longitude: -74.0, kind: .home)
        await state.setHome(home)

        let expected = ([home] + state.preferences.savedStores).map(RegionID.make(for:))
        XCTAssertEqual(Set(state.locationService.monitoredForTesting.keys), Set(expected))
        XCTAssertEqual(state.locationService.authorizationStatus, .notDetermined)
        XCTAssertEqual(state.notificationService.authorizationStatus, .notDetermined)

        state.signOut()
        XCTAssertTrue(state.locationService.monitoredForTesting.isEmpty)
    }

    @MainActor
    func testStoreReminderRespectsToggleAndItemCount() async {
        var prefs = UserPreferences.default
        XCTAssertTrue(AppState.shouldSendStoreReminder(preferences: prefs, openItemCount: 3))
        XCTAssertFalse(AppState.shouldSendStoreReminder(preferences: prefs, openItemCount: 0))

        prefs.storeEntryReminderEnabled = false
        XCTAssertFalse(AppState.shouldSendStoreReminder(preferences: prefs, openItemCount: 3))
    }

    @MainActor
    func testCarUnloadPlanIsNilWhenEverythingWasCompletedLongAgo() async {
        let now = Date()
        let items = [GroceryItem(title: "Milk", isCompleted: true, updatedAt: now.addingTimeInterval(-24 * 60 * 60))]
        XCTAssertNil(AppState.carUnloadReminderPlan(preferences: .default, items: items, now: now))
    }

    @MainActor
    func testCarUnloadPlanCountsItemsJustBought() async throws {
        let now = Date()
        let items = [
            GroceryItem(title: "Milk", isCompleted: true, updatedAt: now.addingTimeInterval(-20 * 60)),
            GroceryItem(title: "Eggs", isCompleted: true, updatedAt: now.addingTimeInterval(-2 * 60 * 60)),
            GroceryItem(title: "Old", isCompleted: true, updatedAt: now.addingTimeInterval(-4 * 60 * 60)),
            GroceryItem(title: "Still needed"),
        ]
        let plan = try XCTUnwrap(AppState.carUnloadReminderPlan(preferences: .default, items: items, now: now))
        XCTAssertEqual(plan.itemCount, 2, "Only the items checked off in the last 3 hours are in the car")
    }

    @MainActor
    func testCarUnloadPlanFallsBackToUncheckedItems() async throws {
        let now = Date()
        let items = [
            GroceryItem(title: "Old", isCompleted: true, updatedAt: now.addingTimeInterval(-4 * 60 * 60)),
            GroceryItem(title: "Milk"),
            GroceryItem(title: "Bread"),
        ]
        let plan = try XCTUnwrap(AppState.carUnloadReminderPlan(preferences: .default, items: items, now: now))
        XCTAssertEqual(plan.itemCount, 2)
    }

    @MainActor
    func testCarUnloadPlanIgnoresCheckOffsFromTheFuture() async {
        // Another device's clock can be ahead; that isn't "just bought".
        let now = Date()
        let items = [GroceryItem(title: "Milk", isCompleted: true, updatedAt: now.addingTimeInterval(60 * 60))]
        XCTAssertNil(AppState.carUnloadReminderPlan(preferences: .default, items: items, now: now))
    }

    @MainActor
    func testMarkDoneIsSavedForTheNextLaunch() async throws {
        let directory = temporaryFileURL("state").deletingLastPathComponent()
        let now = Date(timeIntervalSince1970: 2_000_000)
        let state = AppState.forTesting(stateDirectory: directory)

        state.markUnloadComplete(source: "test", now: now)

        XCTAssertEqual(state.lastUnloadDone, now)
        XCTAssertEqual(AppState.forTesting(stateDirectory: directory).lastUnloadDone, now)
    }

    @MainActor
    func testSignOutClearsCooldowns() async throws {
        let directory = temporaryFileURL("state").deletingLastPathComponent()
        let state = AppState.forTesting(stateDirectory: directory)
        state.markUnloadComplete(source: "test")

        state.signOut()

        XCTAssertNil(state.lastUnloadDone)
        XCTAssertNil(AppState.forTesting(stateDirectory: directory).lastUnloadDone)
    }

    @MainActor
    func testItemsCheckedOffBeforeTheLastUnloadAreAlreadyInside() async throws {
        let now = Date()
        let done = now.addingTimeInterval(-60 * 60)
        let items = [
            GroceryItem(title: "Brought in", isCompleted: true, updatedAt: done.addingTimeInterval(-10 * 60)),
            GroceryItem(title: "Bought since", isCompleted: true, updatedAt: done.addingTimeInterval(10 * 60)),
        ]
        let plan = try XCTUnwrap(AppState.carUnloadReminderPlan(preferences: .default, items: items, now: now, context: .init(lastUnloadDone: done)))
        XCTAssertEqual(plan.itemCount, 1)
    }

    @MainActor
    func testCarUnloadPlanUsesPreferences() async throws {
        var prefs = UserPreferences.default
        prefs.repeatCarUnloadReminder = false
        prefs.carUnloadRepeatInterval = 120
        let items = [GroceryItem(title: "Milk"), GroceryItem(title: "Eggs"), GroceryItem(title: "Done", isCompleted: true, updatedAt: Date().addingTimeInterval(-24 * 60 * 60))]

        let plan = try XCTUnwrap(AppState.carUnloadReminderPlan(preferences: prefs, items: items))
        XCTAssertEqual(plan.itemCount, 2)
        XCTAssertFalse(plan.repeats)
        XCTAssertEqual(plan.repeatInterval, 120)
    }

    @MainActor
    func testMarkDoneActionStopsTimer() async {
        let state = AppState.forTesting()
        state.homeArrivalTimer.start(duration: 60)

        await state.handleNotificationAction(NotificationAction.markDone, category: NotificationCategory.carUnload)

        XCTAssertFalse(state.homeArrivalTimer.isActive)
    }

    @MainActor
    func testActionFromOtherCategoryIsIgnored() async {
        let state = AppState.forTesting()
        state.homeArrivalTimer.start(duration: 60)
        defer { state.homeArrivalTimer.cancel() }

        await state.handleNotificationAction(NotificationAction.markDone, category: NotificationCategory.storeVisit)

        XCTAssertTrue(state.homeArrivalTimer.isActive)
    }

    @MainActor
    func testSnoozeActionCompletes() async {
        let state = AppState.forTesting()
        await state.handleNotificationAction(NotificationAction.snooze, category: NotificationCategory.carUnload)
    }

    @MainActor
    func testSignOutClearsSession() async {
        let state = AppState.forTesting()
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
        let state = AppState.forTesting()
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
        let state = AppState.forTesting()
        state.currentUser = AppUser(id: "unloaded", email: "u@b.c", displayName: "U")
        state.preferences.homeArrivalDelay = 42

        await state.savePreferences()

        let stored = try await state.listService.observePreferences(userId: "unloaded").first { _ in true }
        XCTAssertEqual(stored, .default)
    }

    @MainActor
    func testPreferencesSaveOnceLoaded() async throws {
        let state = AppState.forTesting()
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
        let state = AppState.forTesting()
        let user = AppUser(id: "sync-user", email: "s@b.c", displayName: "S")
        state.currentUser = user
        state.isAuthenticated = true
        state.startSync(for: user)
        try await waitUntil { state.preferencesLoaded && state.shoppingList.isEmpty }

        let apples = GroceryItem(title: "Apples")
        try await state.listService.upsert(item: apples, listId: user.id)
        try await waitUntil { state.shoppingList == [apples] }

        state.signOut()
        try await state.listService.upsert(item: GroceryItem(title: "Pears"), listId: user.id)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(state.shoppingList.isEmpty)
        XCTAssertFalse(state.preferencesLoaded)
    }

    @MainActor
    func testQuickAddRequiresSignIn() async {
        let state = AppState.forTesting()
        do {
            _ = try await state.quickAdd("Milk")
            XCTFail("Expected notSignedIn")
        } catch {
            XCTAssertEqual(error as? QuickAddError, .notSignedIn)
        }
    }

    @MainActor
    func testQuickAddRejectsBlankItem() async {
        let state = AppState.forTesting()
        state.isAuthenticated = true
        do {
            _ = try await state.quickAdd("   \n")
            XCTFail("Expected emptyItem")
        } catch {
            XCTAssertEqual(error as? QuickAddError, .emptyItem)
        }
    }

    @MainActor
    func testQuickAddTrimsAndInsertsAtTop() async throws {
        let state = AppState.forTesting()
        state.isAuthenticated = true
        state.currentUser = AppUser(id: "quick", email: "q@b.c", displayName: "Q")

        let title = try await state.quickAdd("  Oat milk \n")

        XCTAssertEqual(title, "Oat milk")
        XCTAssertEqual(state.shoppingList.first?.title, "Oat milk")
    }

    @MainActor
    func testRestoreSessionWithMockBackendStaysSignedOut() async {
        let state = AppState.forTesting()
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
