package com.frelsical.nativeapp.notify

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.frelsical.nativeapp.MainActivity
import com.frelsical.nativeapp.R

class ReminderReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val eventId = intent.getLongExtra(EXTRA_EVENT_ID, -1L)
        val minutes = intent.getIntExtra(EXTRA_MINUTES, 0)
        if (eventId < 0) return

        ReminderScheduler.ensureChannel(context)
        if (!ReminderScheduler.notificationsAllowed(context)) return

        val title = intent.getStringExtra(EXTRA_TITLE)?.takeIf { it.isNotBlank() }
            ?: context.getString(R.string.app_name)
        val body = intent.getStringExtra(EXTRA_BODY)?.takeIf { it.isNotBlank() }
            ?: context.getString(R.string.reminder_default_body)

        val contentIntent = PendingIntent.getActivity(
            context,
            ReminderScheduler.notificationId(eventId, minutes),
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra(EXTRA_EVENT_ID, eventId)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, ReminderScheduler.CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .build()

        try {
            NotificationManagerCompat.from(context)
                .notify(ReminderScheduler.notificationId(eventId, minutes), notification)
        } catch (_: SecurityException) {
            // Notification permission was revoked between the check and notify().
        }
    }

    companion object {
        const val EXTRA_EVENT_ID = "event_id"
        const val EXTRA_MINUTES = "minutes"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
    }
}
