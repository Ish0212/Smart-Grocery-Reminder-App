package com.smartgrocery.reminder.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.smartgrocery.reminder.reminders.LocationHelper
import com.smartgrocery.reminder.reminders.ReminderStore

/** Asks for location (in two steps, as Android requires) and notifications, and shows what's still missing. */
@Composable
fun PermissionsSection(reminders: ReminderStore) {
    val context = LocalContext.current
    var foreground by remember { mutableStateOf(LocationHelper.hasForegroundAccess(context)) }
    var background by remember { mutableStateOf(LocationHelper.hasBackgroundAccess(context)) }
    var notifications by remember {
        mutableStateOf(
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED,
        )
    }

    val foregroundLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) {
        foreground = LocationHelper.hasForegroundAccess(context)
        background = LocationHelper.hasBackgroundAccess(context)
        reminders.reapplyGeofences()
    }
    val backgroundLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) {
        background = LocationHelper.hasBackgroundAccess(context)
        reminders.reapplyGeofences()
    }
    val notificationLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        notifications = granted
    }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Permissions", style = MaterialTheme.typography.titleMedium)
        when {
            !foreground -> Button(onClick = {
                foregroundLauncher.launch(
                    arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                )
            }) { Text("Allow location") }
            !background -> OutlinedButton(onClick = {
                backgroundLauncher.launch(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
            }) { Text("Allow location all the time") }
            else -> Text("Location: on", style = MaterialTheme.typography.bodyMedium)
        }
        if (!notifications) {
            OutlinedButton(onClick = { notificationLauncher.launch(Manifest.permission.POST_NOTIFICATIONS) }) {
                Text("Allow notifications")
            }
        }
    }
}
