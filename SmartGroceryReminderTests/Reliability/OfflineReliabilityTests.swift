import XCTest
@testable import SmartGroceryReminder

/// Offline, edits are kept on the phone until the server confirms them. The list says so, but
/// only when a change has really been waiting, not for the moment every online save takes.
final class OfflineReliabilityTests: XCTestCase {
    @MainActor
    private func session(noticeDelay: TimeInterval) async throws -> (AppState, MockShoppingListService) {
        let state = try await reliabilitySession(items: [])
        state.unsyncedNoticeDelay = noticeDelay
        let service = try XCTUnwrap(state.listService as? MockShoppingListService)
        return (state, service)
    }

    @MainActor
    func testChangesWaitingForTheServerShowTheNoticeUntilTheySync() async throws {
        let (state, service) = try await session(noticeDelay: 0)

        await service.setPendingWritesForTesting(true, listId: Reliability.userId)
        try await waitUntil { state.hasUnsyncedChanges }

        await service.setPendingWritesForTesting(false, listId: Reliability.userId)
        try await waitUntil { !state.hasUnsyncedChanges }
        state.signOut()
    }

    @MainActor
    func testAChangeTheServerConfirmsQuicklyNeverShowsTheNotice() async throws {
        let (state, service) = try await session(noticeDelay: 0.5)

        await service.setPendingWritesForTesting(true, listId: Reliability.userId)
        try await Task.sleep(nanoseconds: 100_000_000)
        await service.setPendingWritesForTesting(false, listId: Reliability.userId)
        try await Task.sleep(nanoseconds: 700_000_000)

        XCTAssertFalse(state.hasUnsyncedChanges)
        state.signOut()
    }

    @MainActor
    func testSigningOutClearsTheNotice() async throws {
        let (state, service) = try await session(noticeDelay: 0)
        await service.setPendingWritesForTesting(true, listId: Reliability.userId)
        try await waitUntil { state.hasUnsyncedChanges }

        state.signOut()

        XCTAssertFalse(state.hasUnsyncedChanges)
    }

    @MainActor
    func testSwitchingListsClearsTheNotice() async throws {
        let (state, service) = try await session(noticeDelay: 0)
        await service.setPendingWritesForTesting(true, listId: Reliability.userId)
        try await waitUntil { state.hasUnsyncedChanges }
        try await service.upsert(item: GroceryItem(title: "Alice's milk"), listId: "alice")
        let code = try await service.createInvite(userId: "alice")

        try await state.joinList(code: code)

        try await waitUntil { state.activeListId == "alice" }
        XCTAssertFalse(state.hasUnsyncedChanges)
        state.signOut()
    }
}
