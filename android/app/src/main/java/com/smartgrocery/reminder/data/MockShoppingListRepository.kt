package com.smartgrocery.reminder.data

import com.smartgrocery.reminder.model.GroceryItem
import com.smartgrocery.reminder.model.ItemPatch
import com.smartgrocery.reminder.model.SampleData
import com.smartgrocery.reminder.model.applying
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update
import java.util.UUID

/** In-memory list for builds without a Firebase project. Nothing is saved between launches. */
class MockShoppingListRepository(initial: List<GroceryItem> = SampleData.groceryItems) : ShoppingListRepository {
    private val items = MutableStateFlow(initial)

    override fun observe(): Flow<ListSnapshot> = items.map { ListSnapshot(it, savedOnDevice = false) }

    override suspend fun add(draft: ItemDraft) {
        val now = System.currentTimeMillis()
        val item = GroceryItem(
            id = UUID.randomUUID().toString(),
            title = draft.title,
            aisle = draft.aisle,
            notes = draft.notes,
            createdAt = now,
            updatedAt = now,
        )
        items.update { it + item }
    }

    override suspend fun update(id: String, patch: ItemPatch) {
        val now = System.currentTimeMillis()
        items.update { list -> list.map { if (it.id == id) it.applying(patch, now) else it } }
    }

    override suspend fun delete(id: String) {
        items.update { list -> list.filterNot { it.id == id } }
    }

    override suspend fun deleteAll() {
        items.value = emptyList()
    }
}
