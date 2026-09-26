import XCTest
@testable import SmartGroceryReminder

/// `firestore.rules` only accepts items with exactly these fields. If this test fails because a
/// field was added or renamed, update `isValidItem` in `firestore.rules` and `firestore-tests/` too.
final class ModelKeysTests: XCTestCase {
    func testGroceryItemEncodesTheKeysTheRulesAllow() throws {
        // Optionals are only encoded when set, so set every one.
        let data = try JSONEncoder().encode(GroceryItem(title: "Milk", isCompleted: true, completedBy: "uid"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(
            Set(object.keys),
            ["id", "title", "notes", "aisle", "isCompleted", "completedBy", "createdAt", "updatedAt"]
        )
    }
}
