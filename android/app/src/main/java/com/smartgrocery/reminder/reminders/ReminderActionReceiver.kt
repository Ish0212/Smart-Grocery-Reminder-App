package com.smartgrocery.reminder.reminders

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.smartgrocery.reminder.SmartGroceryApplication

/** The "Brought in" and "Remind again" buttons on the unload notification. */
class ReminderActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val reminders = (context.applicationContext as SmartGroceryApplication).container.reminders
        when (intent.action) {
            ACTION_BROUGHT_IN -> reminders.cancelUnloadTimer()
            ACTION_REMIND_AGAIN -> reminders.remindAgain(System.currentTimeMillis())
        }
        Notifications.cancelUnload(context)
    }

    companion object {
        const val ACTION_BROUGHT_IN = "com.smartgrocery.reminder.BROUGHT_IN"
        const val ACTION_REMIND_AGAIN = "com.smartgrocery.reminder.REMIND_AGAIN"
    }
}
