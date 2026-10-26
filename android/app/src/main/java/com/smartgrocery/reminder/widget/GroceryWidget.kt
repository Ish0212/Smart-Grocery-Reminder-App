package com.smartgrocery.reminder.widget

import android.content.Context
import android.content.Intent
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.ActionParameters
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.layout.Column
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.padding
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.smartgrocery.reminder.MainActivity
import com.smartgrocery.reminder.SmartGroceryApplication
import java.text.DateFormat
import java.util.Date

/**
 * The home-screen widget: the open items, and the unload countdown with a "Brought in" button. It
 * reads what the app saved to the device, so it works without opening the app.
 */
class GroceryWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val reminders = (context.applicationContext as SmartGroceryApplication).container.reminders
        val titles = reminders.openItemTitles()
        val countdown = reminders.countdown.value
        val ink = ColorProvider(day = Color(0xFF1C1C1E), night = Color(0xFFF2F2F7))
        val openApp = actionStartActivity(Intent(context, MainActivity::class.java))

        provideContent {
            Column(
                modifier = GlanceModifier
                    .fillMaxSize()
                    .padding(12.dp)
                    .clickable(openApp),
            ) {
                Text(
                    "To buy (${titles.size})",
                    style = TextStyle(color = ink, fontSize = 16.sp),
                )
                titles.take(4).forEach { title ->
                    Text("• $title", style = TextStyle(color = ink, fontSize = 14.sp))
                }
                if (titles.size > 4) {
                    Text("+${titles.size - 4} more", style = TextStyle(color = ink, fontSize = 12.sp))
                }
                if (countdown != null) {
                    val time = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(countdown.endsAtMillis))
                    Text("Unload reminder at $time", style = TextStyle(color = ink, fontSize = 12.sp))
                    Text(
                        "Brought in",
                        style = TextStyle(color = ink, fontSize = 14.sp),
                        modifier = GlanceModifier.clickable(actionRunCallback<BroughtInAction>()),
                    )
                }
            }
        }
    }
}

class BroughtInAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        (context.applicationContext as SmartGroceryApplication).container.reminders.cancelUnloadTimer()
        GroceryWidget().updateAll(context)
    }
}
