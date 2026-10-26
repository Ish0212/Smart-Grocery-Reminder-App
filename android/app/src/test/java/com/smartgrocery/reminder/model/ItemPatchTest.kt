package com.smartgrocery.reminder.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ItemPatchTest {

    private val milk = GroceryItem(id = "milk", title = "Milk", aisle = "Dairy")

    @Test
    fun fieldsHoldOnlyTheChangedKeysAndUpdatedAt() {
        val patch = ItemPatch(isCompleted = true, completedBy = "u1")

        assertEquals(
            mapOf("isCompleted" to true, "completedBy" to "u1", "updatedAt" to 5L),
            patch.fields(updatedAt = 5L),
        )
    }

    @Test
    fun clearingCompletedByWritesANullMeaningDelete() {
        val fields = ItemPatch(isCompleted = false, clearCompletedBy = true).fields(updatedAt = 5L)

        assertEquals(true, fields.containsKey("completedBy"))
        assertNull(fields["completedBy"])
    }

    @Test
    fun togglingAnOpenItemRecordsWhoCheckedItOff() {
        assertEquals(ItemPatch(isCompleted = true, completedBy = "u1"), ItemPatch.toggle(milk, "u1"))
    }

    @Test
    fun togglingACompletedItemClearsWhoCheckedItOff() {
        val done = milk.copy(isCompleted = true, completedBy = "u1")

        assertEquals(ItemPatch(isCompleted = false, clearCompletedBy = true), ItemPatch.toggle(done, "u2"))
    }

    @Test
    fun applyingAPatchKeepsTheFieldsItDoesNotName() {
        val renamed = milk.applying(ItemPatch(title = "Oat milk"), updatedAt = 9L)

        assertEquals("Oat milk", renamed.title)
        assertEquals("Dairy", renamed.aisle)
        assertEquals(9L, renamed.updatedAt)
    }
}
