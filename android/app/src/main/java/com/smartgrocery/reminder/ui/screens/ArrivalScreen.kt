package com.smartgrocery.reminder.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.smartgrocery.reminder.reminders.ReminderStore
import kotlinx.coroutines.delay

private val TimerLengths = listOf(5, 10, 15, 30)

@Composable
fun ArrivalScreen(reminders: ReminderStore) {
    val countdown by reminders.countdown.collectAsState()
    val unloadMinutes by reminders.unloadMinutes.collectAsState()
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }

    LaunchedEffect(Unit) {
        while (true) {
            now = System.currentTimeMillis()
            delay(1_000L)
        }
    }

    val running = countdown
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Home arrival", style = MaterialTheme.typography.headlineMedium)
        Text(
            "When you get home, start the timer. When it ends, you get a reminder to bring the groceries in.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Text(
            when {
                running == null -> "No timer running"
                running.remainingSeconds(now) > 0 -> formatCountdown(running.remainingSeconds(now))
                else -> "Time's up"
            },
            style = MaterialTheme.typography.displaySmall,
        )

        Text("Timer length", style = MaterialTheme.typography.labelLarge)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            TimerLengths.forEach { minutes ->
                val label = "$minutes min"
                if (minutes == unloadMinutes) {
                    Button(onClick = { reminders.setUnloadMinutes(minutes) }, modifier = Modifier.weight(1f)) {
                        Text(label)
                    }
                } else {
                    OutlinedButton(onClick = { reminders.setUnloadMinutes(minutes) }, modifier = Modifier.weight(1f)) {
                        Text(label)
                    }
                }
            }
        }

        Button(
            onClick = { reminders.startUnloadTimer(System.currentTimeMillis()) },
            enabled = running == null,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Start timer (I'm home)")
        }
        if (running != null) {
            OutlinedButton(onClick = reminders::cancelUnloadTimer, modifier = Modifier.fillMaxWidth()) {
                Text("Brought in")
            }
        }

        PermissionsSection(reminders)
    }
}

internal fun formatCountdown(totalSeconds: Long): String {
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return "%02d:%02d".format(minutes, seconds)
}
