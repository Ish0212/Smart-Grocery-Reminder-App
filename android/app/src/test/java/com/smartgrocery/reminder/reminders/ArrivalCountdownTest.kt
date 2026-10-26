package com.smartgrocery.reminder.reminders

import org.junit.Assert.assertEquals
import org.junit.Test

class ArrivalCountdownTest {

    private val start = 1_000_000L
    private val tenMinutes = 10 * 60_000L

    @Test
    fun startsAtTheFullDuration() {
        val countdown = ArrivalCountdown.starting(start, tenMinutes)

        assertEquals(600L, countdown.remainingSeconds(start))
    }

    @Test
    fun roundsUpSoItDoesNotShowZeroEarly() {
        val countdown = ArrivalCountdown.starting(start, tenMinutes)

        assertEquals(1L, countdown.remainingSeconds(countdown.endsAtMillis - 1))
    }

    @Test
    fun reachesZeroAtTheEndAndStaysThere() {
        val countdown = ArrivalCountdown.starting(start, tenMinutes)

        assertEquals(0L, countdown.remainingSeconds(countdown.endsAtMillis))
        assertEquals(0L, countdown.remainingSeconds(countdown.endsAtMillis + 5_000))
    }

    @Test
    fun countsDownFromTheSavedEndTimeAfterARelaunch() {
        val saved = ArrivalCountdown.starting(start, tenMinutes)
        val afterRelaunch = saved.copy()

        assertEquals(300L, afterRelaunch.remainingSeconds(start + 5 * 60_000L))
    }
}
