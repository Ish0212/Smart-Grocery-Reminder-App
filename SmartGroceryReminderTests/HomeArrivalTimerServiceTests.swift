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
