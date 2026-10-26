package com.smartgrocery.reminder.model

/**
 * A change to one item. Only the fields that are set are sent, so two people editing different
 * fields of the same item offline both keep their change (the Firestore update merges field by field).
 */
data class ItemPatch(
    val title: String? = null,
    val aisle: String? = null,
    val notes: String? = null,
    val isCompleted: Boolean? = null,
    val completedBy: String? = null,
    /** Removes completedBy. Used when an item is unchecked. */
    val clearCompletedBy: Boolean = false,
) {
    /**
     * The fields to write. A null value means "delete this field". updatedAt is always included.
     */
    fun fields(updatedAt: Long): Map<String, Any?> = buildMap {
        title?.let { put("title", it) }
        aisle?.let { put("aisle", it) }
        notes?.let { put("notes", it) }
        isCompleted?.let { put("isCompleted", it) }
        completedBy?.let { put("completedBy", it) }
        if (clearCompletedBy) put("completedBy", null)
        put("updatedAt", updatedAt)
    }

    companion object {
        /** Checking an item off records who did it; unchecking clears that. */
        fun toggle(item: GroceryItem, uid: String): ItemPatch =
            if (item.isCompleted) {
                ItemPatch(isCompleted = false, clearCompletedBy = true)
            } else {
                ItemPatch(isCompleted = true, completedBy = uid)
            }
    }
}

fun GroceryItem.applying(patch: ItemPatch, updatedAt: Long): GroceryItem = copy(
    title = patch.title ?: title,
    aisle = patch.aisle ?: aisle,
    notes = patch.notes ?: notes,
    isCompleted = patch.isCompleted ?: isCompleted,
    completedBy = if (patch.clearCompletedBy) null else patch.completedBy ?: completedBy,
    updatedAt = updatedAt,
)
