package com.smartgrocery.reminder.receipt

import java.math.BigDecimal

/** A purchase read from a receipt. */
data class ReceiptItem(
    val name: String,
    val price: BigDecimal?,
    val quantity: Int,
)

/**
 * Turns receipt lines into purchases. Receipts differ by store, so this works on the patterns most
 * share: an item line ends in a price (maybe followed by tax-flag letters), totals and payment
 * lines name themselves, and a quantity or weight line refines the item just above it.
 */
object ReceiptParser {

    fun parse(lines: List<String>): List<ReceiptItem> {
        val items = mutableListOf<ReceiptItem>()
        // A line with a name but no price: the next line may be its quantity or weight with the price.
        var pendingName: String? = null

        for (raw in lines) {
            val line = raw.split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
            if (line.isEmpty() || hasSkipWord(line)) {
                pendingName = null
                continue
            }

            val count = quantity(line) ?: if (isWeight(line)) 1 else null
            if (count != null) {
                val found = price(line)
                val name = pendingName
                // Only with a price: a department header ("PRODUCE") above a weight line isn't an item.
                if (name != null && found != null && !found.negative) {
                    add(ReceiptItem(name, found.value, count), items)
                } else if (quantity(line) != null && items.isNotEmpty()) {
                    items[items.lastIndex] = items.last().copy(quantity = count)
                }
                pendingName = null
                continue
            }

            val found = price(line)
            if (found == null) {
                pendingName = cleanName(line)?.name
                continue
            }
            val previousName = pendingName
            pendingName = null
            if (found.negative) continue

            val cleaned = cleanName(found.namePart)
            if (cleaned != null) {
                add(ReceiptItem(cleaned.name, found.value, cleaned.quantity), items)
            } else if (found.namePart.isEmpty() && previousName != null) {
                // The name on one line and its price alone on the next.
                add(ReceiptItem(previousName, found.value, 1), items)
            }
        }
        return items
    }

    /** The same product on two lines is one purchase with both quantities. */
    private fun add(item: ReceiptItem, items: MutableList<ReceiptItem>) {
        val index = items.indexOfFirst { it.name == item.name }
        if (index >= 0) {
            items[index] = items[index].copy(quantity = items[index].quantity + item.quantity)
        } else {
            items.add(item)
        }
    }

    // Summary, payment and fee lines start or end with one of these ("TOTAL 31.03", "VISA ****
    // 1234", "BAG FEE 0.10", "YOU SAVED 1.50"). Only the first and last words are checked, so a
    // product that merely contains one ("GREETING CARD", "CASHEW MIX") is kept.
    private val leadingSkipWords = setOf(
        "total", "subtotal", "tax", "balance", "change", "cash", "visa", "mastercard", "amex",
        "debit", "credit", "card", "tender", "due", "payment", "savings", "discount", "coupon",
        "points", "auth", "approved", "thank", "receipt", "you", "ebt", "crv", "deposit", "refund",
    )
    private val trailingSkipWords = setOf(
        "total", "subtotal", "tax", "due", "change", "savings", "saved", "discount", "coupon",
        "deposit", "fee", "refund", "crv",
    )

    private fun hasSkipWord(line: String): Boolean {
        val words = line.lowercase().split(Regex("[^\\p{L}]+")).filter { it.isNotEmpty() }
        val first = words.firstOrNull() ?: return false
        val last = words.last()
        return first in leadingSkipWords || last in trailingSkipWords
    }

    // `name  [-]$1,29[-] [F]` at the end of the line. A minus on either side marks a discount.
    private val pricePattern = Regex("""^(.*?)\s*(-?)\$?(\d{1,4}[.,]\d{2})(-?)(?:\s+[A-Z*]{1,2})?$""")

    private class Found(val namePart: String, val value: BigDecimal?, val negative: Boolean)

    private fun price(line: String): Found? {
        val match = pricePattern.find(line) ?: return null
        val negative = match.groupValues[2].isNotEmpty() || match.groupValues[4].isNotEmpty()
        val value = match.groupValues[3].replace(',', '.').toBigDecimalOrNull()
        return Found(match.groupValues[1], value, negative)
    }

    // `2 @ 1.99`, `2 x 1.99`, `3 EA`: how many of the item there were.
    private val quantityPattern = Regex("""^(\d{1,3})\s*(?:@|[xX](?=\s*\d)|EA\b)""")

    private fun quantity(line: String): Int? =
        quantityPattern.find(line)?.groupValues?.get(1)?.toIntOrNull()

    // `1.52 lb @ 1.99/lb`: a weighed item's detail line.
    private val weightPattern = Regex("""^\d+[.,]\d+\s*(?:lbs?|kg|oz)\b""", RegexOption.IGNORE_CASE)

    private fun isWeight(line: String): Boolean = weightPattern.containsMatchIn(line)

    private val abbreviations = mapOf(
        "ORG" to "Organic", "BNLS" to "Boneless", "SKNLS" to "Skinless", "GAL" to "Gallon",
        "CHKN" to "Chicken", "BRST" to "Breast", "WHL" to "Whole", "GRN" to "Green", "LG" to "Large",
        "SM" to "Small", "PK" to "Pack",
    )

    private val sizeCode = Regex("""\d+(?:[.,]\d+)?(?:OZ|LB|LBS|CT|G|KG|ML|L|PK)""", RegexOption.IGNORE_CASE)

    data class CleanedName(val name: String, val quantity: Int)

    /**
     * The readable name and a leading quantity (`2 AVOCADOS`): SKU numbers and trailing size codes
     * dropped, abbreviations spelled out, title case. Null without at least two letters.
     */
    fun cleanName(raw: String): CleanedName? {
        val tokens = raw.split(' ').filter { it.isNotEmpty() }.toMutableList()
        var quantity = 1
        val first = tokens.firstOrNull()
        if (first != null && first.length <= 2 && (first.toIntOrNull() ?: 0) > 0 &&
            tokens.size > 1 && tokens[1].any { it.isLetter() }
        ) {
            quantity = first.toInt()
            tokens.removeAt(0)
        }
        // SKU / PLU codes anywhere.
        tokens.removeAll { it.length >= 4 && it.all { character -> character.isDigit() } }
        while (tokens.isNotEmpty() && sizeCode.matches(tokens.last())) {
            tokens.removeAt(tokens.lastIndex)
        }
        val words = tokens.map { token ->
            abbreviations[token.uppercase()] ?: if (token.all { it.isLetter() || it == '\'' || it == '-' }) {
                token.take(1).uppercase() + token.drop(1).lowercase()
            } else {
                token.lowercase()
            }
        }
        val name = words.joinToString(" ")
        if (name.count { it.isLetter() } < 2) return null
        return CleanedName(name.take(500), quantity)
    }
}
