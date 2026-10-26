package com.smartgrocery.reminder.receipt

import com.smartgrocery.reminder.model.GroceryItem

sealed interface ReceiptChange {
    /** An open list item that the receipt bought: check it off. */
    data class CheckOff(val itemId: String) : ReceiptChange

    /** A purchase with no open list item: add it already checked off. */
    data class AddBought(val title: String, val quantity: Int) : ReceiptChange
}

object ReceiptApplier {
    /**
     * What applying a receipt does. Open list items are matched first. A purchase that matches an
     * item already bought (a second scan of the same receipt) is skipped, so it isn't counted twice.
     */
    fun plan(purchases: List<ReceiptItem>, list: List<GroceryItem>): List<ReceiptChange> {
        val open = list.filterNot { it.isCompleted }.toMutableList()
        val bought = list.filter { it.isCompleted }
        val changes = mutableListOf<ReceiptChange>()
        for (purchase in purchases) {
            val match = ReceiptMatcher.match(purchase, open)
            if (match != null) {
                changes.add(ReceiptChange.CheckOff(match.id))
                open.removeAll { it.id == match.id }
                continue
            }
            if (bought.any { ReceiptMatcher.isClose(purchase, it) }) continue
            changes.add(ReceiptChange.AddBought(purchase.name, purchase.quantity))
        }
        return changes
    }
}
