import XCTest
@testable import SmartGroceryReminder

final class MockShoppingListServiceTests: XCTestCase {
    func testDemoUserStartsWithSampleItems() async throws {
        let items = try await MockShoppingListService().fetchItems(userId: "demo-user")
        XCTAssertEqual(items.count, SampleData.groceryItems.count)
    }

    func testUpsertInsertsNewItemAtFront() async throws {
        let service = MockShoppingListService()
        let item = GroceryItem(title: "Apples")
        try await service.upsert(item: item, userId: "demo-user")

        let items = try await service.fetchItems(userId: "demo-user")
        XCTAssertEqual(items.first, item)
        XCTAssertEqual(items.count, SampleData.groceryItems.count + 1)
    }

    func testUpsertReplacesExistingItemInPlace() async throws {
        let service = MockShoppingListService()
        var item = try await service.fetchItems(userId: "demo-user")[2]
        item.isCompleted = true
        try await service.upsert(item: item, userId: "demo-user")

        let items = try await service.fetchItems(userId: "demo-user")
        XCTAssertEqual(items.count, SampleData.groceryItems.count)
        XCTAssertEqual(items[2], item)
    }

    func testDeleteRemovesById() async throws {
        let service = MockShoppingListService()
        let target = SampleData.groceryItems[0]
        try await service.delete(itemId: target.id, userId: "demo-user")

        let items = try await service.fetchItems(userId: "demo-user")
        XCTAssertFalse(items.contains { $0.id == target.id })
    }

    func testUnknownUserGetsDefaultPreferences() async throws {
        let prefs = try await MockShoppingListService().fetchPreferences(userId: "someone-else")
        XCTAssertEqual(prefs, .default)
    }

    func testSavedPreferencesRoundTrip() async throws {
        let service = MockShoppingListService()
        var prefs = UserPreferences.default
        prefs.homeArrivalDelay = 5 * 60
        prefs.storeEntryReminderEnabled = false
        try await service.savePreferences(prefs, userId: "u1")

        let fetched = try await service.fetchPreferences(userId: "u1")
        XCTAssertEqual(fetched, prefs)
    }
}
