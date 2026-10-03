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
    func testTestToolsAreForTheDemoAndDebugBuildsButNeverTheScreenshots() {
        XCTAssertTrue(AppState.showsTestTools(useMockBackend: true, isDebugBuild: false, takingScreenshots: false))
        XCTAssertTrue(AppState.showsTestTools(useMockBackend: false, isDebugBuild: true, takingScreenshots: false))
        // The App Store build.
        XCTAssertFalse(AppState.showsTestTools(useMockBackend: false, isDebugBuild: false, takingScreenshots: false))
        XCTAssertFalse(AppState.showsTestTools(useMockBackend: true, isDebugBuild: true, takingScreenshots: true))
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
    func testDeletingTheAccountChecksThePasswordThenRemovesTheData() async throws {
        let state = AppState.forTesting()
        try await state.signUp(email: "gone@example.com", password: "secret1", displayName: "Gone")
        let userId = try XCTUnwrap(state.currentUser?.id)
        try await waitUntil { state.sessionDataLoaded }
        await state.addItem("Milk")

        do {
            try await state.deleteAccount(password: "wrong12")
            XCTFail("Expected invalidCredentials")
        } catch {
            XCTAssertEqual(error as? AuthError, .invalidCredentials)
        }
        XCTAssertTrue(state.isAuthenticated)
        XCTAssertEqual(state.shoppingList.map(\.title), ["Milk"])

        try await state.deleteAccount(password: "secret1")

        XCTAssertFalse(state.isAuthenticated)
        XCTAssertTrue(state.locationService.monitoredForTesting.isEmpty)
        XCTAssertTrue(state.diagnostics.entries.isEmpty)
        let items = try await state.listService.observeItems(listId: userId).first { _ in true }
        XCTAssertEqual(items?.count, 0)
        do {
            try await state.signIn(email: "gone@example.com", password: "secret1")
            XCTFail("Expected invalidCredentials")
        } catch {
            XCTAssertEqual(error as? AuthError, .invalidCredentials)
        }
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
    func testCarUnloadPlanFallsBackToUncheckedItemsOnlyWhenSimulated() async throws {
        let now = Date()
        let items = [
            GroceryItem(title: "Old", isCompleted: true, updatedAt: now.addingTimeInterval(-4 * 60 * 60)),
            GroceryItem(title: "Milk"),
            GroceryItem(title: "Bread"),
        ]
        XCTAssertNil(AppState.carUnloadReminderPlan(preferences: .default, items: items, now: now))
        let plan = try XCTUnwrap(AppState.carUnloadReminderPlan(preferences: .default, items: items, now: now, isSimulated: true))
        XCTAssertEqual(plan.itemCount, 2)
    }

    @MainActor
    func testCarUnloadPlanCountsUncheckedItemsAfterAStoreVisit() async throws {
        let now = Date()
        let items = [GroceryItem(title: "Milk"), GroceryItem(title: "Bread")]
        let context = AppState.ReminderContext(lastStoreVisit: now.addingTimeInterval(-45 * 60))
        let plan = try XCTUnwrap(AppState.carUnloadReminderPlan(preferences: .default, items: items, now: now, context: context))
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
        let afterShopping = AppState.ReminderContext(lastStoreVisit: Date().addingTimeInterval(-10 * 60))

        let plan = try XCTUnwrap(AppState.carUnloadReminderPlan(preferences: prefs, items: items, context: afterShopping))
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
    func testSignOutRemovesEveryReminder() async throws {
        let state = AppState.forTesting()
        try await state.signUp(email: "reminders@example.com", password: "secret1", displayName: "R")
        let service = state.notificationService
        await service.scheduleHomeArrivalReminder(after: 600, itemCount: 1, repeats: true, repeatInterval: 300)
        await service.sendGroceryStoreReminder(itemCount: 1)
        XCTAssertGreaterThanOrEqual(service.pendingCount, 3)

        state.signOut()

        XCTAssertEqual(
            Set(NotificationID.all),
            [NotificationID.carUnload, NotificationID.carUnloadRepeat, NotificationID.storeVisit, NotificationID.dailyList]
        )
        XCTAssertEqual(Array(service.removedForTesting.suffix(4)), NotificationID.all)
        XCTAssertEqual(Array(service.removedDeliveredForTesting.suffix(4)), NotificationID.all)
        try await waitUntil { service.pendingCount == 0 }
    }

    /// A reminder delivered while the app was in the background is no longer pending.
    @MainActor
    func testThePendingCountIsRefreshedWhenTheAppBecomesActive() async throws {
        let state = AppState.forTesting()
        let service = state.notificationService
        await service.sendGroceryStoreReminder(itemCount: 1)
        XCTAssertEqual(service.pendingCount, 1)

        service.deliverForTesting(NotificationID.storeVisit)
        XCTAssertEqual(service.pendingCount, 1, "Stale until something refreshes it")

        state.appDidBecomeActive()
        try await waitUntil { service.pendingCount == 0 }
    }

    /// A reminder left in Notification Center after sign-out must not snooze or write a cooldown.
    @MainActor
    func testReminderActionsAfterSignOutAreIgnored() async throws {
        let state = AppState.forTesting()
        try await state.signUp(email: "leftover@example.com", password: "secret1", displayName: "L")
        state.signOut()

        await state.handleNotificationAction(NotificationAction.markDone, category: NotificationCategory.carUnload)
        await state.handleNotificationAction(NotificationAction.snooze, category: NotificationCategory.carUnload, itemCount: 2)
        await state.handleNotificationAction(UNNotificationDefaultActionIdentifier, category: NotificationCategory.carUnload)

        XCTAssertNil(state.lastUnloadDone)
        XCTAssertNil(state.requestedTab)
        XCTAssertFalse(state.notificationService.scheduledForTesting.contains { $0.identifier == NotificationID.carUnload })
        let entries = state.diagnostics.entries
        XCTAssertEqual(entries.filter { $0.kind == .skipped && $0.message == "Ignored a reminder action: signed out" }.count, 3)
        XCTAssertFalse(entries.contains { $0.kind == .unloadDone || $0.kind == .snoozed })
    }

    /// "All brought in" can cold-launch the app before the saved session has been restored.
    @MainActor
    func testAllBroughtInBeforeTheSessionRestoresIsHandled() async {
        let state = AppState.forTesting()
        XCTAssertNil(state.currentUser)

        await state.handleNotificationAction(NotificationAction.markDone, category: NotificationCategory.carUnload)

        XCTAssertNotNil(state.lastUnloadDone)
        XCTAssertEqual(state.diagnostics.entries.last?.kind, .unloadDone)
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
