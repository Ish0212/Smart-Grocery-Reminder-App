package com.smartgrocery.reminder.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import com.smartgrocery.reminder.ui.screens.ArrivalScreen
import com.smartgrocery.reminder.ui.screens.AuthScreen
import com.smartgrocery.reminder.ui.screens.PlacesScreen
import com.smartgrocery.reminder.ui.screens.SettingsScreen
import com.smartgrocery.reminder.ui.screens.ShoppingListScreen

private enum class Tab(val label: String, val icon: ImageVector) {
    Shopping("List", Icons.Filled.ShoppingCart),
    Arrival("Arrival", Icons.Filled.Home),
    Places("Places", Icons.Filled.Place),
    Settings("Settings", Icons.Filled.Settings),
}

@Composable
fun RootScreen(viewModel: AppViewModel) {
    val user by viewModel.user.collectAsState()
    if (user == null) {
        AuthScreen(viewModel)
        return
    }

    var selected by rememberSaveable { mutableStateOf(Tab.Shopping) }

    Scaffold(
        bottomBar = {
            NavigationBar {
                Tab.entries.forEach { tab ->
                    NavigationBarItem(
                        selected = tab == selected,
                        onClick = { selected = tab },
                        icon = { Icon(tab.icon, contentDescription = null) },
                        label = { Text(tab.label) },
                    )
                }
            }
        },
    ) { padding ->
        Box(Modifier.padding(padding)) {
            when (selected) {
                Tab.Shopping -> ShoppingListScreen(viewModel)
                Tab.Arrival -> ArrivalScreen(viewModel.reminders)
                Tab.Places -> PlacesScreen(viewModel.reminders)
                Tab.Settings -> SettingsScreen(viewModel)
            }
        }
    }
}
