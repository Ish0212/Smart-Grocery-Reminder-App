package com.smartgrocery.reminder

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
import androidx.activity.compose.setContent
import com.smartgrocery.reminder.ui.RootScreen
import com.smartgrocery.reminder.ui.theme.SmartGroceryTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            SmartGroceryTheme {
                RootScreen()
            }
        }
    }
}
