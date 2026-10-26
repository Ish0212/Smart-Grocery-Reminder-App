package com.smartgrocery.reminder.reminders

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import com.smartgrocery.reminder.SmartGroceryApplication

/** Gets geofence enters from Play services, even when the app is closed. */
class GeofenceReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val event = GeofencingEvent.fromIntent(intent) ?: return
        if (event.hasError() || event.geofenceTransition != Geofence.GEOFENCE_TRANSITION_ENTER) return
        val placeId = event.triggeringGeofences?.firstOrNull()?.requestId ?: return

        val reminders = (context.applicationContext as SmartGroceryApplication).container.reminders
        val place = reminders.places.value.firstOrNull { it.id == placeId } ?: return
        val now = System.currentTimeMillis()

        val action = ReminderPolicy.decide(place.kind, now, reminders.lastFiredAt(placeId), reminders.openItemCount())
        reminders.diagnostics.log("Entered ${place.name}: $action")
        when (action) {
            ReminderAction.Ignore -> return
            is ReminderAction.StoreReminder -> Notifications.storeReminder(context, place.name, action.openItems)
            ReminderAction.StartUnloadTimer -> reminders.startUnloadTimer(now)
        }
        reminders.markFired(placeId, now)
    }
}
