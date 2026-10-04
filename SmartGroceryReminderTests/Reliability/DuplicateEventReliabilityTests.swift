import XCTest
@testable import SmartGroceryReminder

/// iOS can report the same geofence crossing more than once: GPS jitter at the edge, and a replay
/// after it relaunches the app. Each real arrival must remind exactly once.
final class DuplicateEventReliabilityTests: XCTestCase {
    @MainActor
    private func unloadsScheduled(_ state: AppState) -> Int {
        state.diagnostics.entries.filter { $0.kind == .unloadScheduled }.count
    }

    @MainActor
    func testTheSameHomeEnterTwiceInAMomentRemindsOnce() async throws {
        let manager = FakeLocationManager()
        let state = try await reliabilitySession(manager: manager)

        manager.deliverEnter(Reliability.home, to: state.locationService)
        manager.deliverEnter(Reliability.home, to: state.locationService)

        try await waitUntil { state.diagnostics.entries.contains { $0.kind == .skipped } }
        XCTAssertEqual(unloadsScheduled(state), 1)
        state.signOut()
    }

    @MainActor
    func testFlappingAtTheHomeBoundaryRemindsOnce() async throws {
        let manager = FakeLocationManager()
        let state = try await reliabilitySession(manager: manager)

        manager.deliverEnter(Reliability.home, to: state.locationService)
        manager.deliverExit(Reliability.home, to: state.locationService)
        manager.deliverEnter(Reliability.home, to: state.locationService)
        manager.deliverExit(Reliability.home, to: state.locationService)
        manager.deliverEnter(Reliability.home, to: state.locationService)

        try await waitUntil { state.diagnostics.entries.filter { $0.kind == .skipped }.count == 2 }
        XCTAssertEqual(unloadsScheduled(state), 1)
        state.signOut()
    }

    @MainActor
    func testAnEnterReplayedWhileTheListLoadsRemindsOnce() async throws {
        // iOS relaunches the app for the enter and may deliver it again; the list isn't loaded yet.
        let manager = FakeLocationManager()
        let state = AppState.forTesting(locationManager: manager)
        let user = AppUser(id: Reliability.userId, email: "r@b.c", displayName: "R")
        try await state.listService.savePreferences(Reliability.preferences, userId: user.id)
        for item in Reliability.justBought {
            try await state.listService.upsert(item: item, listId: user.id)
        }
        state.currentUser = user
        state.isAuthenticated = true

        manager.deliverEnter(Reliability.home, to: state.locationService)
        manager.deliverEnter(Reliability.home, to: state.locationService)
        XCTAssertTrue(state.diagnostics.entries.contains { $0.kind == .queued })

        state.startSync(for: user)

        try await waitUntil { self.unloadsScheduled(state) >= 1 }
        // Give a second, late reminder the chance to appear before asserting it didn't.
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(unloadsScheduled(state), 1)
        state.signOut()
    }
}
