package com.smartgrocery.reminder.reminders

/**
 * The unload countdown. It stores when it ends rather than how long is left, so it stays correct
 * when the app is killed and reopened.
 */
data class ArrivalCountdown(
    val endsAtMillis: Long,
    val durationMillis: Long,
) {
    /** Whole seconds left, rounded up so the display doesn't hit 0 early. */
    fun remainingSeconds(now: Long): Long = ((endsAtMillis - now).coerceAtLeast(0L) + 999L) / 1000L

    companion object {
        fun starting(now: Long, durationMillis: Long) = ArrivalCountdown(now + durationMillis, durationMillis)
    }
}
