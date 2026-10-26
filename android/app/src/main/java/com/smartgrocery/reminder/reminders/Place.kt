package com.smartgrocery.reminder.reminders

enum class PlaceKind { Home, Store }

/** A saved home or grocery store. Geofences are built from these. */
data class Place(
    val id: String,
    val name: String,
    val kind: PlaceKind,
    val latitude: Double,
    val longitude: Double,
    val radiusMeters: Float = 150f,
) {
    companion object {
        const val HOME_ID = "home"

        // Unit and record separators: names are free text, so they can't use a plain delimiter.
        private const val RECORD = "\u001E"
        private const val FIELD = "\u001F"

        fun encodeAll(places: List<Place>): String =
            places.joinToString(RECORD) { place ->
                listOf(place.id, place.name, place.kind.name, place.latitude, place.longitude, place.radiusMeters)
                    .joinToString(FIELD)
            }

        fun decodeAll(text: String): List<Place> =
            text.split(RECORD).filter { it.isNotBlank() }.mapNotNull { record ->
                val fields = record.split(FIELD)
                if (fields.size != 6) return@mapNotNull null
                runCatching {
                    Place(
                        id = fields[0],
                        name = fields[1],
                        kind = PlaceKind.valueOf(fields[2]),
                        latitude = fields[3].toDouble(),
                        longitude = fields[4].toDouble(),
                        radiusMeters = fields[5].toFloat(),
                    )
                }.getOrNull()
            }
    }
}
