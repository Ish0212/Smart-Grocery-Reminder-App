import Foundation

/// Which open list item a receipt line is. Receipt names carry extra words ("Organic Bananas",
/// "Milk 2% Gallon"), so a list item matches when all its significant words are in the receipt
/// name, or the other way round.
enum ReceiptMatcher {
    /// Words that describe a product rather than name it.
    private static let stopWords: Set<String> = [
        "organic", "large", "small", "medium", "fresh", "pack", "gallon", "lb", "oz", "the", "and", "of",
    ]

    /// Lowercase words, letters only, with a plural "s" dropped from longer words.
    static func words(_ text: String) -> Set<String> {
        Set(text.lowercased()
            .split { !$0.isLetter }
            .map { word -> String in
                word.count >= 4 && word.hasSuffix("s") ? String(word.dropLast()) : String(word)
            }
            .filter { $0.count >= 2 && !stopWords.contains($0) })
    }

    /// The best match among `items`: the most shared words, then the fewest words that differ
    /// ("Milk" over "Chocolate milk" for MILK), then the earlier item.
    static func match(_ item: ReceiptItem, in items: [GroceryItem]) -> GroceryItem? {
        let receiptWords = words(item.name)
        guard !receiptWords.isEmpty else { return nil }
        var best: (item: GroceryItem, shared: Int, differing: Int)?
        for candidate in items {
            let listWords = words(candidate.title)
            guard !listWords.isEmpty,
                  listWords.isSubset(of: receiptWords) || receiptWords.isSubset(of: listWords) else { continue }
            let shared = listWords.intersection(receiptWords).count
            let differing = listWords.symmetricDifference(receiptWords).count
            if let current = best, shared < current.shared || (shared == current.shared && differing >= current.differing) {
                continue
            }
            best = (candidate, shared, differing)
        }
        return best?.item
    }

    /// Whether the names agree closely enough to check the item off without asking: at most one
    /// extra word on either side. "Large Brown Eggs" is Eggs; "Milk Choc Bar" only might be Milk.
    static func isClose(_ item: ReceiptItem, to listItem: GroceryItem) -> Bool {
        words(item.name).symmetricDifference(words(listItem.title)).count <= 1
    }
}
