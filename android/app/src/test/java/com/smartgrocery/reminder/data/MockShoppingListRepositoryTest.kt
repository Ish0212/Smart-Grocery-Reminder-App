package com.smartgrocery.reminder.data

import com.smartgrocery.reminder.model.ItemPatch
import com.smartgrocery.reminder.model.SampleData
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MockShoppingListRepositoryTest {

    @Test
    fun startsWithTheSampleList() = runBlocking {
        val repository = MockShoppingListRepository()

        assertEquals(SampleData.groceryItems, repository.observe().first().items)
    }

    @Test
    fun updateChangesOnlyTheFieldsInThePatch() = runBlocking {
        val repository = MockShoppingListRepository()

        repository.update("milk", ItemPatch(title = "Oat milk"))

        val milk = repository.observe().first().items.single { it.id == "milk" }
        assertEquals("Oat milk", milk.title)
        assertEquals("Dairy", milk.aisle)
    }

    @Test
    fun togglingThroughAPatchRecordsWhoCheckedTheItemOff() = runBlocking {
        val repository = MockShoppingListRepository()
        val milk = SampleData.groceryItems.first { it.id == "milk" }

        repository.update("milk", ItemPatch.toggle(milk, uid = "u1"))

        val checked = repository.observe().first().items.single { it.id == "milk" }
        assertTrue(checked.isCompleted)
        assertEquals("u1", checked.completedBy)
    }

    @Test
    fun addAppendsAnItemAndDeleteRemovesIt() = runBlocking {
        val repository = MockShoppingListRepository()

        repository.add(ItemDraft(title = "Lemons", aisle = "Produce"))
        val added = repository.observe().first().items.last()
        assertEquals("Lemons", added.title)

        repository.delete(added.id)
        assertEquals(SampleData.groceryItems, repository.observe().first().items)
    }
}
