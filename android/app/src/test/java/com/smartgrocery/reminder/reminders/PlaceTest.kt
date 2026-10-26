package com.smartgrocery.reminder.reminders

import org.junit.Assert.assertEquals
import org.junit.Test

class PlaceTest {

    @Test
    fun savedPlacesRoundTripIncludingNamesWithPunctuation() {
        val places = listOf(
            Place(Place.HOME_ID, "Home", PlaceKind.Home, 37.7749, -122.4194, 150f),
            Place("store-1", "Trader Joe's, Mission | 2nd", PlaceKind.Store, 37.7601, -122.4190, 120.5f),
        )

        assertEquals(places, Place.decodeAll(Place.encodeAll(places)))
    }

    @Test
    fun emptyOrCorruptTextDecodesToNoPlaces() {
        assertEquals(emptyList<Place>(), Place.decodeAll(""))
        assertEquals(emptyList<Place>(), Place.decodeAll("not a record"))
    }
}
