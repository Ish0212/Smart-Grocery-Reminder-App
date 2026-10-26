package com.smartgrocery.reminder.data

import com.google.firebase.Timestamp
import com.google.firebase.firestore.CollectionReference
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.MetadataChanges
import com.smartgrocery.reminder.model.GroceryItem
import com.smartgrocery.reminder.model.ItemPatch
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await
import java.util.Date

/**
 * The shared list at lists/{uid}/items. Items follow the rules in firestore.rules: every write sends
 * the fields the rules check, and clearing completedBy deletes the field rather than blanking it.
 */
class FirestoreShoppingListRepository(
    firestore: FirebaseFirestore,
    private val listId: String,
) : ShoppingListRepository {

    private val items: CollectionReference = firestore.collection("lists").document(listId).collection("items")

    override fun observe(): Flow<ListSnapshot> = callbackFlow {
        val registration = items.addSnapshotListener(MetadataChanges.INCLUDE) { snapshot, error ->
            if (error != null) {
                close(error)
                return@addSnapshotListener
            }
            if (snapshot != null) {
                val list = snapshot.documents
                    .mapNotNull { it.toGroceryItem() }
                    .sortedBy { it.createdAt }
                trySend(ListSnapshot(list, savedOnDevice = snapshot.metadata.hasPendingWrites()))
            }
        }
        awaitClose { registration.remove() }
    }

    override suspend fun add(draft: ItemDraft) {
        val document = items.document()
        val now = Timestamp(Date())
        val fields = mutableMapOf<String, Any>(
            "id" to document.id,
            "title" to draft.title,
            "aisle" to draft.aisle,
            "notes" to draft.notes,
            "isCompleted" to (draft.completedBy != null),
            "createdAt" to now,
            "updatedAt" to now,
        )
        draft.completedBy?.let { fields["completedBy"] = it }
        document.set(fields).await()
    }

    override suspend fun update(id: String, patch: ItemPatch) {
        val fields = patch.fields(updatedAt = System.currentTimeMillis()).mapValues { (key, value) ->
            when {
                value == null -> FieldValue.delete()
                key == "updatedAt" -> Timestamp(Date(value as Long))
                else -> value
            }
        }
        items.document(id).update(fields).await()
    }

    override suspend fun delete(id: String) {
        items.document(id).delete().await()
    }

    override suspend fun deleteAll() {
        // Firestore batches hold at most 500 writes.
        items.get().await().documents.chunked(400).forEach { chunk ->
            val batch = items.firestore.batch()
            chunk.forEach { batch.delete(it.reference) }
            batch.commit().await()
        }
    }

    private fun DocumentSnapshot.toGroceryItem(): GroceryItem? {
        val title = getString("title") ?: return null
        return GroceryItem(
            id = id,
            title = title,
            aisle = getString("aisle").orEmpty(),
            notes = getString("notes").orEmpty(),
            isCompleted = getBoolean("isCompleted") ?: false,
            completedBy = getString("completedBy"),
            createdAt = getTimestamp("createdAt")?.toDate()?.time ?: 0L,
            updatedAt = getTimestamp("updatedAt")?.toDate()?.time ?: 0L,
        )
    }
}
