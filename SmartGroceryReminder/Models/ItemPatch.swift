import Foundation

/// The fields one edit changes. Sending only these (not the whole item) means edits that family
/// members made offline to different fields all survive; two edits to the same field leave the
/// one that reaches the server last.
struct ItemPatch: Equatable {
    /// Whether it's checked off and by whom, which always change together.
    struct Completion: Equatable {
        var isCompleted: Bool
        var completedBy: String?
    }

    var title: String?
    var notes: String?
    var aisle: String?
    var completion: Completion?
    var updatedAt: Date

    init(title: String? = nil, notes: String? = nil, aisle: String? = nil, completion: Completion? = nil, updatedAt: Date) {
        self.title = title
        self.notes = notes
        self.aisle = aisle
        self.completion = completion
        self.updatedAt = updatedAt
    }

    var isEmpty: Bool {
        title == nil && notes == nil && aisle == nil && completion == nil
    }

    /// What changed between `base` (the item as the editor saw it) and `edited`; `nil` when nothing
    /// a person can edit did.
    static func changes(from base: GroceryItem, to edited: GroceryItem, at date: Date) -> ItemPatch? {
        var patch = ItemPatch(updatedAt: date)
        if edited.title != base.title { patch.title = edited.title }
        if edited.notes != base.notes { patch.notes = edited.notes }
        if edited.aisle != base.aisle { patch.aisle = edited.aisle }
        if edited.isCompleted != base.isCompleted || edited.completedBy != base.completedBy {
            patch.completion = Completion(isCompleted: edited.isCompleted, completedBy: edited.completedBy)
        }
        return patch.isEmpty ? nil : patch
    }

    /// `item` with the patched fields changed and every other field left as it is.
    func applied(to item: GroceryItem) -> GroceryItem {
        var result = item
        if let title { result.title = title }
        if let notes { result.notes = notes }
        if let aisle { result.aisle = aisle }
        if let completion {
            result.isCompleted = completion.isCompleted
            result.completedBy = completion.completedBy
        }
        result.updatedAt = updatedAt
        return result
    }
}
