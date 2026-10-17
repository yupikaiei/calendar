package com.frelsical.nativeapp.notify

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import com.frelsical.nativeapp.R
import com.frelsical.nativeapp.data.Event
import com.frelsical.nativeapp.ical.RecurrenceExpander
import java.time.ZoneId

class ReminderScheduler(private val context: Context) {

    /**
     * Schedules the next reminder for this event, including occurrences of a
     * repeating series. When the alarm fires, [ReminderReceiver] chains the
     * following occurrence.
     */
    fun scheduleNext(
        event: Event,
        minutesBefore: Int,
        afterMillis: Long = System.currentTimeMillis(),
    ) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val cancelIntent = reminderIntent(event.id, null, minutesBefore, -1L)
        val offset = minutesBefore * 60_000L
        val occurrenceStart = RecurrenceExpander.nextOccurrenceStart(
            event = event,
            afterMillis = afterMillis + offset,
            zone = ZoneId.systemDefault(),
        )

        if (occurrenceStart == null) {
            Log.d(TAG, "No next occurrence for event ${event.id} (${event.title}); cancelling")
            alarmManager.cancel(cancelIntent)
            return
        }

        val triggerAt = occurrenceStart - offset
        if (triggerAt < afterMillis) {
            alarmManager.cancel(cancelIntent)
            return
        }

        Log.d(
            TAG,
            "Scheduling event ${event.id} (${event.title}) minutes=$minutesBefore " +
                "occurrence=$occurrenceStart trigger=$triggerAt now=${System.currentTimeMillis()}",
        )
        val pendingIntent = reminderIntent(event.id, event, minutesBefore, occurrenceStart)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
            // Without the exact-alarm grant an inexact alarm keeps reminders working.
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
        } else {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
        }
    }

    fun cancel(eventId: Long, minutesBefore: Int) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        Log.d(TAG, "Cancelling event $eventId minutes=$minutesBefore")
        alarmManager.cancel(reminderIntent(eventId, null, minutesBefore, -1L))
    }

    fun cancelAll(eventId: Long, reminders: List<Int>) {
        reminders.forEach { cancel(eventId, it) }
    }

    private fun reminderIntent(
        eventId: Long,
        event: Event?,
        minutesBefore: Int,
        occurrenceStart: Long,
    ): PendingIntent {
        val intent = Intent(context, ReminderReceiver::class.java).apply {
            putExtra(ReminderReceiver.EXTRA_EVENT_ID, eventId)
            putExtra(ReminderReceiver.EXTRA_MINUTES, minutesBefore)
            putExtra(ReminderReceiver.EXTRA_OCCURRENCE_START, occurrenceStart)
            if (event != null) {
                putExtra(ReminderReceiver.EXTRA_TITLE, event.title)
                putExtra(ReminderReceiver.EXTRA_BODY, reminderBody(minutesBefore))
            }
        }
        return PendingIntent.getBroadcast(
            context,
            notificationId(eventId, minutesBefore),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    companion object {
        private const val TAG = "ReminderScheduler"
        const val CHANNEL_ID = "frelsi_cal_reminders"

        fun ensureChannel(context: Context) {
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            val channel = NotificationChannel(
                CHANNEL_ID,
                context.getString(R.string.notification_channel_reminders),
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = context.getString(R.string.notification_channel_reminders_description)
            }
            manager.createNotificationChannel(channel)
        }

        fun notificationsAllowed(context: Context): Boolean {
            return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.POST_NOTIFICATIONS,
                ) == PackageManager.PERMISSION_GRANTED
        }

        fun reminderBody(minutesBefore: Int): String {
            if (minutesBefore == 0) return "Starts now!"
            val minutes = minutesBefore.toLong()
            return when {
                minutes >= 1440 -> "Starts in ${minutes / 1440} day(s)"
                minutes >= 60 -> "Starts in ${minutes / 60} hour(s)"
                else -> "Starts in $minutes minutes"
            }
        }

        fun notificationId(eventId: Long, minutesBefore: Int): Int {
            return ((eventId xor (eventId ushr 32)).toInt() * 31 + minutesBefore) and 0x7fffffff
        }
    }
}
