package com.smartgrocery.reminder.receipt

import com.smartgrocery.reminder.model.GroceryItem

/**
 * Which open list item a receipt line is. Receipt names carry extra words ("Organic Bananas",
 * "Milk 2% Gallon"), so a list item matches when all its significant words are in the receipt
 * name, or the other way round.
 */
object ReceiptMatcher {
    /** Words that describe a product rather than name it. */
    private val stopWords = setOf(
        "organic", "large", "small", "medium", "fresh", "pack", "gallon", "lb", "oz", "the", "and", "of",
    )

    /** Lowercase words, letters only, with a plural "s" dropped from longer words. */
    fun words(text: String): Set<String> =
        text.lowercase()
            .split(Regex("[^\\p{L}]+"))
            .filter { it.isNotEmpty() }
            .map { word -> if (word.length >= 4 && word.endsWith("s")) word.dropLast(1) else word }
            .filter { it.length >= 2 && it !in stopWords }
            .toSet()

    /**
     * The best match among [items]: the most shared words, then the fewest words that differ
     * ("Milk" over "Chocolate milk" for MILK), then the earlier item.
     */
    fun match(item: ReceiptItem, items: List<GroceryItem>): GroceryItem? {
        val receiptWords = words(item.name)
        if (receiptWords.isEmpty()) return null
        var best: GroceryItem? = null
        var bestShared = -1
        var bestDiffering = Int.MAX_VALUE
        for (candidate in items) {
            val listWords = words(candidate.title)
            if (listWords.isEmpty()) continue
            if (!(listWords.containsAll(receiptWords) || receiptWords.containsAll(listWords))) continue
            val shared = listWords.intersect(receiptWords).size
            val differing = (listWords union receiptWords).size - shared
            if (shared < bestShared || (shared == bestShared && differing >= bestDiffering)) continue
            best = candidate
            bestShared = shared
            bestDiffering = differing
        }
        return best
    }

    /**
     * Whether the names agree closely enough to treat the purchase as the same item: at most one
     * extra word on either side. "Large Brown Eggs" is Eggs; "Milk Choc Bar" only might be Milk.
     */
    fun isClose(item: ReceiptItem, listItem: GroceryItem): Boolean {
        val receiptWords = words(item.name)
        val listWords = words(listItem.title)
        return ((receiptWords union listWords) - (receiptWords intersect listWords)).size <= 1
    }
}
