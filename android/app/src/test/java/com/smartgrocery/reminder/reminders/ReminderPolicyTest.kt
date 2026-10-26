package com.smartgrocery.reminder.reminders

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ReminderPolicyTest {

    private val now = 10_000_000L
    private val minute = 60_000L

    private fun store(id: String) = Place(id, id, PlaceKind.Store, 0.0, 0.0)
    private val home = Place(Place.HOME_ID, "Home", PlaceKind.Home, 0.0, 0.0)

    @Test
    fun watchesHomeAndAtMost19StoresInTotal20() {
        val places = listOf(home) + (1..25).map { store("s$it") }

        val watched = ReminderPolicy.watchedPlaces(places)

        assertEquals(20, watched.size)
        assertEquals(Place.HOME_ID, watched.first().id)
    }

    @Test
    fun watchesEveryStoreWhenThereIsNoHome() {
        val watched = ReminderPolicy.watchedPlaces(listOf(store("a"), store("b")))

        assertEquals(listOf("a", "b"), watched.map { it.id })
    }

    @Test
    fun storeEnterWithItemsOnTheListReminds() {
        val action = ReminderPolicy.decide(PlaceKind.Store, now, lastFiredAt = 0L, openItems = 3)

        assertEquals(ReminderAction.StoreReminder(openItems = 3), action)
    }

    @Test
    fun storeEnterWithAnEmptyListSaysNothing() {
        val action = ReminderPolicy.decide(PlaceKind.Store, now, lastFiredAt = 0L, openItems = 0)

        assertEquals(ReminderAction.Ignore, action)
    }

    @Test
    fun repeatStoreEnterWithinAnHourIsIgnored() {
        val recent = ReminderPolicy.decide(PlaceKind.Store, now, lastFiredAt = now - 30 * minute, openItems = 2)
        val later = ReminderPolicy.decide(PlaceKind.Store, now, lastFiredAt = now - 61 * minute, openItems = 2)

        assertEquals(ReminderAction.Ignore, recent)
        assertTrue(later is ReminderAction.StoreReminder)
    }

    @Test
    fun homeEnterStartsTheUnloadTimerUnlessItIsFlapping() {
        val flapping = ReminderPolicy.decide(PlaceKind.Home, now, lastFiredAt = now - 5 * minute, openItems = 0)
        val arrival = ReminderPolicy.decide(PlaceKind.Home, now, lastFiredAt = now - 16 * minute, openItems = 0)

        assertEquals(ReminderAction.Ignore, flapping)
        assertEquals(ReminderAction.StartUnloadTimer, arrival)
    }
}
