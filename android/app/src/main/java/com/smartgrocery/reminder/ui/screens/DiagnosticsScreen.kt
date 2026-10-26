package com.smartgrocery.reminder.ui.screens

import android.content.Intent
import android.os.PowerManager
import android.provider.Settings
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.smartgrocery.reminder.reminders.LocationHelper
import com.smartgrocery.reminder.reminders.Notifications
import com.smartgrocery.reminder.reminders.PlaceKind
import com.smartgrocery.reminder.reminders.ReminderPolicy
import com.smartgrocery.reminder.reminders.ReminderStore
import java.text.DateFormat
import java.util.Date

private data class HealthItem(val label: String, val ok: Boolean, val fix: String)

@Composable
fun DiagnosticsScreen(reminders: ReminderStore, onBack: () -> Unit) {
    val context = LocalContext.current
    val places by reminders.places.collectAsState()
    val entries by reminders.diagnostics.entries.collectAsState()

    val home = places.any { it.kind == PlaceKind.Home }
    val watched = ReminderPolicy.watchedPlaces(places).size
    val batteryUnrestricted = context.getSystemService(PowerManager::class.java)
        .isIgnoringBatteryOptimizations(context.packageName)
    val checks = listOf(
        HealthItem("Location access", LocationHelper.hasForegroundAccess(context), "Allow location in Places."),
        HealthItem(
            "Location all the time",
            LocationHelper.hasBackgroundAccess(context),
            "Needed to hear arrivals while the app is closed.",
        ),
        HealthItem("Notifications allowed", Notifications.canPost(context), "Allow notifications in Arrival."),
        HealthItem("Home saved", home, "Set home in Places."),
        HealthItem(
            "Battery unrestricted",
            batteryUnrestricted,
            "Some phones delay background work. Set the app to unrestricted battery use.",
        ),
    )

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(24.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = onBack) { Text("Back") }
                Text("Diagnostics", style = MaterialTheme.typography.headlineSmall)
            }
        }
        item {
            Text("Reminder health", style = MaterialTheme.typography.titleMedium)
        }
        items(checks, key = { it.label }) { check ->
            Column {
                Text(
                    "${if (check.ok) "OK" else "Fix"}: ${check.label}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (check.ok) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.error,
                )
                if (!check.ok) {
                    Text(
                        check.fix,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
        item {
            Text(
                "Watching $watched of ${places.size} saved places.",
                style = MaterialTheme.typography.bodyMedium,
            )
            if (!batteryUnrestricted) {
                OutlinedButton(
                    onClick = {
                        context.startActivity(
                            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Open battery settings")
                }
            }
        }
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Event log", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                TextButton(onClick = { reminders.diagnostics.clear() }) { Text("Clear") }
            }
        }
        if (entries.isEmpty()) {
            item {
                Text("No events yet.", style = MaterialTheme.typography.bodyMedium)
            }
        }
        items(entries.reversed()) { entry ->
            Column(Modifier.padding(vertical = 2.dp)) {
                Text(
                    DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(entry.time)),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(entry.message, style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}
