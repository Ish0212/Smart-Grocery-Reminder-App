package com.smartgrocery.reminder.data

import com.smartgrocery.reminder.model.GroceryItem
import com.smartgrocery.reminder.model.SampleData
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/** In-memory list for the demo account. Firestore replaces it in phase 2. */
class MockShoppingListRepository(initial: List<GroceryItem> = SampleData.groceryItems) {
    private val _items = MutableStateFlow(initial)
    val items: StateFlow<List<GroceryItem>> = _items.asStateFlow()

    fun toggle(id: String) {
        _items.update { list ->
            list.map { if (it.id == id) it.copy(isCompleted = !it.isCompleted) else it }
        }
    }
}
