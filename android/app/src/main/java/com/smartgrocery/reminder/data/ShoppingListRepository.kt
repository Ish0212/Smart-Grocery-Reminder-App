package com.smartgrocery.reminder.data

import com.smartgrocery.reminder.model.GroceryItem
import com.smartgrocery.reminder.model.ItemPatch
import kotlinx.coroutines.flow.Flow

data class ItemDraft(
    val title: String,
    val aisle: String = "",
    val notes: String = "",
    /** Set to add the item already checked off by this user (a receipt purchase). */
    val completedBy: String? = null,
)

data class ListSnapshot(
    val items: List<GroceryItem>,
    /** True while changes are only on this device, waiting for the server. */
    val savedOnDevice: Boolean,
) {
    companion object {
        val Empty = ListSnapshot(items = emptyList(), savedOnDevice = false)
    }
}

interface ShoppingListRepository {
    /** Emits the list now, and again each time it changes. */
    fun observe(): Flow<ListSnapshot>

    suspend fun add(draft: ItemDraft)
    suspend fun update(id: String, patch: ItemPatch)
    suspend fun delete(id: String)

    /** Removes every item. Used when the account is deleted. */
    suspend fun deleteAll()
}
