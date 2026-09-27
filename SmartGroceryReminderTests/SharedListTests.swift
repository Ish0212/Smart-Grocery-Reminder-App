import XCTest
@testable import SmartGroceryReminder

/// A clock tests can move forward, for invite expiry.
private final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_000_000)
}

final class InviteCodeTests: XCTestCase {
    func testCodesUseTheReadableAlphabet() {
        for _ in 0..<50 {
            let code = InviteCode.generate()
            XCTAssertEqual(code.count, InviteCode.length)
            XCTAssertTrue(code.allSatisfy { InviteCode.alphabet.contains($0) }, code)
        }
        XCTAssertFalse(InviteCode.alphabet.contains { "01OIL".contains($0) })
    }

    func testNormalizeAcceptsTypingVariations() {
        XCTAssertEqual(InviteCode.normalize("abcd-2345"), "ABCD2345")
        XCTAssertEqual(InviteCode.normalize(" ABCD 2345 "), "ABCD2345")
    }
}

final class MockSharedListTests: XCTestCase {
    private func first<T>(_ stream: AsyncThrowingStream<T, Error>) async throws -> T? {
        try await stream.first { _ in true }
    }

    func testEveryoneStartsOnTheirOwnList() async throws {
        let service = MockShoppingListService()
        let active = try await first(await service.observeActiveList(userId: "alice"))
        XCTAssertEqual(active, "alice")
        let info = try await service.listInfo(listId: "alice")
        XCTAssertEqual(info, .personal("alice"))
        XCTAssertFalse(info.isShared)
    }

    func testJoiningSharesTheItemsBothWays() async throws {
        let service = MockShoppingListService()
        try await service.upsert(item: GroceryItem(title: "Milk"), listId: "alice")
        let code = try await service.createInvite(userId: "alice")

        var bobsList = await service.observeActiveList(userId: "bob").makeAsyncIterator()
        let before = try await bobsList.next()
        XCTAssertEqual(before, "bob")
        try await service.joinList(code: code.lowercased(), userId: "bob")
        let after = try await bobsList.next()
        XCTAssertEqual(after, "alice")

        try await service.upsert(item: GroceryItem(title: "Bread"), listId: "alice")
        let items = try await first(await service.observeItems(listId: "alice"))
        XCTAssertEqual(items?.map(\.title), ["Bread", "Milk"])
        let info = try await service.listInfo(listId: "alice")
        XCTAssertEqual(info.memberIds, ["alice", "bob"])
    }

    func testWrongOrExpiredCodesFail() async throws {
        let clock = TestClock()
        let service = MockShoppingListService(now: { clock.now })
        let code = try await service.createInvite(userId: "alice")

        do {
            try await service.joinList(code: "ZZZZZZZZ", userId: "bob")
            XCTFail("Expected invalidCode")
        } catch let error as SharedListError {
            XCTAssertEqual(error, .invalidCode)
        }

        clock.now = clock.now.addingTimeInterval(InviteCode.lifetime + 1)
        do {
            try await service.joinList(code: code, userId: "bob")
            XCTFail("Expected expiredCode")
        } catch let error as SharedListError {
            XCTAssertEqual(error, .expiredCode)
        }
    }

    func testListsAreCapped() async throws {
        let service = MockShoppingListService()
        let code = try await service.createInvite(userId: "owner")
        for index in 1..<SharedListInfo.maxMembers {
            try await service.joinList(code: code, userId: "member-\(index)")
        }
        do {
            try await service.joinList(code: code, userId: "one-too-many")
            XCTFail("Expected listFull")
        } catch let error as SharedListError {
            XCTAssertEqual(error, .listFull)
        }
        // Someone already on the list can use the code again.
        try await service.joinList(code: code, userId: "member-1")
    }

    func testLeavingGoesBackToYourOwnItems() async throws {
        let service = MockShoppingListService()
        try await service.upsert(item: GroceryItem(title: "Bob's own"), listId: "bob")
        let code = try await service.createInvite(userId: "alice")
        try await service.joinList(code: code, userId: "bob")

        try await service.leaveList(userId: "bob")

        let active = try await first(await service.observeActiveList(userId: "bob"))
        XCTAssertEqual(active, "bob")
        let items = try await first(await service.observeItems(listId: "bob"))
        XCTAssertEqual(items?.map(\.title), ["Bob's own"])
        let info = try await service.listInfo(listId: "alice")
        XCTAssertEqual(info.memberIds, ["alice"])
    }

    func testYouCantLeaveYourOwnList() async throws {
        let service = MockShoppingListService()
        do {
            try await service.leaveList(userId: "alice")
            XCTFail("Expected cannotLeaveOwnList")
        } catch let error as SharedListError {
            XCTAssertEqual(error, .cannotLeaveOwnList)
        }
    }

