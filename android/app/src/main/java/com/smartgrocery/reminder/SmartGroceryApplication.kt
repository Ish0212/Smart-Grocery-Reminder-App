package com.smartgrocery.reminder

import android.app.Application
import com.smartgrocery.reminder.reminders.Notifications

class SmartGroceryApplication : Application() {
    val container: AppContainer by lazy { AppContainer(BuildConfig.USE_FIREBASE, this) }

    override fun onCreate() {
        super.onCreate()
        Notifications.createChannels(this)
    }
}
