import XCTest
@testable import SmartGroceryReminder

final class ReceiptApplyTests: XCTestCase {
    @MainActor
    private func session(items: [GroceryItem]) async throws -> (AppState, MockShoppingListService) {
        let state = try await reliabilitySession(items: items)
        let service = try XCTUnwrap(state.listService as? MockShoppingListService)
        return (state, service)
    }

    @MainActor
    func testAMatchedItemIsCheckedOffAsBoughtByYou() async throws {
        let milk = GroceryItem(title: "Milk", notes: "2%")
        let (state, service) = try await session(items: [milk])

        let result = await state.applyReceipt([.checkOff(itemId: milk.id)])

        XCTAssertEqual(result, ReceiptResult(checkedOff: 1, added: 0))
        let sent = await service.patchesForTesting
        XCTAssertEqual(sent.map(\.itemId), [milk.id])
        XCTAssertEqual(sent.first?.patch.completion, ItemPatch.Completion(isCompleted: true, completedBy: Reliability.userId))
        XCTAssertNil(sent.first?.patch.title)
        XCTAssertEqual(state.shoppingList.first?.isCompleted, true)
        state.signOut()
    }

    @MainActor
    func testOtherPurchasesAreAddedAsAlreadyBought() async throws {
        let (state, _) = try await session(items: [])

        let result = await state.applyReceipt([.addBought(name: "  Avocados "), .addBought(name: "   ")])

        XCTAssertEqual(result, ReceiptResult(checkedOff: 0, added: 1))
        try await waitUntil { state.shoppingList.count == 1 }
        let added = try XCTUnwrap(state.shoppingList.first)
        XCTAssertEqual(added.title, "Avocados")
        XCTAssertTrue(added.isCompleted)
        XCTAssertEqual(added.completedBy, Reliability.userId)
        state.signOut()
    }

    @MainActor
    func testAnItemAlreadyCheckedOffIsLeftAloneSoScanningTwiceIsSafe() async throws {
        let done = GroceryItem(title: "Eggs", isCompleted: true, completedBy: "alice")
        let (state, service) = try await session(items: [done])

        let result = await state.applyReceipt([.checkOff(itemId: done.id), .skip])

        XCTAssertEqual(result, ReceiptResult())
        let sent = await service.patchesForTesting
        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(state.shoppingList.first?.completedBy, "alice")
        state.signOut()
    }
}