    func testMembershipSurvivesANewInstance() async throws {
        let store = JSONFileStore<MockListSnapshot>(url: temporaryFileURL())
        let firstService = MockShoppingListService(store: store)
        let code = try await firstService.createInvite(userId: "alice")
        try await firstService.joinList(code: code, userId: "bob")

        let second = MockShoppingListService(store: store)
        let active = try await first(await second.observeActiveList(userId: "bob"))
        XCTAssertEqual(active, "alice")
    }

    func testFilesSavedBeforeSharedListsStillLoad() async throws {
        let url = temporaryFileURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // The Phase 3–5 format: no lists, invites or active lists.
        let old = #"{"itemsByUser":{"u1":[]},"preferencesByUser":{}}"#
        try Data(old.utf8).write(to: url)
        guard case .loaded(let snapshot) = JSONFileStore<MockListSnapshot>(url: url).load() else {
            return XCTFail("Expected the old file to decode")
        }
        XCTAssertNil(snapshot.lists)

        let service = MockShoppingListService(store: JSONFileStore(url: url))
        let active = try await first(await service.observeActiveList(userId: "u1"))
        XCTAssertEqual(active, "u1")
    }
}

final class AppStateSharedListTests: XCTestCase {
    @MainActor
    private func signedInState(_ userId: String) -> AppState {
        let state = AppState.forTesting()
        let user = AppUser(id: userId, email: "\(userId)@b.c", displayName: userId)
        state.currentUser = user
        state.isAuthenticated = true
        state.startSync(for: user)
        return state
    }

    @MainActor
    func testJoiningSwitchesTheListAndEditsGoToTheSharedList() async throws {
        let state = signedInState("bob")
        try await waitUntil { state.activeListId == "bob" && state.itemsLoaded }
        try await state.listService.upsert(item: GroceryItem(title: "Alice's milk"), listId: "alice")
        let code = try await state.listService.createInvite(userId: "alice")

        try await state.joinList(code: code)
        try await waitUntil { state.activeListId == "alice" && state.shoppingList.map(\.title) == ["Alice's milk"] }

        await state.addItem("Bread")
        let aliceItems = try await state.listService.observeItems(listId: "alice").first { _ in true }
        XCTAssertEqual(aliceItems?.map(\.title), ["Bread", "Alice's milk"])
        try await waitUntil { state.sharedList?.memberIds == ["alice", "bob"] }

        try await state.leaveSharedList()
        try await waitUntil { state.activeListId == "bob" && state.shoppingList.isEmpty }
        state.signOut()
        XCTAssertNil(state.activeListId)
    }

    @MainActor
    func testAFailedJoinKeepsTheCurrentList() async throws {
        let state = signedInState("bob")
        try await state.listService.upsert(item: GroceryItem(title: "Bob's"), listId: "bob")
        try await waitUntil { state.shoppingList.map(\.title) == ["Bob's"] }

        do {
            try await state.joinList(code: "ZZZZZZZZ")
            XCTFail("Expected invalidCode")
        } catch let error as SharedListError {
            XCTAssertEqual(error, .invalidCode)
        }

        try await state.listService.upsert(item: GroceryItem(title: "Still syncing"), listId: "bob")
        try await waitUntil { state.shoppingList.map(\.title) == ["Still syncing", "Bob's"] }
        XCTAssertEqual(state.activeListId, "bob")
        state.signOut()
    }

    @MainActor
    func testTogglingRecordsWhoCheckedItOff() async throws {
        let state = signedInState("bob")
        try await state.listService.upsert(item: GroceryItem(title: "Milk"), listId: "bob")
        try await waitUntil { state.shoppingList.count == 1 }

        // Sync echoes each save back, so wait for the list to settle after each toggle.
        await state.toggleItem(state.shoppingList[0])
        try await waitUntil { state.shoppingList.first?.completedBy == "bob" }
        let saved = try await state.listService.observeItems(listId: "bob").first { _ in true }
        XCTAssertEqual(saved?.first?.completedBy, "bob")

        await state.toggleItem(state.shoppingList[0])
        try await waitUntil { state.shoppingList.first.map { !$0.isCompleted && $0.completedBy == nil } == true }
        state.signOut()
    }

    @MainActor
    func testSomeoneElsesCheckOffsDontCountForYourUnloadReminder() async throws {
        let now = Date()
        let items = [
            GroceryItem(title: "Mine", isCompleted: true, completedBy: "bob", updatedAt: now.addingTimeInterval(-10 * 60)),
            GroceryItem(title: "Alice's", isCompleted: true, completedBy: "alice", updatedAt: now.addingTimeInterval(-10 * 60)),
            GroceryItem(title: "Before sharing", isCompleted: true, updatedAt: now.addingTimeInterval(-10 * 60)),
        ]
        let plan = try XCTUnwrap(AppState.carUnloadReminderPlan(preferences: .default, items: items, now: now, context: .init(userId: "bob")))
        XCTAssertEqual(plan.itemCount, 2)

        let onlyAlices = [items[1]]
        XCTAssertNil(AppState.carUnloadReminderPlan(preferences: .default, items: onlyAlices, now: now, context: .init(userId: "bob")))
    }
}
