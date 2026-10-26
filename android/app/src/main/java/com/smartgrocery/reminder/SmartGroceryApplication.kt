package com.smartgrocery.reminder

import android.app.Application
import com.google.android.libraries.places.api.Places
import com.smartgrocery.reminder.reminders.Notifications

class SmartGroceryApplication : Application() {
    val container: AppContainer by lazy { AppContainer(BuildConfig.USE_FIREBASE, this) }

    override fun onCreate() {
        super.onCreate()
        Notifications.createChannels(this)
        if (BuildConfig.MAPS_API_KEY.isNotBlank() && !Places.isInitialized()) {
            Places.initialize(this, BuildConfig.MAPS_API_KEY)
        }
    }
}
