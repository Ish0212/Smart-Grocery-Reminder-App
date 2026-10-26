package com.smartgrocery.reminder.ui

import androidx.lifecycle.ViewModel
import com.smartgrocery.reminder.data.MockShoppingListRepository

class GroceryViewModel(
    private val repository: MockShoppingListRepository = MockShoppingListRepository(),
) : ViewModel() {
    val items = repository.items

    fun toggle(id: String) = repository.toggle(id)
}
