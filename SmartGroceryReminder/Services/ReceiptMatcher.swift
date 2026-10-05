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

    /// The best match among `open`: the most shared words, the earlier item on a tie.
    static func match(_ item: ReceiptItem, in open: [GroceryItem]) -> GroceryItem? {
        let receiptWords = words(item.name)
        guard !receiptWords.isEmpty else { return nil }
        var best: (item: GroceryItem, score: Int)?
        for candidate in open {
            let listWords = words(candidate.title)
            guard !listWords.isEmpty,
                  listWords.isSubset(of: receiptWords) || receiptWords.isSubset(of: listWords) else { continue }
            let score = listWords.intersection(receiptWords).count
            if score > (best?.score ?? 0) {
                best = (candidate, score)
            }
        }
        return best?.item
    }
}
