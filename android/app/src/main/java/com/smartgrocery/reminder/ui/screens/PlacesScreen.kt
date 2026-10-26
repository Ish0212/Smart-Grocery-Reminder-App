package com.smartgrocery.reminder.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.smartgrocery.reminder.reminders.LocationHelper
import com.smartgrocery.reminder.reminders.Place
import com.smartgrocery.reminder.reminders.PlaceKind
import com.smartgrocery.reminder.reminders.ReminderPolicy
import com.smartgrocery.reminder.reminders.ReminderStore
import kotlinx.coroutines.launch
import java.util.UUID

@Composable
fun PlacesScreen(reminders: ReminderStore) {
    val places by reminders.places.collectAsState()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var storeName by rememberSaveable { mutableStateOf("") }
    var status by rememberSaveable { mutableStateOf<String?>(null) }

    val home = places.firstOrNull { it.kind == PlaceKind.Home }
    val stores = places.filter { it.kind == PlaceKind.Store }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Text("Places", style = MaterialTheme.typography.headlineMedium)
        }
        item {
            PermissionsSection(reminders)
        }
        item {
            SectionTitle("Home")
            Text(
                if (home == null) "No home saved yet." else "Saved at ${home.latitude.format()}, ${home.longitude.format()}.",
                style = MaterialTheme.typography.bodyMedium,
            )
            Button(
                onClick = {
                    scope.launch {
                        val location = LocationHelper.currentLocation(context)
                        if (location == null) {
                            status = "Couldn't get your location. Try again with GPS on."
                            return@launch
                        }
                        val others = reminders.places.value.filterNot { it.kind == PlaceKind.Home }
                        reminders.savePlaces(
                            others + Place(Place.HOME_ID, "Home", PlaceKind.Home, location.latitude, location.longitude),
                        )
                        status = "Home saved."
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(if (home == null) "Set home from my location" else "Use my location as home")
            }
            PlaceSearch("Search for a home address") { name, latitude, longitude ->
                val others = reminders.places.value.filterNot { it.kind == PlaceKind.Home }
                reminders.savePlaces(others + Place(Place.HOME_ID, name, PlaceKind.Home, latitude, longitude))
                status = "Home saved."
            }
        }
        item {
            SectionTitle("Grocery stores")
            OutlinedTextField(
                value = storeName,
                onValueChange = { storeName = it },
                label = { Text("Store name") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            PlaceSearch("Search for a store") { name, latitude, longitude ->
                reminders.savePlaces(
                    reminders.places.value + Place(UUID.randomUUID().toString(), name, PlaceKind.Store, latitude, longitude),
                )
                status = "$name saved."
            }
            Button(
                onClick = {
                    scope.launch {
                        val location = LocationHelper.currentLocation(context)
                        if (location == null) {
                            status = "Couldn't get your location. Try again with GPS on."
                            return@launch
                        }
                        val name = storeName.trim().ifEmpty { "Grocery store" }
                        reminders.savePlaces(
                            reminders.places.value + Place(
                                UUID.randomUUID().toString(),
                                name,
                                PlaceKind.Store,
                                location.latitude,
                                location.longitude,
                            ),
                        )
                        storeName = ""
                        status = "$name saved."
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Add a store at my location")
            }
            if (stores.size > ReminderPolicy.MAX_WATCHED_PLACES - 1) {
                Text(
                    "Only the first ${ReminderPolicy.MAX_WATCHED_PLACES - 1} stores are watched, so home and the stores fit in ${ReminderPolicy.MAX_WATCHED_PLACES} geofences.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        items(stores, key = { it.id }) { store ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text(store.name, style = MaterialTheme.typography.bodyLarge)
                    Text(
                        "${store.latitude.format()}, ${store.longitude.format()}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                TextButton(onClick = {
                    reminders.savePlaces(reminders.places.value.filterNot { it.id == store.id })
                }) {
                    Text("Remove")
                }
            }
        }
        status?.let { message ->
            item {
                Text(message, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary)
            }
        }
    }
}

@Composable
private fun SectionTitle(title: String) {
    Text(title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 8.dp))
}

private fun Double.format(): String = "%.4f".format(this)
