package com.smartgrocery.reminder.reminders

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.smartgrocery.reminder.SmartGroceryApplication

/** Registers the geofences again after a reboot, so the reminders work before the app is opened. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        (context.applicationContext as SmartGroceryApplication).container.reminders.reapplyGeofences()
    }
}
