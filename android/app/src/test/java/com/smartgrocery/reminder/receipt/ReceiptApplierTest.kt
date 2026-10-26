package com.smartgrocery.reminder.receipt

import com.smartgrocery.reminder.model.GroceryItem
import org.junit.Assert.assertEquals
import org.junit.Test
import java.math.BigDecimal

class ReceiptApplierTest {

    private val list = listOf(
        GroceryItem(id = "milk", title = "Milk"),
        GroceryItem(id = "eggs", title = "Eggs", isCompleted = true, completedBy = "me"),
    )

    @Test
    fun openItemsAreCheckedOffAndUnknownPurchasesAreAddedBought() {
        val purchases = listOf(
            ReceiptItem("Milk 2% Gallon", BigDecimal("3.49"), 1),
            ReceiptItem("Cheese", BigDecimal("4.00"), 1),
        )

        assertEquals(
            listOf(
                ReceiptChange.CheckOff("milk"),
                ReceiptChange.AddBought("Cheese", 1),
            ),
            ReceiptApplier.plan(purchases, list),
        )
    }

    @Test
    fun aSecondScanDoesNotCountAnAlreadyBoughtItemAgain() {
        val purchases = listOf(ReceiptItem("Eggs", BigDecimal("3.99"), 1))

        assertEquals(emptyList<ReceiptChange>(), ReceiptApplier.plan(purchases, list))
    }
}
