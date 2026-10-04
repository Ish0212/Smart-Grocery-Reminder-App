import XCTest
@testable import SmartGroceryReminder

/// iOS kills the app in the background whenever it likes, and relaunches it for a geofence.
/// What the user was in the middle of must survive that.
final class RelaunchReliabilityTests: XCTestCase {
    @MainActor
    func testARunningCountdownSurvivesTheAppBeingKilled() async throws {
        let directory = temporaryDirectory()
        let manager = FakeLocationManager()
        var first: AppState? = try await reliabilitySession(manager: manager, stateDirectory: directory)
        manager.deliverEnter(Reliability.home, to: first!.locationService)
        try await waitUntil { first!.homeArrivalTimer.isActive }
        let endDate = try XCTUnwrap(first!.homeArrivalTimer.endDate)
        first!.homeArrivalTimer.cancelTickingForTesting()
        first = nil // killed: no sign-out, nothing cleaned up

        let relaunched = AppState.forTesting(stateDirectory: directory, locationManager: FakeLocationManager())

        XCTAssertTrue(relaunched.homeArrivalTimer.isActive)
        XCTAssertEqual(relaunched.homeArrivalTimer.endDate, endDate)
        relaunched.homeArrivalTimer.cancel()
    }

    @MainActor
    func testACooldownSurvivesTheAppBeingKilled() async throws {
        let directory = temporaryDirectory()
        let firstManager = FakeLocationManager()
        let first = try await reliabilitySession(manager: firstManager, stateDirectory: directory)
        firstManager.deliverEnter(Reliability.home, to: first.locationService)
        try await waitUntil { first.diagnostics.entries.contains { $0.kind == .unloadScheduled } }
        first.homeArrivalTimer.cancel() // only the cooldown matters here

        let secondManager = FakeLocationManager()
        let relaunched = try await reliabilitySession(manager: secondManager, stateDirectory: directory)
        secondManager.deliverEnter(Reliability.home, to: relaunched.locationService)

        try await waitUntil { relaunched.diagnostics.entries.contains { $0.kind == .skipped } }
        XCTAssertFalse(relaunched.diagnostics.entries.contains { $0.kind == .unloadScheduled })
        relaunched.signOut()
    }

    @MainActor
    func testACountdownThatEndedWhileKilledDoesNotComeBack() throws {
        let directory = temporaryDirectory()
        let store = JSONFileStore<ArrivalTimerState>(url: directory.appendingPathComponent("arrival-timer.json"))
        try store.save(ArrivalTimerState(endDate: Date().addingTimeInterval(-60), duration: 600))

        let relaunched = AppState.forTesting(stateDirectory: directory, locationManager: FakeLocationManager())

        XCTAssertFalse(relaunched.homeArrivalTimer.isActive)
        XCTAssertNil(relaunched.homeArrivalTimer.endDate)
    }

    @MainActor
    func testCorruptStateFilesStartCleanInsteadOfCrashing() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: directory.appendingPathComponent("arrival-timer.json"))
        try Data("{not json".utf8).write(to: directory.appendingPathComponent("reminder-cooldowns.json"))

        let relaunched = AppState.forTesting(stateDirectory: directory, locationManager: FakeLocationManager())

        XCTAssertFalse(relaunched.homeArrivalTimer.isActive)
        XCTAssertNil(relaunched.lastUnloadScheduled)
        XCTAssertNil(relaunched.lastUnloadDone)
        XCTAssertFalse(relaunched.unloadOutstanding)
    }
}
