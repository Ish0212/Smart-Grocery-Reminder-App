package com.smartgrocery.reminder

import android.app.Application

class SmartGroceryApplication : Application() {
    val container: AppContainer by lazy { AppContainer(useFirebase = BuildConfig.USE_FIREBASE) }
}
