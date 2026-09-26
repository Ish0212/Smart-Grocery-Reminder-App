import XCTest
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

    // MARK: - Flapping cooldown

    @MainActor
    func testHomeEnterInsideTheCooldownIsIgnored() {
        let decision = AppState.decision(
            for: event(), preferences: .default, items: items, now: now,
            lastHandled: now.addingTimeInterval(-5 * 60)
        )
        guard case .ignore(let reason) = decision else { return XCTFail("Expected ignore") }
        XCTAssertTrue(reason.contains("already handled"), reason)
    }

    @MainActor
    func testHomeEnterAfterTheCooldownSchedules() {
        let decision = AppState.decision(
            for: event(), preferences: .default, items: items, now: now,
            lastHandled: now.addingTimeInterval(-AppState.cooldown(for: .home))
        )
        guard case .scheduleUnload = decision else { return XCTFail("Expected scheduleUnload") }
    }

    @MainActor
    func testStoreCooldownIsLongerThanHome() {
        let twentyMinutesAgo = now.addingTimeInterval(-20 * 60)
        guard case .ignore = AppState.decision(
            for: event(.groceryStore), preferences: .default, items: items, now: now, lastHandled: twentyMinutesAgo
        ) else { return XCTFail("Expected the store enter to be ignored") }
        guard case .scheduleUnload = AppState.decision(
            for: event(.home), preferences: .default, items: items, now: now, lastHandled: twentyMinutesAgo
        ) else { return XCTFail("Expected the home enter to schedule") }
    }

    @MainActor
    func testSimulatedEventsSkipTheCooldown() {
        var simulated = event()
        simulated.isSimulated = true
        guard case .scheduleUnload = AppState.decision(
            for: simulated, preferences: .default, items: items, now: now, lastHandled: now.addingTimeInterval(-60)
        ) else { return XCTFail("Expected scheduleUnload") }
    }

    @MainActor
    func testArrivalOlderThanTheLastHandledTimeIsIgnored() {
        // e.g. a queued arrival from before "All brought in" was tapped.
        guard case .ignore = AppState.decision(
            for: event(secondsAgo: 120), preferences: .default, items: items, now: now, lastHandled: now
        ) else { return XCTFail("Expected ignore") }
    }

    @MainActor
    func testHomeArrivalSchedulesUnloadAfterTheConfiguredDelay() {
        var prefs = UserPreferences.default
        prefs.homeArrivalDelay = 600

        let decision = AppState.decision(for: event(), preferences: prefs, items: items, now: now)

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

        let late = AppState.decision(for: event(secondsAgo: 240), preferences: prefs, items: items, now: now)
        guard case .scheduleUnload(let delay, _, _, _) = late else { return XCTFail("Expected scheduleUnload") }
        XCTAssertEqual(delay, 360)

        let veryLate = AppState.decision(for: event(secondsAgo: 599), preferences: prefs, items: items, now: now)
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
        let state = AppState()
        let user = AppUser(id: "queued-user", email: "q@b.c", displayName: "Q")
        try await state.listService.upsert(item: GroceryItem(title: "Milk"), userId: user.id)
        state.currentUser = user

        state.handleLocationEvent(LocationEvent(kind: .home, transition: .enter, placeId: "default-home", date: Date()))
        XCTAssertEqual(state.pendingLocationEvents.count, 1)
        XCTAssertFalse(state.homeArrivalTimer.isActive)

        state.startSync(for: user)
        try await waitUntil { state.homeArrivalTimer.isActive }
        XCTAssertTrue(state.pendingLocationEvents.isEmpty)
        try await waitUntil { state.diagnostics.entries.contains { $0.kind == .unloadScheduled } }
        state.signOut()
    }

    @MainActor
    func testRunningOutOfBackgroundTimeDropsQueuedEvents() {
        let activity = FakeBackgroundActivity()
        let state = AppState(backgroundActivity: activity)
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
        let state = AppState(backgroundActivity: activity)
        state.currentUser = AppUser(id: "u", email: "u@b.c", displayName: "U")
        state.handleLocationEvent(LocationEvent(kind: .home, transition: .enter, placeId: "p", date: Date()))

        state.signOut()

        XCTAssertTrue(state.pendingLocationEvents.isEmpty)
        XCTAssertEqual(activity.ended, 1)
    }

    // MARK: - Notification actions and timer

    @MainActor
    func testSnoozeUsesTheCountFromTheNotification() async {
        let state = AppState()
        await state.handleNotificationAction(NotificationAction.snooze, category: NotificationCategory.carUnload, itemCount: 2)
        XCTAssertEqual(state.diagnostics.entries.last?.kind, .snoozed)
    }

    @MainActor
    func testSnoozeWithoutACountBeforeTheListLoadsIsSkipped() async {
        let state = AppState()
        await state.handleNotificationAction(NotificationAction.snooze, category: NotificationCategory.carUnload)
        XCTAssertEqual(state.diagnostics.entries.last?.kind, .skipped)
    }

    @MainActor
    func testMarkUnloadCompleteStopsTheTimerAndIsLogged() {
        let state = AppState()
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
