import XCTest
@testable import SmartGroceryReminder

final class ReceiptMatcherTests: XCTestCase {
    private func bought(_ name: String) -> ReceiptItem {
        ReceiptItem(name: name, price: nil, quantity: 1)
    }

    func testExtraWordsAndPluralsStillMatch() {
        let bananas = GroceryItem(title: "Banana")
        let milk = GroceryItem(title: "Milk")
        XCTAssertEqual(ReceiptMatcher.match(bought("Organic Bananas"), in: [milk, bananas]), bananas)
        XCTAssertEqual(ReceiptMatcher.match(bought("Milk 2% Gallon"), in: [bananas, milk]), milk)
    }

    func testOnlyWholeWordsMatch() {
        let list = [GroceryItem(title: "Butter"), GroceryItem(title: "Breadcrumbs")]
        XCTAssertNil(ReceiptMatcher.match(bought("Bread"), in: list))
    }

    func testTheItemSharingTheMostWordsWins() {
        let chicken = GroceryItem(title: "Chicken")
        let breast = GroceryItem(title: "Chicken breast")
        XCTAssertEqual(ReceiptMatcher.match(bought("Boneless Chicken Breast"), in: [chicken, breast]), breast)
    }

    func testOnATieTheEarlierItemWins() {
        let first = GroceryItem(title: "Eggs")
        let second = GroceryItem(title: "eggs")
        XCTAssertEqual(ReceiptMatcher.match(bought("Large Brown Eggs"), in: [first, second]), first)
    }

    func testDescribingWordsAloneNeverMatch() {
        XCTAssertNil(ReceiptMatcher.match(bought("Organic"), in: [GroceryItem(title: "Organic")]))
        XCTAssertNil(ReceiptMatcher.match(bought("Fresh Large Pack"), in: [GroceryItem(title: "Large apples")]))
    }

    func testAnEmptyListMatchesNothing() {
        XCTAssertNil(ReceiptMatcher.match(bought("Milk"), in: []))
    }
}
