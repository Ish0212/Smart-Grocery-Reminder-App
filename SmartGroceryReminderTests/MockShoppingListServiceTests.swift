import XCTest
@testable import SmartGroceryReminder

final class MockShoppingListServiceTests: XCTestCase {
    /// The first value a stream emits: the current state.
    private func current<T>(_ stream: AsyncThrowingStream<T, Error>) async throws -> T? {
        try await stream.first { _ in true }
    }

    func testDemoUserStartsWithSampleItems() async throws {
        let items = try await current(await MockShoppingListService().observeItems(listId: "demo-user"))
        XCTAssertEqual(items, SampleData.groceryItems)
    }

    func testUnknownUserStartsWithEmptyList() async throws {
        let items = try await current(await MockShoppingListService().observeItems(listId: "someone-else"))
        XCTAssertEqual(items, [])
    }

    func testUpsertInsertsNewItemAtFront() async throws {
        let service = MockShoppingListService()
        let item = GroceryItem(title: "Apples")
        try await service.upsert(item: item, listId: "demo-user")

        let items = try await current(await service.observeItems(listId: "demo-user")) ?? []
        XCTAssertEqual(items.first, item)
        XCTAssertEqual(items.count, SampleData.groceryItems.count + 1)
    }

    func testUpsertReplacesExistingItemInPlace() async throws {
        let service = MockShoppingListService()
        var item = SampleData.groceryItems[2]
        item.isCompleted = true
        try await service.upsert(item: item, listId: "demo-user")

        let items = try await current(await service.observeItems(listId: "demo-user")) ?? []
        XCTAssertEqual(items.count, SampleData.groceryItems.count)
        XCTAssertEqual(items[2], item)
    }

    func testDeleteRemovesById() async throws {
        let service = MockShoppingListService()
        let target = SampleData.groceryItems[0]
        try await service.delete(itemId: target.id, listId: "demo-user")

        let items = try await current(await service.observeItems(listId: "demo-user")) ?? []
        XCTAssertFalse(items.contains { $0.id == target.id })
    }

    func testUpdateChangesAnItemInPlace() async throws {
        let service = MockShoppingListService()
        var item = SampleData.groceryItems[2]
        let patch = ItemPatch(completion: .init(isCompleted: true, completedBy: "demo-user"), updatedAt: Date())
        item = patch.applied(to: item)
        try await service.update(itemId: item.id, patch: patch, listId: "demo-user")

        let items = try await current(await service.observeItems(listId: "demo-user")) ?? []
        XCTAssertEqual(items.count, SampleData.groceryItems.count)
        XCTAssertEqual(items[2], item)
    }

    func testUpdatingADeletedItemDoesntBringItBack() async throws {
        let service = MockShoppingListService()
        let item = SampleData.groceryItems[0]
        try await service.delete(itemId: item.id, listId: "demo-user")

        // Someone else deleted it while this user was checking it off.
        try await service.update(
            itemId: item.id,
            patch: ItemPatch(completion: .init(isCompleted: true, completedBy: "demo-user"), updatedAt: Date()),
            listId: "demo-user"
        )

        let items = try await current(await service.observeItems(listId: "demo-user")) ?? []
        XCTAssertFalse(items.contains { $0.id == item.id })
        XCTAssertEqual(items.count, SampleData.groceryItems.count - 1)
    }

    func testObserverReceivesEveryChange() async throws {
        let service = MockShoppingListService()
        var updates = await service.observeItems(listId: "u1").makeAsyncIterator()
        let initial = try await updates.next()
        XCTAssertEqual(initial, [])

        let item = GroceryItem(title: "Apples")
        try await service.upsert(item: item, listId: "u1")
        let afterUpsert = try await updates.next()
        XCTAssertEqual(afterUpsert, [item])

        try await service.delete(itemId: item.id, listId: "u1")
        let afterDelete = try await updates.next()
        XCTAssertEqual(afterDelete, [])
    }

    func testUnknownUserGetsDefaultPreferences() async throws {
        let prefs = try await current(await MockShoppingListService().observePreferences(userId: "someone-else"))
        XCTAssertEqual(prefs, .default)
    }

    func testPreferenceObserverReceivesSaves() async throws {
        let service = MockShoppingListService()
        var updates = await service.observePreferences(userId: "u1").makeAsyncIterator()
        _ = try await updates.next()

        var prefs = UserPreferences.default
        prefs.homeArrivalDelay = 5 * 60
        prefs.storeEntryReminderEnabled = false
        try await service.savePreferences(prefs, userId: "u1")

        let saved = try await updates.next()
        XCTAssertEqual(saved, prefs)
        let refetched = try await current(await service.observePreferences(userId: "u1"))
        XCTAssertEqual(refetched, prefs)
    }
}
