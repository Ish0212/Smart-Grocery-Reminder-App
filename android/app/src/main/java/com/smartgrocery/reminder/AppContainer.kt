package com.smartgrocery.reminder

import android.content.Context
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.smartgrocery.reminder.data.AuthService
import com.smartgrocery.reminder.data.FirebaseAuthService
import com.smartgrocery.reminder.data.FirestoreShoppingListRepository
import com.smartgrocery.reminder.data.MockAuthService
import com.smartgrocery.reminder.data.MockShoppingListRepository
import com.smartgrocery.reminder.data.ShoppingListRepository
import com.smartgrocery.reminder.reminders.ReminderStore

/** Picks the Firebase or the in-memory backend once, for the whole app. */
class AppContainer(val useFirebase: Boolean, context: Context) {
    val auth: AuthService =
        if (useFirebase) FirebaseAuthService(FirebaseAuth.getInstance()) else MockAuthService()

    val reminders = ReminderStore(context.applicationContext)

    private val demoLists = MockShoppingListRepository()

    /** A list's ID is its owner's uid, so each signed-in user gets their own repository. */
    fun listsFor(uid: String): ShoppingListRepository =
        if (useFirebase) FirestoreShoppingListRepository(FirebaseFirestore.getInstance(), uid) else demoLists
}
