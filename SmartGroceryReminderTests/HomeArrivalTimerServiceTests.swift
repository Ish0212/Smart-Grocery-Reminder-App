import XCTest
@testable import SmartGroceryReminder

final class HomeArrivalTimerServiceTests: XCTestCase {
    @MainActor
    func testStartSetsCountdown() async {
        let timer = HomeArrivalTimerService()
        defer { timer.cancel() }
        timer.start(duration: 600)

        XCTAssertTrue(timer.isActive)
        XCTAssertEqual(timer.remainingSeconds, 600)
        XCTAssertEqual(timer.selectedDelay, 600)
        XCTAssertEqual(timer.formattedRemaining, "10:00")
    }

    @MainActor
    func testRefreshRecomputesFromEndDate() async {
        let timer = HomeArrivalTimerService()
        defer { timer.cancel() }
        timer.start(duration: 600)
        timer.refresh(now: Date().addingTimeInterval(300))

        XCTAssertTrue(timer.isActive)
        XCTAssertTrue((298...300).contains(timer.remainingSeconds), "got \(timer.remainingSeconds)")
    }

    @MainActor
    func testRefreshPastEndStopsTimer() async {
        let timer = HomeArrivalTimerService()
        defer { timer.cancel() }
        timer.start(duration: 600)
        timer.refresh(now: Date().addingTimeInterval(601))

        XCTAssertFalse(timer.isActive)
        XCTAssertEqual(timer.remainingSeconds, 0)
        XCTAssertNil(timer.endDate, "No countdown is running")
    }

    @MainActor
    func testCompleteUnloadResetsState() async {
        let timer = HomeArrivalTimerService()
        timer.start(duration: 300)
        timer.completeUnload()

        XCTAssertFalse(timer.isActive)
        XCTAssertEqual(timer.remainingSeconds, 0)
        XCTAssertEqual(timer.formattedRemaining, "00:00")
    }
}

final class ArrivalTimerPersistenceTests: XCTestCase {
    @MainActor
    func testRunningCountdownIsRestoredByANewInstance() {
        let store = JSONFileStore<ArrivalTimerState>(url: temporaryFileURL())
        let start = Date()
        HomeArrivalTimerService(store: store).start(duration: 600, startedAt: start)

        let restored = HomeArrivalTimerService(store: store, now: start.addingTimeInterval(120))

        XCTAssertTrue(restored.isActive)
        XCTAssertEqual(restored.remainingSeconds, 480)
        XCTAssertEqual(restored.selectedDelay, 600)
        restored.cancel()
    }

    @MainActor
    func testFinishedCountdownIsNotRestored() {
        let store = JSONFileStore<ArrivalTimerState>(url: temporaryFileURL())
        let start = Date()
        let first = HomeArrivalTimerService(store: store)
        first.start(duration: 60, startedAt: start)

        let restored = HomeArrivalTimerService(store: store, now: start.addingTimeInterval(61))

        XCTAssertFalse(restored.isActive)
        XCTAssertEqual(restored.remainingSeconds, 0)
        first.cancel()
    }

    @MainActor
    func testCancelledCountdownIsNotRestored() {
        let store = JSONFileStore<ArrivalTimerState>(url: temporaryFileURL())
        let timer = HomeArrivalTimerService(store: store)
        timer.start(duration: 600)
        timer.completeUnload()

        XCTAssertFalse(HomeArrivalTimerService(store: store).isActive)
        guard case .missing = store.load() else { return XCTFail("Expected the saved countdown to be removed") }
    }
}
