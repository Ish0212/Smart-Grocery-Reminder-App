import XCTest
import FirebaseFirestore
@testable import SmartGroceryReminder

final class ItemPatchTests: XCTestCase {
    private let base = GroceryItem(id: "i", title: "Milk", notes: "2%", aisle: "Dairy")
    private let later = Date(timeIntervalSince1970: 2_000_000)

    func testARenameChangesOnlyTheTitle() throws {
        var edited = base
        edited.title = "Oat milk"

        let patch = try XCTUnwrap(ItemPatch.changes(from: base, to: edited, at: later))

        XCTAssertEqual(patch.title, "Oat milk")
        XCTAssertNil(patch.notes)
        XCTAssertNil(patch.aisle)
        XCTAssertNil(patch.completion)
        XCTAssertEqual(patch.updatedAt, later)
    }

    func testACheckOffChangesOnlyTheCompletion() throws {
        var edited = base
        edited.isCompleted = true
        edited.completedBy = "u"

        let patch = try XCTUnwrap(ItemPatch.changes(from: base, to: edited, at: later))

        XCTAssertEqual(patch.completion, ItemPatch.Completion(isCompleted: true, completedBy: "u"))
        XCTAssertNil(patch.title)
        XCTAssertNil(patch.notes)
        XCTAssertNil(patch.aisle)
    }

    func testNothingChangedIsNoPatch() {
        var edited = base
        edited.updatedAt = later // not something the user edits

        XCTAssertNil(ItemPatch.changes(from: base, to: edited, at: later))
    }

    func testApplyingSetsOnlyThePatchedFields() {
        var someoneElses = base
        someoneElses.isCompleted = true
        someoneElses.completedBy = "bob"

        let renamed = ItemPatch(title: "Oat milk", updatedAt: later).applied(to: someoneElses)

        XCTAssertEqual(renamed.title, "Oat milk")
        XCTAssertEqual(renamed.notes, "2%")
        XCTAssertEqual(renamed.aisle, "Dairy")
        XCTAssertTrue(renamed.isCompleted)
        XCTAssertEqual(renamed.completedBy, "bob")
        XCTAssertEqual(renamed.updatedAt, later)
        XCTAssertEqual(renamed.createdAt, base.createdAt)
    }

    func testUncheckingClearsWhoCheckedItOff() {
        var done = base
        done.isCompleted = true
        done.completedBy = "bob"

        let unchecked = ItemPatch(completion: .init(isCompleted: false, completedBy: nil), updatedAt: later).applied(to: done)

        XCTAssertFalse(unchecked.isCompleted)
        XCTAssertNil(unchecked.completedBy)
    }

    // MARK: - Firestore fields

    func testATitlePatchWritesOnlyTheTitleAndTime() {
        let fields = FirestoreShoppingListService.firestoreFields(for: ItemPatch(title: "Oat milk", updatedAt: later))

        XCTAssertEqual(Set(fields.keys), ["title", "updatedAt"])
        XCTAssertEqual(fields["title"] as? String, "Oat milk")
        XCTAssertEqual((fields["updatedAt"] as? Timestamp)?.dateValue(), later)
    }

    func testACheckOffWritesWhoDidIt() {
        let patch = ItemPatch(completion: .init(isCompleted: true, completedBy: "u"), updatedAt: later)

        let fields = FirestoreShoppingListService.firestoreFields(for: patch)

        XCTAssertEqual(Set(fields.keys), ["isCompleted", "completedBy", "updatedAt"])
        XCTAssertEqual(fields["isCompleted"] as? Bool, true)
        XCTAssertEqual(fields["completedBy"] as? String, "u")
    }

    func testAnUncheckDeletesWhoCheckedItOff() {
        let patch = ItemPatch(completion: .init(isCompleted: false, completedBy: nil), updatedAt: later)

        let fields = FirestoreShoppingListService.firestoreFields(for: patch)

        XCTAssertEqual(fields["isCompleted"] as? Bool, false)
        XCTAssertTrue(fields["completedBy"] is FieldValue)
    }
}
