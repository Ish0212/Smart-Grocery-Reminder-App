package com.smartgrocery.reminder.data

import com.smartgrocery.reminder.model.GroceryItem
import com.smartgrocery.reminder.model.SampleData
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MockShoppingListRepositoryTest {

    @Test
    fun startsWithTheSampleList() {
        val repository = MockShoppingListRepository()

        assertEquals(SampleData.groceryItems, repository.items.value)
    }

    @Test
    fun togglingFlipsOnlyThatItem() {
        val repository = MockShoppingListRepository()

        repository.toggle("milk")

        val milk = repository.items.value.single { it.id == "milk" }
        assertTrue(milk.isCompleted)
        assertEquals(
            SampleData.groceryItems.filter { it.id != "milk" },
            repository.items.value.filter { it.id != "milk" },
        )
    }

    @Test
    fun togglingTwiceRestoresTheItem() {
        val repository = MockShoppingListRepository()

        repository.toggle("eggs")
        repository.toggle("eggs")

        assertEquals(SampleData.groceryItems, repository.items.value)
    }

    @Test
    fun togglingAnUnknownIdChangesNothing() {
        val initial = listOf(GroceryItem(id = "a", title = "A"))
        val repository = MockShoppingListRepository(initial)

        repository.toggle("missing")

        assertEquals(initial, repository.items.value)
    }
}
