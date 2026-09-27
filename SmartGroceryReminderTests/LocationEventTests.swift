import XCTest
import UserNotifications
@testable import SmartGroceryReminder

@MainActor
private final class FakeBackgroundActivity: BackgroundActivityProviding {
    private(set) var began = 0
    private(set) var ended = 0
    var onExpiration: (@MainActor () -> Void)?

    func begin(name: String, onExpiration: @escaping @MainActor () -> Void) -> Int {
        began += 1
        self.onExpiration = onExpiration
        return began
    }

    func end(_ token: Int) {
        ended += 1
    }
}

final class LocationEventTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let items = [GroceryItem(title: "Milk"), GroceryItem(title: "Eggs", isCompleted: true)]

    private func event(
        _ kind: GeoPlace.PlaceKind = .home,
        secondsAgo: TimeInterval = 0,
        transition: LocationEvent.Transition = .enter
    ) -> LocationEvent {
        LocationEvent(kind: kind, transition: transition, placeId: "p", date: now.addingTimeInterval(-secondsAgo))
    }

    /// A real visit to a saved store half an hour ago: evidence of a shopping trip.
    private var storeVisit: Date { now.addingTimeInterval(-30 * 60) }
    private var afterShopping: AppState.ReminderContext { .init(lastStoreVisit: storeVisit) }

    private let home = GeoPlace(id: "test-home", name: "Home", latitude: 40.7, longitude: -74.0, kind: .home)
    private let store = GeoPlace(id: "test-store", name: "Market", latitude: 40.71, longitude: -74.01, kind: .groceryStore)

    /// Saved places with known ids, so real events for them are handled.
    private var sessionPreferences: UserPreferences {
        var prefs = UserPreferences.default
        prefs.homeLocation = home
        prefs.savedStores = [store]
        return prefs
    }

    /// A signed-in session whose preferences and list have loaded.
    @MainActor
    private func loadedSession(
        preferences: UserPreferences? = nil,
        items: [GroceryItem] = [],
        stateDirectory: URL? = nil
    ) async throws -> AppState {
        let state = AppState.forTesting(stateDirectory: stateDirectory)
        let user = AppUser(id: "session-user", email: "s@b.c", displayName: "S")
        try await state.listService.savePreferences(preferences ?? sessionPreferences, userId: user.id)
        for item in items {
            try await state.listService.upsert(item: item, listId: user.id)
        }
        state.currentUser = user
        state.isAuthenticated = true
        state.startSync(for: user)
        try await waitUntil { state.sessionDataLoaded && state.shoppingList.count == items.count }
        return state
    }

    private func enter(_ place: GeoPlace) -> LocationEvent {
        LocationEvent(kind: place.kind, transition: .enter, placeId: place.id, date: Date())
    }

    // MARK: - Decisions

    @MainActor
    func testArrivalAfterCheckingEverythingOffStillSchedulesUnload() {
        let bought = [
            GroceryItem(title: "Milk", isCompleted: true, updatedAt: now.addingTimeInterval(-30 * 60)),
            GroceryItem(title: "Eggs", isCompleted: true, updatedAt: now.addingTimeInterval(-25 * 60)),
        ]
        guard case .scheduleUnload(_, let itemCount, _, _) = AppState.decision(
            for: event(), preferences: .default, items: bought, now: now
        ) else { return XCTFail("Expected scheduleUnload") }
        XCTAssertEqual(itemCount, 2)
    }

    // MARK: - Shopping trip

    /// Unload, then walk the dog: the unchecked items are still on the list, but nothing was bought.
    @MainActor
    func testWalkingTheDogWithUncheckedItemsDoesNotRemind() {
        let decision = AppState.decision(
            for: event(), preferences: .default, items: items, now: now,
            context: .init(
                lastHandled: now.addingTimeInterval(-60 * 60),
                lastUnloadDone: now.addingTimeInterval(-45 * 60),
                lastStoreVisit: now.addingTimeInterval(-90 * 60)
            )
        )
        XCTAssertEqual(decision, .ignore(reason: AppState.noShoppingTripReason))
    }

    @MainActor
    func testCommuteWithOpenItemsAndNoStoreVisitDoesNotRemind() {
        let open = [GroceryItem(title: "Milk"), GroceryItem(title: "Bread")]
        let decision = AppState.decision(for: event(), preferences: .default, items: open, now: now)
        XCTAssertEqual(decision, .ignore(reason: AppState.noShoppingTripReason))
        XCTAssertTrue(AppState.noShoppingTripReason.contains("check off what you bought, or visit a saved store"))
    }

    @MainActor
    func testStoreVisitWithUncheckedItemsReminds() {
        let open = [
            GroceryItem(title: "Milk"),
            GroceryItem(title: "Bread"),
            GroceryItem(title: "Old", isCompleted: true, updatedAt: now.addingTimeInterval(-24 * 60 * 60)),
        ]
        guard case .scheduleUnload(_, let itemCount, _, _) = AppState.decision(
            for: event(), preferences: .default, items: open, now: now, context: afterShopping
        ) else { return XCTFail("Expected scheduleUnload") }
        XCTAssertEqual(itemCount, 2)
    }

    @MainActor
    func testStoreVisitWithNothingOnTheListRemindsAboutYourGroceries() {
        guard case .scheduleUnload(_, let itemCount, _, _) = AppState.decision(
            for: event(), preferences: .default, items: [], now: now, context: afterShopping
        ) else { return XCTFail("Expected scheduleUnload") }
        XCTAssertEqual(itemCount, 0)

        let content = NotificationService.carUnloadContent(itemCount: 0, isRepeat: false)
        XCTAssertEqual(content.body, "Don't forget to bring your groceries inside.")
        XCTAssertEqual(content.userInfo[NotificationUserInfo.itemCount] as? Int, 0)
    }

    @MainActor
    func testAStoreVisitCountsForThreeHours() {
        let open = [GroceryItem(title: "Milk")]
        guard case .scheduleUnload = AppState.decision(
            for: event(), preferences: .default, items: open, now: now,
            context: .init(lastStoreVisit: now.addingTimeInterval(-AppState.recentPurchaseWindow))
        ) else { return XCTFail("Expected scheduleUnload") }

        XCTAssertEqual(
            AppState.decision(
                for: event(), preferences: .default, items: open, now: now,
                context: .init(lastStoreVisit: now.addingTimeInterval(-AppState.recentPurchaseWindow - 1))
            ),
            .ignore(reason: AppState.noShoppingTripReason)
        )
    }

    @MainActor
    func testAStoreVisitBeforeTheLastUnloadDoesNotCount() {
        let decision = AppState.decision(
            for: event(), preferences: .default, items: items, now: now,
            context: .init(lastUnloadDone: now.addingTimeInterval(-20 * 60), lastStoreVisit: now.addingTimeInterval(-40 * 60))
        )
        XCTAssertEqual(decision, .ignore(reason: AppState.noShoppingTripReason))
    }

    /// Demos and the field test's "Simulate arrive home" still remind about the unchecked items.
    @MainActor
    func testSimulatedArrivalFallsBackToUncheckedItems() {
        var simulated = event()
        simulated.isSimulated = true
        guard case .scheduleUnload(_, let itemCount, _, _) = AppState.decision(
            for: simulated, preferences: .default, items: items, now: now
        ) else { return XCTFail("Expected scheduleUnload") }
        XCTAssertEqual(itemCount, 1)

        guard case .ignore(let reason) = AppState.decision(
            for: simulated, preferences: .default, items: [], now: now
        ) else { return XCTFail("Expected ignore") }
        XCTAssertEqual(reason, "nothing bought recently and no unchecked items")
    }

    // MARK: - Flapping cooldown

    @MainActor
    func testHomeEnterInsideTheCooldownIsIgnored() {
        let decision = AppState.decision(
            for: event(), preferences: .default, items: items, now: now,
            context: .init(lastHandled: now.addingTimeInterval(-5 * 60))
        )
        guard case .ignore(let reason) = decision else { return XCTFail("Expected ignore") }
        XCTAssertTrue(reason.contains("already handled"), reason)
    }

    @MainActor
    func testHomeEnterAfterTheCooldownSchedules() {
        let decision = AppState.decision(
            for: event(), preferences: .default, items: items, now: now,
            context: .init(lastHandled: now.addingTimeInterval(-AppState.cooldown(for: .home)), lastStoreVisit: storeVisit)
        )
        guard case .scheduleUnload = decision else { return XCTFail("Expected scheduleUnload") }
    }

    @MainActor
    func testStoreCooldownIsLongerThanHome() {
        let twentyMinutesAgo = now.addingTimeInterval(-20 * 60)
        guard case .ignore = AppState.decision(
            for: event(.groceryStore), preferences: .default, items: items, now: now, context: .init(lastHandled: twentyMinutesAgo)
        ) else { return XCTFail("Expected the store enter to be ignored") }
        guard case .scheduleUnload = AppState.decision(
            for: event(.home), preferences: .default, items: items, now: now,
            context: .init(lastHandled: twentyMinutesAgo, lastStoreVisit: storeVisit)
        ) else { return XCTFail("Expected the home enter to schedule") }
    }

    /// Unload, then walk the dog: re-entering home later must not ask about groceries already inside.
    @MainActor
    func testReEnteringHomeAfterUnloadingDoesNotRemindAgain() {
        let arrival = now.addingTimeInterval(-50 * 60)
        let done = now.addingTimeInterval(-38 * 60)
        let boughtBeforeDone = [GroceryItem(title: "Milk", isCompleted: true, updatedAt: arrival.addingTimeInterval(-30 * 60))]

        guard case .ignore = AppState.decision(
            for: event(), preferences: .default, items: boughtBeforeDone, now: now,
            context: .init(lastHandled: arrival, lastUnloadDone: done)
        ) else { return XCTFail("Expected ignore") }

        let boughtAfterDone = boughtBeforeDone + [GroceryItem(title: "Bread", isCompleted: true, updatedAt: done.addingTimeInterval(20 * 60))]
        guard case .scheduleUnload(_, let itemCount, _, _) = AppState.decision(
            for: event(), preferences: .default, items: boughtAfterDone, now: now,
            context: .init(lastHandled: arrival, lastUnloadDone: done)
        ) else { return XCTFail("Expected scheduleUnload") }
        XCTAssertEqual(itemCount, 1)
    }

    @MainActor
    func testUnloadDoneStartsTheHomeCooldown() {
        guard case .ignore = AppState.decision(
            for: event(), preferences: .default, items: items, now: now,
            context: .init(lastHandled: now.addingTimeInterval(-60 * 60), lastUnloadDone: now.addingTimeInterval(-5 * 60))
        ) else { return XCTFail("Expected ignore") }
    }

    @MainActor
    func testUnloadDoneDoesNotAffectStores() {
        guard case .notifyStore = AppState.decision(
            for: event(.groceryStore), preferences: .default, items: items, now: now,
            context: .init(lastUnloadDone: now.addingTimeInterval(-60))
        ) else { return XCTFail("Expected notifyStore") }
    }

    @MainActor
    func testSimulatedEventsSkipTheCooldown() {
        var simulated = event()
        simulated.isSimulated = true
        guard case .scheduleUnload = AppState.decision(
            for: simulated, preferences: .default, items: items, now: now, context: .init(lastHandled: now.addingTimeInterval(-60))
        ) else { return XCTFail("Expected scheduleUnload") }
    }

    @MainActor
    func testArrivalOlderThanTheLastHandledTimeIsIgnored() {
        // e.g. a queued arrival from before "All brought in" was tapped.
        guard case .ignore = AppState.decision(
            for: event(secondsAgo: 120), preferences: .default, items: items, now: now, context: .init(lastHandled: now)
        ) else { return XCTFail("Expected ignore") }
    }

    @MainActor
    func testHomeArrivalSchedulesUnloadAfterTheConfiguredDelay() {
        var prefs = UserPreferences.default
        prefs.homeArrivalDelay = 600

        let decision = AppState.decision(for: event(), preferences: prefs, items: items, now: now, context: afterShopping)

        XCTAssertEqual(decision, .scheduleUnload(
            delay: 600,
            itemCount: 1,
            repeats: prefs.repeatCarUnloadReminder,
            repeatInterval: prefs.carUnloadRepeatInterval
        ))
    }

    @MainActor
    func testLateArrivalKeepsTheReminderDueFromTheArrivalTime() {
        var prefs = UserPreferences.default
        prefs.homeArrivalDelay = 600

        let late = AppState.decision(for: event(secondsAgo: 240), preferences: prefs, items: items, now: now, context: afterShopping)
        guard case .scheduleUnload(let delay, _, _, _) = late else { return XCTFail("Expected scheduleUnload") }
        XCTAssertEqual(delay, 360)

        let veryLate = AppState.decision(for: event(secondsAgo: 599), preferences: prefs, items: items, now: now, context: afterShopping)
        guard case .scheduleUnload(let floored, _, _, _) = veryLate else { return XCTFail("Expected scheduleUnload") }
        XCTAssertEqual(floored, 5)
    }

    @MainActor
    func testStaleEventIsIgnored() {
        let decision = AppState.decision(for: event(secondsAgo: 3_601), preferences: .default, items: items, now: now)
        guard case .ignore = decision else { return XCTFail("Expected ignore") }
    }

    @MainActor
    func testArrivalWithEverythingCheckedOffLongAgoIsIgnored() {
        let done = [GroceryItem(title: "Milk", isCompleted: true, updatedAt: now.addingTimeInterval(-24 * 60 * 60))]
        guard case .ignore = AppState.decision(for: event(), preferences: .default, items: done, now: now) else {
            return XCTFail("Expected ignore")
        }
    }

    @MainActor
    func testStoreEntryRespectsTheToggle() {
        XCTAssertEqual(
            AppState.decision(for: event(.groceryStore), preferences: .default, items: items, now: now),
            .notifyStore(itemCount: 1)
        )

        var off = UserPreferences.default
        off.storeEntryReminderEnabled = false
        guard case .ignore = AppState.decision(for: event(.groceryStore), preferences: off, items: items, now: now) else {
            return XCTFail("Expected ignore")
        }
    }

    @MainActor
    func testExitIsIgnored() {
        guard case .ignore = AppState.decision(for: event(transition: .exit), preferences: .default, items: items, now: now) else {
            return XCTFail("Expected ignore")
        }
    }

    @MainActor
    func testCoalescedKeepsTheLatestEnterPerKind() {
        let firstHome = event(.home, secondsAgo: 300)
        let store = event(.groceryStore, secondsAgo: 200)
        let secondHome = event(.home, secondsAgo: 100)
        let exit = event(.home, secondsAgo: 50, transition: .exit)

        XCTAssertEqual(AppState.coalesced([firstHome, store, secondHome, exit]), [store, secondHome])
    }

    // MARK: - Queue

    @MainActor
    func testArrivalBeforeTheListLoadsIsHandledOnceItDoes() async throws {
        let state = AppState.forTesting()
        let user = AppUser(id: "queued-user", email: "q@b.c", displayName: "Q")
        try await state.listService.savePreferences(sessionPreferences, userId: user.id)
        // Checked off on the way home: evidence of a shopping trip.
        try await state.listService.upsert(item: GroceryItem(title: "Milk", isCompleted: true, completedBy: user.id), listId: user.id)
        state.currentUser = user

        state.handleLocationEvent(enter(home))
        XCTAssertEqual(state.pendingLocationEvents.count, 1)
        XCTAssertFalse(state.homeArrivalTimer.isActive)

        state.startSync(for: user)
        try await waitUntil { state.homeArrivalTimer.isActive }
        XCTAssertTrue(state.pendingLocationEvents.isEmpty)
        try await waitUntil { state.diagnostics.entries.contains { $0.kind == .unloadScheduled } }
        state.signOut()
    }

    /// Store reminders are off, so the visit sends nothing, but it still counts as a shopping trip.
    @MainActor
    func testARealStoreVisitMakesTheNextHomeArrivalRemind() async throws {
        var prefs = sessionPreferences
        prefs.storeEntryReminderEnabled = false
        let state = try await loadedSession(preferences: prefs, items: [GroceryItem(title: "Milk")])

        state.handleLocationEvent(enter(home))
        try await waitUntil {
            state.diagnostics.entries.contains { $0.kind == .skipped && $0.message.contains(AppState.noShoppingTripReason) }
        }
        XCTAssertFalse(state.homeArrivalTimer.isActive)
        XCTAssertNil(state.lastStoreVisit)

        state.handleLocationEvent(enter(store))
        XCTAssertNotNil(state.lastStoreVisit)

        state.handleLocationEvent(enter(home))
        try await waitUntil { state.homeArrivalTimer.isActive }
        try await waitUntil { state.diagnostics.entries.contains { $0.kind == .unloadScheduled } }
        let reminder = try XCTUnwrap(state.notificationService.scheduledForTesting.first { $0.identifier == NotificationID.carUnload })
        XCTAssertEqual(reminder.content.userInfo[NotificationUserInfo.itemCount] as? Int, 1)
        XCTAssertFalse(state.notificationService.scheduledForTesting.contains { $0.identifier == NotificationID.storeVisit })
        state.signOut()
    }

    @MainActor
    func testSimulatedStoreVisitsAreNotRemembered() async throws {
        let state = try await loadedSession()
        state.locationService.simulateEnterStore()
        XCTAssertNil(state.lastStoreVisit)
        state.signOut()
    }

    @MainActor
    func testRunningOutOfBackgroundTimeDropsQueuedEvents() {
        let activity = FakeBackgroundActivity()
        let state = AppState.forTesting(backgroundActivity: activity)
        state.currentUser = AppUser(id: "u", email: "u@b.c", displayName: "U")

        state.handleLocationEvent(LocationEvent(kind: .home, transition: .enter, placeId: "p", date: Date()))
        XCTAssertEqual(activity.began, 1)

        activity.onExpiration?()

        XCTAssertTrue(state.pendingLocationEvents.isEmpty)
        XCTAssertEqual(activity.ended, 1)
        XCTAssertEqual(state.diagnostics.entries.last?.kind, .dropped)
    }

    @MainActor
    func testSignOutClearsTheQueue() {
        let activity = FakeBackgroundActivity()
        let state = AppState.forTesting(backgroundActivity: activity)
        state.currentUser = AppUser(id: "u", email: "u@b.c", displayName: "U")
        state.handleLocationEvent(LocationEvent(kind: .home, transition: .enter, placeId: "p", date: Date()))

        state.signOut()

        XCTAssertTrue(state.pendingLocationEvents.isEmpty)
        XCTAssertEqual(activity.ended, 1)
    }

    // MARK: - Notification actions and timer

    @MainActor
    func testSnoozeUsesTheCountFromTheNotification() async throws {
        let state = AppState.forTesting()
        state.shoppingList = [GroceryItem(title: "Milk"), GroceryItem(title: "Eggs"), GroceryItem(title: "Bread")]

        await state.handleNotificationAction(NotificationAction.snooze, category: NotificationCategory.carUnload, itemCount: 2)

        XCTAssertEqual(state.diagnostics.entries.last?.kind, .snoozed)
        let scheduled = state.notificationService.scheduledForTesting
        XCTAssertEqual(scheduled.map(\.identifier), [NotificationID.carUnload])
        let request = try XCTUnwrap(scheduled.first)
        XCTAssertEqual(request.content.userInfo[NotificationUserInfo.itemCount] as? Int, 2)
        let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(trigger.timeInterval, state.preferences.carUnloadRepeatInterval)
    }

    @MainActor
    func testSnoozeKeepsAYourGroceriesReminder() async throws {
        let state = AppState.forTesting()

        await state.handleNotificationAction(NotificationAction.snooze, category: NotificationCategory.carUnload, itemCount: 0)

        XCTAssertEqual(state.diagnostics.entries.last?.kind, .snoozed)
        let request = try XCTUnwrap(state.notificationService.scheduledForTesting.first)
        XCTAssertEqual(request.content.userInfo[NotificationUserInfo.itemCount] as? Int, 0)
        XCTAssertEqual(request.content.body, "Don't forget to bring your groceries inside.")
    }

    @MainActor
    func testSnoozeWithoutACountBeforeTheListLoadsIsSkipped() async {
        let state = AppState.forTesting()
        await state.handleNotificationAction(NotificationAction.snooze, category: NotificationCategory.carUnload)
        XCTAssertEqual(state.diagnostics.entries.last?.kind, .skipped)
        XCTAssertTrue(state.notificationService.scheduledForTesting.isEmpty)
    }

    @MainActor
    func testInertNotificationServiceRecordsWhatItWouldScheduleAndRemove() async throws {
        let service = NotificationService(center: nil)
        XCTAssertTrue(service.isInert)

        await service.scheduleHomeArrivalReminder(after: 600, itemCount: 3, repeats: true, repeatInterval: 300)

        XCTAssertEqual(service.scheduledForTesting.map(\.identifier), [NotificationID.carUnload, NotificationID.carUnloadRepeat])
        let first = try XCTUnwrap(service.scheduledForTesting.first)
        XCTAssertEqual(first.content.userInfo[NotificationUserInfo.itemCount] as? Int, 3)
        XCTAssertEqual((first.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval, 600)
        XCTAssertEqual(service.pendingCount, 2)

        service.markCarUnloadComplete()

        XCTAssertEqual(Array(service.removedForTesting.suffix(2)), [NotificationID.carUnload, NotificationID.carUnloadRepeat])
        try await waitUntil { service.pendingCount == 0 }

        // Never prompts.
        await service.requestAuthorization()
        XCTAssertEqual(service.authorizationStatus, .notDetermined)
    }

    @MainActor
    func testMarkUnloadCompleteStopsTheTimerAndIsLogged() {
        let state = AppState.forTesting()
        state.homeArrivalTimer.start(duration: 60)

        state.markUnloadComplete(source: "app")

        XCTAssertFalse(state.homeArrivalTimer.isActive)
        XCTAssertEqual(state.diagnostics.entries.last?.kind, .unloadDone)
    }

    @MainActor
    func testUnloadNotificationCarriesTheItemCount() {
        let content = NotificationService.carUnloadContent(itemCount: 3, isRepeat: false)
        XCTAssertEqual(content.userInfo[NotificationUserInfo.itemCount] as? Int, 3)
        XCTAssertEqual(content.categoryIdentifier, NotificationCategory.carUnload)
    }

    @MainActor
    func testTimerCountsDownFromTheArrival() {
        let timer = HomeArrivalTimerService()
        defer { timer.cancel() }

        timer.start(duration: 600, startedAt: Date().addingTimeInterval(-240))
        XCTAssertTrue(timer.isActive)
        XCTAssertTrue((359...361).contains(timer.remainingSeconds), "got \(timer.remainingSeconds)")

        timer.start(duration: 600, startedAt: Date().addingTimeInterval(-700))
        XCTAssertFalse(timer.isActive)
    }
}
