package com.smartgrocery.reminder.reminders

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import androidx.glance.appwidget.updateAll
import com.smartgrocery.reminder.widget.GroceryWidget
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Saved places, the arrival countdown and the geofences that watch the places. Everything is kept on
 * the device in SharedPreferences, so it survives the app being killed. Broadcast receivers reach it
 * through the Application container.
 */
class ReminderStore(private val context: Context) {
    private val prefs = context.getSharedPreferences("reminders", Context.MODE_PRIVATE)
    private val geofencing by lazy { LocationServices.getGeofencingClient(context) }

    val diagnostics = DiagnosticsLog(prefs)

    private val widgetScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private val _places = MutableStateFlow(Place.decodeAll(prefs.getString(KEY_PLACES, "").orEmpty()))
    val places: StateFlow<List<Place>> = _places.asStateFlow()

    private val _countdown = MutableStateFlow(loadCountdown())
    val countdown: StateFlow<ArrivalCountdown?> = _countdown.asStateFlow()

    private val _unloadMinutes = MutableStateFlow(prefs.getInt(KEY_UNLOAD_MINUTES, DEFAULT_UNLOAD_MINUTES))
    val unloadMinutes: StateFlow<Int> = _unloadMinutes.asStateFlow()

    fun savePlaces(places: List<Place>) {
        _places.value = places
        prefs.edit().putString(KEY_PLACES, Place.encodeAll(places)).apply()
        reapplyGeofences()
    }

    /** Re-registers the geofences: after a save, after a reboot, or after the permission is granted. */
    fun reapplyGeofences() {
        val watched = ReminderPolicy.watchedPlaces(_places.value)
        val pendingIntent = geofencePendingIntent()
        geofencing.removeGeofences(pendingIntent).addOnCompleteListener {
            if (watched.isEmpty()) return@addOnCompleteListener
            val request = GeofencingRequest.Builder()
                // Don't fire for places the phone is already inside when they're registered.
                .setInitialTrigger(0)
                .addGeofences(watched.map { it.toGeofence() })
                .build()
            try {
                geofencing.addGeofences(request, pendingIntent)
                    .addOnSuccessListener { diagnostics.log("Watching ${watched.size} places") }
                    .addOnFailureListener { diagnostics.log("Geofences not registered: ${it.message}") }
            } catch (error: SecurityException) {
                diagnostics.log("Geofences not registered: location permission is missing")
            }
        }
    }

    fun setUnloadMinutes(minutes: Int) {
        _unloadMinutes.value = minutes
        prefs.edit().putInt(KEY_UNLOAD_MINUTES, minutes).apply()
    }

    /** The open list items, saved by the app so the widget and the receivers can show them. */
    fun openItemTitles(): List<String> =
        prefs.getString(KEY_OPEN_TITLES, "").orEmpty().split(RECORD).filter { it.isNotEmpty() }

    fun openItemCount(): Int = openItemTitles().size

    fun setOpenItemTitles(titles: List<String>) {
        prefs.edit().putString(KEY_OPEN_TITLES, titles.joinToString(RECORD)).apply()
        refreshWidget()
    }

    fun lastFiredAt(placeId: String): Long = prefs.getLong("fired_$placeId", 0L)

    fun markFired(placeId: String, now: Long) {
        prefs.edit().putLong("fired_$placeId", now).apply()
    }

    fun startUnloadTimer(now: Long) {
        startCountdown(ArrivalCountdown.starting(now, unloadMinutes.value * 60_000L))
    }

    fun remindAgain(now: Long) {
        startCountdown(ArrivalCountdown.starting(now, REMIND_AGAIN_MS))
    }

    /** The user tapped "Brought in": stop the countdown and cancel its reminder. */
    fun cancelUnloadTimer() {
        clearCountdown()
        UnloadWorker.cancel(context)
    }

    /** Ends the countdown without touching the scheduled reminder. The reminder calls this itself. */
    fun clearCountdown() {
        _countdown.value = null
        prefs.edit().remove(KEY_ENDS_AT).remove(KEY_DURATION).apply()
        refreshWidget()
    }

    private fun startCountdown(countdown: ArrivalCountdown) {
        _countdown.value = countdown
        prefs.edit()
            .putLong(KEY_ENDS_AT, countdown.endsAtMillis)
            .putLong(KEY_DURATION, countdown.durationMillis)
            .apply()
        UnloadWorker.schedule(context, countdown.endsAtMillis)
        refreshWidget()
    }

    private fun refreshWidget() {
        widgetScope.launch { GroceryWidget().updateAll(context) }
    }

    private fun loadCountdown(): ArrivalCountdown? {
        val endsAt = prefs.getLong(KEY_ENDS_AT, 0L)
        if (endsAt == 0L) return null
        return ArrivalCountdown(endsAt, prefs.getLong(KEY_DURATION, 0L))
    }

    private fun Place.toGeofence(): Geofence = Geofence.Builder()
        .setRequestId(id)
        .setCircularRegion(latitude, longitude, radiusMeters)
        .setExpirationDuration(Geofence.NEVER_EXPIRE)
        .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER)
        .build()

    private fun geofencePendingIntent(): PendingIntent = PendingIntent.getBroadcast(
        context,
        0,
        Intent(context, GeofenceReceiver::class.java),
        // Play services fills in the transition details, so the intent must be mutable.
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
    )

    companion object {
        const val DEFAULT_UNLOAD_MINUTES = 10
        const val REMIND_AGAIN_MS = 10 * 60_000L

        private const val KEY_PLACES = "places"
        private const val KEY_ENDS_AT = "countdown_ends_at"
        private const val KEY_DURATION = "countdown_duration"
        private const val KEY_UNLOAD_MINUTES = "unload_minutes"
        private const val KEY_OPEN_TITLES = "open_titles"
        private const val RECORD = ""
    }
}
