import XCTest
@testable import SmartGroceryReminder

/// Family members edit the same list, often offline, and their changes reach the server in any
/// order. Each test starts two editors from the same copy of an item, as two phones would have it.
final class ConflictReliabilityTests: XCTestCase {
    private let listId = "demo-user"
    private var base: GroceryItem { SampleData.groceryItems[0] }
    private let t0 = Date(timeIntervalSince1970: 3_000_000)

    private func stored(_ service: MockShoppingListService, _ id: String) async throws -> GroceryItem? {
        for try await items in await service.observeItems(listId: listId) {
            return items.first { $0.id == id }
        }
        return nil
    }

    private func patch(_ edit: (inout GroceryItem) -> Void, at seconds: TimeInterval) throws -> ItemPatch {
        var edited = base
        edit(&edited)
        return try XCTUnwrap(ItemPatch.changes(from: base, to: edited, at: t0.addingTimeInterval(seconds)))
    }

    // MARK: - Conflicts

    func testARenameAndACheckOffBothSurviveInEitherOrder() async throws {
        let rename = try patch({ $0.title = "Oat milk" }, at: 1)
        let checkOff = try patch({ $0.isCompleted = true; $0.completedBy = "bob" }, at: 2)

        for order in [[rename, checkOff], [checkOff, rename]] {
            let service = MockShoppingListService()
            for patch in order {
                try await service.update(itemId: base.id, patch: patch, listId: listId)
            }

            let found = try await stored(service, base.id)
            let item = try XCTUnwrap(found)
            XCTAssertEqual(item.title, "Oat milk")
            XCTAssertTrue(item.isCompleted)
            XCTAssertEqual(item.completedBy, "bob")
            XCTAssertEqual(item.notes, base.notes)
        }
    }

    func testTwoEditsToTheSameFieldLeaveTheLastOneToArrive() async throws {
        let service = MockShoppingListService()
        try await service.update(itemId: base.id, patch: try patch({ $0.title = "Oat milk" }, at: 1), listId: listId)
        try await service.update(itemId: base.id, patch: try patch({ $0.title = "Almond milk" }, at: 2), listId: listId)

        let found = try await stored(service, base.id)
        let item = try XCTUnwrap(found)
        XCTAssertEqual(item.title, "Almond milk")
    }

    func testAnEditToAnItemSomeoneDeletedLeavesItDeleted() async throws {
        let service = MockShoppingListService()
        try await service.delete(itemId: base.id, listId: listId)

        try await service.update(itemId: base.id, patch: try patch({ $0.notes = "the big one" }, at: 1), listId: listId)

        let item = try await stored(service, base.id)
        XCTAssertNil(item)
    }

    func testTwoCheckOffsLeaveItCheckedOffByTheLastWriter() async throws {
        let service = MockShoppingListService()
        try await service.update(itemId: base.id, patch: try patch({ $0.isCompleted = true; $0.completedBy = "alice" }, at: 1), listId: listId)
        try await service.update(itemId: base.id, patch: try patch({ $0.isCompleted = true; $0.completedBy = "bob" }, at: 2), listId: listId)

        let found = try await stored(service, base.id)
        let item = try XCTUnwrap(found)
        XCTAssertTrue(item.isCompleted)
        XCTAssertEqual(item.completedBy, "bob")
    }

    // MARK: - What the app sends

    @MainActor
    private func session(items: [GroceryItem]) async throws -> (AppState, MockShoppingListService) {
        let state = try await reliabilitySession(items: items)
        let service = try XCTUnwrap(state.listService as? MockShoppingListService)
        return (state, service)
    }

    @MainActor
    func testEditingSendsOnlyTheFieldsThatChanged() async throws {
        let milk = GroceryItem(title: "Milk", notes: "2%", aisle: "Dairy")
        let (state, service) = try await session(items: [milk])

        await state.editItem(milk, title: "  Oat milk ", notes: "2%", aisle: "Dairy")

        let sent = await service.patchesForTesting
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.itemId, milk.id)
        XCTAssertEqual(sent.first?.patch.title, "Oat milk")
        XCTAssertNil(sent.first?.patch.notes)
        XCTAssertNil(sent.first?.patch.aisle)
        XCTAssertNil(sent.first?.patch.completion)
        XCTAssertEqual(state.shoppingList.first?.title, "Oat milk")
        state.signOut()
    }

    @MainActor
    func testAnEmptyNameOrNoChangeSendsNothing() async throws {
        let milk = GroceryItem(title: "Milk")
        let (state, service) = try await session(items: [milk])

        await state.editItem(milk, title: "   ", notes: "", aisle: "")
        await state.editItem(milk, title: "Milk", notes: "", aisle: "")

        let sent = await service.patchesForTesting
        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(state.shoppingList.first?.title, "Milk")
        state.signOut()
    }

    @MainActor
    func testCheckingOffSendsOnlyTheCompletion() async throws {
        let milk = GroceryItem(title: "Milk", notes: "2%")
        let (state, service) = try await session(items: [milk])

        await state.toggleItem(milk)

        let sent = await service.patchesForTesting
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.patch.completion, ItemPatch.Completion(isCompleted: true, completedBy: Reliability.userId))
        XCTAssertNil(sent.first?.patch.title)
        XCTAssertNil(sent.first?.patch.notes)
        XCTAssertNil(sent.first?.patch.aisle)
        state.signOut()
    }

    @MainActor
    func testARenameWhileTheEditSheetIsOpenIsNotUndoneBySaving() async throws {
        let milk = GroceryItem(title: "Milk")
        let (state, service) = try await session(items: [milk])
        // The sheet opened with this copy; then a family member renames the item.
        let opened = milk
        try await service.update(itemId: milk.id, patch: ItemPatch(title: "Oat milk", updatedAt: Date()), listId: Reliability.userId)
        try await waitUntil { state.shoppingList.first?.title == "Oat milk" }

        // Save after changing only the notes; the sheet still shows the old name.
        await state.editItem(opened, title: "Milk", notes: "the big one", aisle: "")

        let sent = await service.patchesForTesting.last?.patch
        XCTAssertNil(sent?.title)
        XCTAssertEqual(sent?.notes, "the big one")
        XCTAssertEqual(state.shoppingList.first?.title, "Oat milk")
        XCTAssertEqual(state.shoppingList.first?.notes, "the big one")
        state.signOut()
    }
}
