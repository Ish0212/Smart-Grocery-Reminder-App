package com.smartgrocery.reminder.receipt

import com.smartgrocery.reminder.model.GroceryItem
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.math.BigDecimal

class ReceiptMatcherTest {

    private fun purchase(name: String) = ReceiptItem(name, BigDecimal("1.00"), 1)

    @Test
    fun extraReceiptWordsStillMatchTheListItem() {
        val milk = GroceryItem(id = "milk", title = "Milk")

        assertEquals(milk, ReceiptMatcher.match(purchase("Milk 2% Gallon"), listOf(milk)))
    }

    @Test
    fun pluralsMatchTheSingularListItem() {
        val bananas = GroceryItem(id = "bananas", title = "Bananas")

        assertEquals(bananas, ReceiptMatcher.match(purchase("Organic Bananas"), listOf(bananas)))
    }

    @Test
    fun theCloserNameWins() {
        val milk = GroceryItem(id = "milk", title = "Milk")
        val chocolateMilk = GroceryItem(id = "choc", title = "Chocolate milk")

        assertEquals(milk, ReceiptMatcher.match(purchase("Milk"), listOf(chocolateMilk, milk)))
    }

    @Test
    fun unrelatedNamesDoNotMatch() {
        assertNull(ReceiptMatcher.match(purchase("Cheese"), listOf(GroceryItem(id = "milk", title = "Milk"))))
    }
}
