package com.smartgrocery.reminder.ui.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.google.android.libraries.places.api.Places
import com.google.android.libraries.places.api.model.AutocompletePrediction
import com.google.android.libraries.places.api.model.AutocompleteSessionToken
import com.google.android.libraries.places.api.model.Place.Field
import com.google.android.libraries.places.api.net.FetchPlaceRequest
import com.google.android.libraries.places.api.net.FindAutocompletePredictionsRequest
import com.smartgrocery.reminder.BuildConfig
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

/**
 * Searches Google Places for an address or store. It needs a Maps API key in local.properties
 * (MAPS_API_KEY); without one, the search says so instead of failing.
 */
@Composable
fun PlaceSearch(label: String, onPicked: (name: String, latitude: Double, longitude: Double) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val client = remember {
        if (BuildConfig.MAPS_API_KEY.isBlank()) null else Places.createClient(context)
    }
    val token = remember { AutocompleteSessionToken.newInstance() }
    var query by rememberSaveable { mutableStateOf("") }
    var predictions by remember { mutableStateOf<List<AutocompletePrediction>>(emptyList()) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(query) {
        if (client == null || query.length < 3) {
            predictions = emptyList()
            return@LaunchedEffect
        }
        delay(300L)
        try {
            val request = FindAutocompletePredictionsRequest.builder()
                .setQuery(query)
                .setSessionToken(token)
                .build()
            predictions = client.findAutocompletePredictions(request).await().autocompletePredictions
            error = null
        } catch (failure: Exception) {
            error = failure.message ?: "Search failed. Check the connection and try again."
        }
    }

    Column(modifier = Modifier.fillMaxWidth()) {
        if (client == null) {
            Text(
                "Place search needs a Google Maps API key. Add MAPS_API_KEY to local.properties.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            return@Column
        }
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            label = { Text(label) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        predictions.take(5).forEach { prediction ->
            TextButton(onClick = {
                scope.launch {
                    val text = prediction.getPrimaryText(null).toString()
                    val place = client.fetchPlace(
                        FetchPlaceRequest.newInstance(prediction.placeId, listOf(Field.NAME, Field.LAT_LNG)),
                    ).await().place
                    val latLng = place.latLng ?: return@launch
                    onPicked(place.name ?: text, latLng.latitude, latLng.longitude)
                    query = ""
                    predictions = emptyList()
                }
            }) {
                Text(prediction.getFullText(null).toString())
            }
        }
    }
}
