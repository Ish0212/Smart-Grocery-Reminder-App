package com.smartgrocery.reminder.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val AccentGreen = Color(0xFF2E8B57)

private val LightColors = lightColorScheme(
    primary = AccentGreen,
    onPrimary = Color.White,
    background = Color(0xFFF2F2F7),
    surface = Color.White,
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF7FD3A0),
    onPrimary = Color(0xFF003919),
    background = Color.Black,
    surface = Color(0xFF1C1C1E),
)

@Composable
fun SmartGroceryTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        content = content,
    )
}
