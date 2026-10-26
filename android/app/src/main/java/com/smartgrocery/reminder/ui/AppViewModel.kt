package com.smartgrocery.reminder.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import com.smartgrocery.reminder.AppContainer
import com.smartgrocery.reminder.data.AuthUser
import com.smartgrocery.reminder.data.ItemDraft
import com.smartgrocery.reminder.data.ListSnapshot
import com.smartgrocery.reminder.data.ShoppingListRepository
import com.smartgrocery.reminder.model.GroceryItem
import com.smartgrocery.reminder.model.ItemPatch
import com.smartgrocery.reminder.receipt.ReceiptApplier
import com.smartgrocery.reminder.receipt.ReceiptChange
import com.smartgrocery.reminder.receipt.ReceiptItem
import com.smartgrocery.reminder.reminders.ReminderStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class AppViewModel(private val container: AppContainer) : ViewModel() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    val usesFirebase: Boolean get() = container.useFirebase

    val user: StateFlow<AuthUser?> = container.auth.user
        .stateIn(scope, SharingStarted.Eagerly, container.auth.currentUser)

    private val lists: StateFlow<ShoppingListRepository?> = user
        .map { it?.let { signedIn -> container.listsFor(signedIn.uid) } }
        .stateIn(scope, SharingStarted.Eagerly, user.value?.let { container.listsFor(it.uid) })

    val list: StateFlow<ListSnapshot> = lists
        .flatMapLatest { repository -> repository?.observe() ?: flowOf(ListSnapshot.Empty) }
        .stateIn(scope, SharingStarted.Eagerly, ListSnapshot.Empty)

    val reminders: ReminderStore get() = container.reminders

    init {
        // The receivers read the open count to say how many items are left at a store.
        scope.launch {
            list.collect { snapshot -> reminders.setOpenItemCount(snapshot.items.count { !it.isCompleted }) }
        }
    }

    private val _authError = MutableStateFlow<String?>(null)
    val authError: StateFlow<String?> = _authError.asStateFlow()

    private val _listError = MutableStateFlow<String?>(null)
    val listError: StateFlow<String?> = _listError.asStateFlow()

    fun signIn(email: String, password: String) = authAction {
        container.auth.signIn(email, password)
    }

    fun signUp(email: String, password: String, displayName: String) = authAction {
        container.auth.signUp(email, password, displayName)
    }

    fun sendPasswordReset(email: String, onSent: () -> Unit) = authAction {
        container.auth.sendPasswordReset(email)
        onSent()
    }

    fun signOut() {
        scope.launch { container.auth.signOut() }
    }

    /** Removes the list first, then the account. The user is signed out when the account goes. */
    fun deleteAccount() = authAction {
        lists.value?.deleteAll()
        container.auth.deleteAccount()
    }

    fun addItem(draft: ItemDraft) = listAction {
        lists.value?.add(draft)
    }

    fun saveEdit(id: String, draft: ItemDraft) = listAction {
        lists.value?.update(id, ItemPatch(title = draft.title, aisle = draft.aisle, notes = draft.notes))
    }

    fun toggle(item: GroceryItem) = listAction {
        val uid = user.value?.uid ?: return@listAction
        lists.value?.update(item.id, ItemPatch.toggle(item, uid))
    }

    fun delete(id: String) = listAction {
        lists.value?.delete(id)
    }

    /** Checks off the open items the receipt bought and adds the rest as already bought. */
    fun applyReceipt(purchases: List<ReceiptItem>) = listAction {
        val uid = user.value?.uid ?: return@listAction
        val repository = lists.value ?: return@listAction
        val items = list.value.items
        for (change in ReceiptApplier.plan(purchases, items)) {
            when (change) {
                is ReceiptChange.CheckOff -> {
                    val item = items.first { it.id == change.itemId }
                    repository.update(item.id, ItemPatch.toggle(item, uid))
                }
                is ReceiptChange.AddBought -> repository.add(
                    ItemDraft(
                        title = change.title,
                        notes = if (change.quantity > 1) "x${change.quantity}" else "",
                        completedBy = uid,
                    ),
                )
            }
        }
    }

    private fun authAction(block: suspend () -> Unit) {
        _authError.value = null
        scope.launch {
            try {
                block()
            } catch (error: Exception) {
                _authError.value = error.message ?: "Something went wrong. Try again."
            }
        }
    }

    private fun listAction(block: suspend () -> Unit) {
        _listError.value = null
        scope.launch {
            try {
                block()
            } catch (error: Exception) {
                _listError.value = error.message ?: "Couldn't save that change. Try again."
            }
        }
    }

    override fun onCleared() {
        scope.cancel()
    }

    class Factory(private val container: AppContainer) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T = AppViewModel(container) as T
    }
}
