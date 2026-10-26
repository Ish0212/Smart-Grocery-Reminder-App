package com.smartgrocery.reminder.reminders

import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class LogEntry(val time: Long, val message: String)

/** A short on-device log of location and reminder events, for the Diagnostics screen. */
class DiagnosticsLog(private val prefs: SharedPreferences) {
    private val _entries = MutableStateFlow(decode(prefs.getString(KEY, "").orEmpty()))

    /** Oldest first. */
    val entries: StateFlow<List<LogEntry>> = _entries.asStateFlow()

    fun log(message: String, now: Long = System.currentTimeMillis()) {
        val updated = appendCapped(_entries.value, LogEntry(now, message), MAX_ENTRIES)
        _entries.value = updated
        prefs.edit().putString(KEY, encode(updated)).apply()
    }

    fun clear() {
        _entries.value = emptyList()
        prefs.edit().remove(KEY).apply()
    }

    companion object {
        const val MAX_ENTRIES = 200
        private const val KEY = "diagnostics_log"

        // Same separators as Place: messages are free text.
        private const val RECORD = "\u001E"
        private const val FIELD = "\u001F"

        fun appendCapped(entries: List<LogEntry>, entry: LogEntry, max: Int): List<LogEntry> =
            (entries + entry).takeLast(max)

        fun encode(entries: List<LogEntry>): String =
            entries.joinToString(RECORD) { "${it.time}$FIELD${it.message}" }

        fun decode(text: String): List<LogEntry> =
            text.split(RECORD).filter { it.isNotBlank() }.mapNotNull { record ->
                val fields = record.split(FIELD, limit = 2)
                val time = fields.getOrNull(0)?.toLongOrNull() ?: return@mapNotNull null
                LogEntry(time, fields.getOrNull(1).orEmpty())
            }
    }
}
