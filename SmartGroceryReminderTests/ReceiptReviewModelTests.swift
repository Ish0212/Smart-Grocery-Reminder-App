import XCTest
import UIKit
@testable import SmartGroceryReminder

private struct FakeRecognizer: TextRecognizer {
    var lines: [String] = []
    var error: Error?

    /// One fragment per line, stacked top to bottom.
    func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation) async throws -> [TextFragment] {
        if let error { throw error }
        return lines.enumerated().map { index, text in
            TextFragment(text: text, box: CGRect(x: 0.1, y: 0.9 - CGFloat(index) * 0.05, width: 0.8, height: 0.02))
        }
    }
}

final class ReceiptReviewModelTests: XCTestCase {
    private let photo = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { _ in }

    @MainActor
    func testMatchedPurchasesAreCheckedOffAndTheRestAdded() async {
        let milk = GroceryItem(title: "Milk")
        let model = ReceiptReviewModel(recognizer: FakeRecognizer(lines: ["MILK 2% GAL 4.99", "AVOCADOS 2.50", "TOTAL 7.49"]))

        await model.read(photo, openItems: [milk])

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.rows.map(\.name), ["Milk 2% Gallon", "Avocados"])
        XCTAssertEqual(model.rows.map(\.action), [.checkOff, .add])
        XCTAssertEqual(model.decisions, [.checkOff(itemId: milk.id), .addBought(name: "Avocados")])
    }

    @MainActor
    func testTwoPurchasesNeverClaimTheSameListItem() async {
        let milk = GroceryItem(title: "Milk")
        let model = ReceiptReviewModel(recognizer: FakeRecognizer(lines: ["WHOLE MILK 3.49", "OAT MILK 4.49"]))

        await model.read(photo, openItems: [milk])

        XCTAssertEqual(model.rows.map(\.match), [milk, nil])
        XCTAssertEqual(model.decisions, [.checkOff(itemId: milk.id), .addBought(name: "Oat Milk")])
    }

    @MainActor
    func testCorrectionsAreWhatGetsApplied() async {
        let milk = GroceryItem(title: "Milk")
        let model = ReceiptReviewModel(recognizer: FakeRecognizer(lines: ["MILK 4.99", "CHOC BAR 1.99", "BAG FEE 0.10"]))
        await model.read(photo, openItems: [milk])

        model.rows[0].action = .add
        model.rows[0].name = "Oat milk"
        model.rows[1].name = "Chocolate bar"
        model.rows[2].action = .skip

        XCTAssertEqual(model.decisions, [.addBought(name: "Oat milk"), .addBought(name: "Chocolate bar"), .skip])
    }

    @MainActor
    func testAReceiptWithNoPurchasesSaysSo() async {
        let model = ReceiptReviewModel(recognizer: FakeRecognizer(lines: ["THANK YOU", "TOTAL 0.00"]))

        await model.read(photo, openItems: [])

        XCTAssertEqual(model.phase, .empty)
        XCTAssertTrue(model.rows.isEmpty)
    }

    @MainActor
    func testAPhotoThatCantBeReadSaysSo() async {
        struct VisionFailed: Error {}
        let failing = ReceiptReviewModel(recognizer: FakeRecognizer(error: VisionFailed()))
        await failing.read(photo, openItems: [])
        XCTAssertEqual(failing.phase, .failed)

        let model = ReceiptReviewModel(recognizer: FakeRecognizer(lines: ["MILK 4.99"]))
        await model.read(nil, openItems: [])
        XCTAssertEqual(model.phase, .failed)
        await model.read(UIImage(), openItems: [])
        XCTAssertEqual(model.phase, .failed)
    }
}
