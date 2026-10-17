package com.frelsical.nativeapp.notify

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.frelsical.nativeapp.FrelsiApplication
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/** Re-registers alarms after a reboot or app update (alarms do not survive either). */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in SUPPORTED_ACTIONS) return

        val pendingResult = goAsync()
        val app = context.applicationContext as FrelsiApplication
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val scheduler = ReminderScheduler(context)
                for (item in app.database.getEventWithReminders()) {
                    for (minutes in item.reminderMinutes) {
                        scheduler.scheduleNext(item.event, minutes)
                    }
                }
            } finally {
                pendingResult.finish()
            }
        }
    }

    private companion object {
        val SUPPORTED_ACTIONS = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
        )
    }
}
