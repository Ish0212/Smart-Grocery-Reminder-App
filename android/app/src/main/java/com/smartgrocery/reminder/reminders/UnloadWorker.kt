package com.smartgrocery.reminder.reminders

import android.content.Context
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.smartgrocery.reminder.SmartGroceryApplication
import java.util.concurrent.TimeUnit

/**
 * Fires when the unload countdown ends. WorkManager keeps it scheduled across app kills and reboots.
 * If the countdown was cancelled or replaced, the endsAt no longer matches and it does nothing.
 */
class UnloadWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val endsAt = inputData.getLong(KEY_ENDS_AT, 0L)
        val reminders = (applicationContext as SmartGroceryApplication).container.reminders
        if (reminders.countdown.value?.endsAtMillis == endsAt) {
            reminders.clearCountdown()
            Notifications.unloadReminder(applicationContext)
            reminders.diagnostics.log("Unload reminder shown")
        }
        return Result.success()
    }

    companion object {
        private const val UNIQUE_NAME = "unload-reminder"
        private const val KEY_ENDS_AT = "endsAt"

        fun schedule(context: Context, endsAtMillis: Long) {
            val delay = (endsAtMillis - System.currentTimeMillis()).coerceAtLeast(0L)
            val request = OneTimeWorkRequestBuilder<UnloadWorker>()
                .setInitialDelay(delay, TimeUnit.MILLISECONDS)
                .setInputData(workDataOf(KEY_ENDS_AT to endsAtMillis))
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(UNIQUE_NAME, ExistingWorkPolicy.REPLACE, request)
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(UNIQUE_NAME)
        }
    }
}
