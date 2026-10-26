package com.smartgrocery.reminder.reminders

sealed interface ReminderAction {
    /** Nothing to say: a repeat within the cooldown, or a store with nothing left on the list. */
    data object Ignore : ReminderAction

    data class StoreReminder(val openItems: Int) : ReminderAction

    data object StartUnloadTimer : ReminderAction
}

/**
 * The reminder rules, kept free of Android types so they can be tested on the JVM.
 * Geofence enters are the only events that reach this; exits are ignored.
 */
object ReminderPolicy {
    /** Home plus up to 19 stores. Matches the iOS limit of 20 monitored regions. */
    const val MAX_WATCHED_PLACES = 20

    /** Repeat enters (GPS jitter at the boundary) within these windows do nothing. */
    const val HOME_COOLDOWN_MS = 15 * 60_000L
    const val STORE_COOLDOWN_MS = 60 * 60_000L

    fun watchedPlaces(places: List<Place>): List<Place> {
        val home = places.filter { it.kind == PlaceKind.Home }.take(1)
        val stores = places.filter { it.kind == PlaceKind.Store }.take(MAX_WATCHED_PLACES - home.size)
        return home + stores
    }

    fun decide(kind: PlaceKind, now: Long, lastFiredAt: Long, openItems: Int): ReminderAction {
        val cooldown = if (kind == PlaceKind.Home) HOME_COOLDOWN_MS else STORE_COOLDOWN_MS
        if (lastFiredAt > 0 && now - lastFiredAt < cooldown) return ReminderAction.Ignore
        return when (kind) {
            PlaceKind.Home -> ReminderAction.StartUnloadTimer
            PlaceKind.Store -> if (openItems > 0) ReminderAction.StoreReminder(openItems) else ReminderAction.Ignore
        }
    }
}
