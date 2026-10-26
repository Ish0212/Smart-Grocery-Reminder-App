package com.smartgrocery.reminder.reminders

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

object Notifications {
    private const val CHANNEL_STORE = "store"
    private const val CHANNEL_UNLOAD = "unload"
    private const val ID_STORE = 1
    private const val ID_UNLOAD = 2

    fun createChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_STORE, "Store reminders", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "When you arrive at a grocery store"
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_UNLOAD, "Unload reminders", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "When your unload timer ends after you get home"
            },
        )
    }

    fun storeReminder(context: Context, storeName: String, openItems: Int) {
        val items = if (openItems == 1) "1 item" else "$openItems items"
        post(
            context,
            ID_STORE,
            NotificationCompat.Builder(context, CHANNEL_STORE)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("You're at $storeName")
                .setContentText("$items still on your list.")
                .setAutoCancel(true)
                .build(),
        )
    }

    fun unloadReminder(context: Context) {
        post(
            context,
            ID_UNLOAD,
            NotificationCompat.Builder(context, CHANNEL_UNLOAD)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("Groceries still in the car?")
                .setContentText("Bring them in, or remind yourself in 10 minutes.")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .addAction(0, "Brought in", actionIntent(context, ReminderActionReceiver.ACTION_BROUGHT_IN, 10))
                .addAction(0, "Remind again", actionIntent(context, ReminderActionReceiver.ACTION_REMIND_AGAIN, 11))
                .build(),
        )
    }

    fun cancelUnload(context: Context) {
        NotificationManagerCompat.from(context).cancel(ID_UNLOAD)
    }

    fun canPost(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun actionIntent(context: Context, action: String, requestCode: Int): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            requestCode,
            Intent(context, ReminderActionReceiver::class.java).setAction(action),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    @SuppressLint("MissingPermission")
    private fun post(context: Context, id: Int, notification: android.app.Notification) {
        if (!canPost(context)) return
        NotificationManagerCompat.from(context).notify(id, notification)
    }
}
