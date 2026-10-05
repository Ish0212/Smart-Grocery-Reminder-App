import XCTest
@testable import SmartGroceryReminder

final class ReceiptParserTests: XCTestCase {
    /// A typical supermarket receipt as Vision would read it, line by line.
    private let receipt = [
        "WHOLE FOODS MARKET",
        "123 MAIN ST, SPRINGFIELD",
        "(555) 123-4567",
        "10/04/2026 14:32",
        "4011 ORG BANANAS 1.29 F",
        "MILK 2% GAL $4.99 F",
        "BNLS CHKN BRST 8.47 F",
        "2 AVOCADOS 2.50 F",
        "LG BROWN EGGS 3,99 F",
        "BREAD WHL WHEAT",
        "2 @ 1.99 3.98 F",
        "APPLES GALA",
        "1.52 lb @ 1.99/lb 3.02 F",
        "COUPON MILK -1.00 F",
        "ORANGE JUICE 52OZ 5.49 F",
        "ORG BANANAS 1.29 F",
        "SUBTOTAL 31.03",
        "TAX 0.00",
        "TOTAL 31.03",
        "VISA **** 1234 31.03",
        "CHANGE 0.00",
        "THANK YOU FOR SHOPPING",
    ]

    private func item(_ name: String, _ price: String, _ quantity: Int = 1) -> ReceiptItem {
        ReceiptItem(name: name, price: Decimal(string: price), quantity: quantity)
    }

    func testATypicalReceiptGivesItsPurchasesAndNothingElse() {
        XCTAssertEqual(ReceiptParser.parse(lines: receipt), [
            item("Organic Bananas", "1.29", 2),
            item("Milk 2% Gallon", "4.99"),
            item("Boneless Chicken Breast", "8.47"),
            item("Avocados", "2.50", 2),
            item("Large Brown Eggs", "3.99"),
            item("Bread Whole Wheat", "3.98", 2),
            item("Apples Gala", "3.02"),
            item("Orange Juice", "5.49"),
        ])
    }

    func testTotalsTaxAndPaymentAreNotPurchases() {
        let lines = ["SUBTOTAL 10.00", "TAX 0.80", "BALANCE DUE 10.80", "MASTERCARD 10.80", "YOU SAVED 1.00 SAVINGS"]
        XCTAssertTrue(ReceiptParser.parse(lines: lines).isEmpty)
    }

    func testDiscountsAreNotPurchases() {
        XCTAssertTrue(ReceiptParser.parse(lines: ["STORE DEAL -0.50", "BOGO 1.00-"]).isEmpty)
    }

    func testAQuantityLineSetsTheQuantityOfTheItemAbove() {
        XCTAssertEqual(ReceiptParser.parse(lines: ["YOGURT 2.97", "3 EA"]), [item("Yogurt", "2.97", 3)])
    }

    func testANameWithItsPriceAloneOnTheNextLine() {
        XCTAssertEqual(ReceiptParser.parse(lines: ["SPINACH", "2.49"]), [item("Spinach", "2.49")])
    }

    func testLinesWithoutAPriceAreNotPurchases() {
        XCTAssertTrue(ReceiptParser.parse(lines: ["FRESH PRODUCE", "CASHIER: SAM", "STORE 0042"]).isEmpty)
    }

    func testCleaningANameDropsCodesAndSpellsOutAbbreviations() {
        XCTAssertEqual(ReceiptParser.cleanName("0049000 GRN BEANS 16OZ")?.name, "Green Beans")
        XCTAssertNil(ReceiptParser.cleanName("004900012 16OZ"))
        XCTAssertEqual(ReceiptParser.cleanName("3 LIMES")?.quantity, 3)
    }
}

final class ReceiptTextTests: XCTestCase {
    private func fragment(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 0.3) -> TextFragment {
        TextFragment(text: text, box: CGRect(x: x, y: y, width: width, height: 0.02))
    }

    func testANameAndAPriceAtTheSameHeightAreOneLine() {
        let lines = ReceiptText.lines(from: [
            fragment("1.29 F", x: 0.7, y: 0.80, width: 0.15),
            fragment("BANANAS", x: 0.1, y: 0.80),
        ])
        XCTAssertEqual(lines, ["BANANAS 1.29 F"])
    }

    func testLinesRunTopToBottom() {
        let lines = ReceiptText.lines(from: [
            fragment("TOTAL 5.00", x: 0.1, y: 0.20),
            fragment("MILK 4.99", x: 0.1, y: 0.80),
            fragment("EGGS 3.99", x: 0.1, y: 0.75),
        ])
        XCTAssertEqual(lines, ["MILK 4.99", "EGGS 3.99", "TOTAL 5.00"])
    }

    func testASlightlyTiltedPhotoStillPairsNameAndPrice() {
        let lines = ReceiptText.lines(from: [
            fragment("BREAD", x: 0.1, y: 0.500),
            fragment("2.49", x: 0.7, y: 0.508, width: 0.1),
            fragment("MILK", x: 0.1, y: 0.470),
            fragment("4.99", x: 0.7, y: 0.478, width: 0.1),
        ])
        XCTAssertEqual(lines, ["BREAD 2.49", "MILK 4.99"])
    }
}

final class ReceiptParserEdgeTests: XCTestCase {
    func testFeesDepositsAndSavingsAreNotPurchases() {
        let lines = ["YOU SAVED 1.50", "BOTTLE DEPOSIT 0.10", "BAG FEE 0.10", "EBT FOOD 23.45", "CRV 0.05"]
        XCTAssertTrue(ReceiptParser.parse(lines: lines).isEmpty)
    }

    func testProductsNamedLikeReceiptWordsAreKept() {
        let names = ReceiptParser.parse(lines: ["MEMBER'S MARK EGGS 5.98", "GREETING CARD 3.49", "CASHEW MIX 6.99"]).map(\.name)
        XCTAssertEqual(names, ["Member's Mark Eggs", "Greeting Card", "Cashew Mix"])
    }

    func testAHeaderAboveAWeightLineWithoutAPriceIsNotAPurchase() {
        XCTAssertTrue(ReceiptParser.parse(lines: ["PRODUCE", "2.04 lb @ 1.49 /lb"]).isEmpty)
    }
}
