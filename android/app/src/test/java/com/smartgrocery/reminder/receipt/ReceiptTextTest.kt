package com.smartgrocery.reminder.receipt

import org.junit.Assert.assertEquals
import org.junit.Test

class ReceiptTextTest {

    private fun fragment(text: String, top: Float, left: Float) =
        TextFragment(text, top = top, bottom = top + 10f, left = left)

    @Test
    fun piecesAtTheSameHeightBecomeOneLineReadLeftToRight() {
        val lines = ReceiptText.lines(
            listOf(
                fragment("3.49", top = 101f, left = 200f),
                fragment("Milk", top = 100f, left = 0f),
                fragment("Eggs", top = 140f, left = 0f),
            ),
        )

        assertEquals(listOf("Milk 3.49", "Eggs"), lines)
    }

    @Test
    fun blankFragmentsAreIgnored() {
        assertEquals(emptyList<String>(), ReceiptText.lines(listOf(fragment("  ", top = 0f, left = 0f))))
    }
}
