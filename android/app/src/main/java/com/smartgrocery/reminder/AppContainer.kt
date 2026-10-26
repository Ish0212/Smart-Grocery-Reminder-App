package com.smartgrocery.reminder

import android.content.Context
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.smartgrocery.reminder.data.AuthService
import com.smartgrocery.reminder.data.FirebaseAuthService
import com.smartgrocery.reminder.data.FirestoreListSharing
import com.smartgrocery.reminder.data.FirestoreShoppingListRepository
import com.smartgrocery.reminder.data.ListSharing
import com.smartgrocery.reminder.data.MockAuthService
import com.smartgrocery.reminder.data.MockListSharing
import com.smartgrocery.reminder.data.MockShoppingListRepository
import com.smartgrocery.reminder.data.ShoppingListRepository
import com.smartgrocery.reminder.reminders.ReminderStore

/** Picks the Firebase or the in-memory backend once, for the whole app. */
class AppContainer(val useFirebase: Boolean, context: Context) {
    val appContext: Context = context.applicationContext

    val auth: AuthService =
        if (useFirebase) FirebaseAuthService(FirebaseAuth.getInstance()) else MockAuthService()

    val reminders = ReminderStore(appContext)

    private val firestore by lazy { FirebaseFirestore.getInstance() }

    val sharing: ListSharing = if (useFirebase) FirestoreListSharing(firestore) else MockListSharing()

    private val demoLists = MockShoppingListRepository()

    /** The items of one list. A list's ID is its owner's uid, or the owner's uid for a shared list. */
    fun listsFor(listId: String): ShoppingListRepository =
        if (useFirebase) FirestoreShoppingListRepository(firestore, listId) else demoLists
}
