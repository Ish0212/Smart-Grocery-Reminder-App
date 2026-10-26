package com.smartgrocery.reminder

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.viewmodel.compose.viewModel
import com.smartgrocery.reminder.ui.AppViewModel
import com.smartgrocery.reminder.ui.RootScreen
import com.smartgrocery.reminder.ui.theme.SmartGroceryTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            SmartGroceryTheme {
                val container = (LocalContext.current.applicationContext as SmartGroceryApplication).container
                val viewModel: AppViewModel = viewModel(factory = AppViewModel.Factory(container))
                RootScreen(viewModel)
            }
        }
    }
}
