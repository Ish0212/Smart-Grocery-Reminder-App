package com.smartgrocery.reminder.receipt

import kotlin.math.abs

/** One piece of text the recognizer found. Coordinates are pixels, with y growing downwards. */
data class TextFragment(
    val text: String,
    val top: Float,
    val bottom: Float,
    val left: Float,
) {
    val midY: Float get() = (top + bottom) / 2f
    val height: Float get() = bottom - top
}

object ReceiptText {
    /**
     * Receipt lines, top to bottom. The recognizer often reports an item's name and its price as
     * separate pieces; pieces at the same height (within half a typical text height) make one line,
     * read left to right.
     */
    fun lines(fragments: List<TextFragment>): List<String> {
        val kept = fragments.filter { it.text.isNotBlank() }
        if (kept.isEmpty()) return emptyList()
        val heights = kept.map { it.height }.sorted()
        val tolerance = heights[heights.size / 2] / 2f

        class Row(var midY: Float, val fragments: MutableList<TextFragment>)

        val rows = mutableListOf<Row>()
        for (fragment in kept.sortedBy { it.midY }) {
            val last = rows.lastOrNull()
            if (last != null && abs(last.midY - fragment.midY) <= tolerance) {
                last.fragments.add(fragment)
                last.midY += (fragment.midY - last.midY) / last.fragments.size
            } else {
                rows.add(Row(fragment.midY, mutableListOf(fragment)))
            }
        }
        return rows.map { row ->
            row.fragments.sortedBy { it.left }.joinToString(" ") { it.text.trim() }
        }
    }
}
