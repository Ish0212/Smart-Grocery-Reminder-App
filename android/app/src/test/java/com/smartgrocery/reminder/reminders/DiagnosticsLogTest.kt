package com.smartgrocery.reminder.reminders

import org.junit.Assert.assertEquals
import org.junit.Test

class DiagnosticsLogTest {

    @Test
    fun keepsOnlyTheNewestEntries() {
        var entries = emptyList<LogEntry>()
        for (i in 1..5) {
            entries = DiagnosticsLog.appendCapped(entries, LogEntry(i.toLong(), "event $i"), max = 3)
        }

        assertEquals(listOf("event 3", "event 4", "event 5"), entries.map { it.message })
    }

    @Test
    fun encodedEntriesDecodeBackIncludingMessagesWithSeparatorsLikeColons() {
        val entries = listOf(
            LogEntry(1_000L, "Entered Trader Joe's: 3 items, cooldown 60 min"),
            LogEntry(2_000L, "Home\u001Fodd text"),
        )

        assertEquals(entries, DiagnosticsLog.decode(DiagnosticsLog.encode(entries)))
    }

    @Test
    fun corruptRecordsAreSkipped() {
        val text = "not-a-time\u001Fhello\u001E42\u001Fkept"

        assertEquals(listOf(LogEntry(42L, "kept")), DiagnosticsLog.decode(text))
    }
}
