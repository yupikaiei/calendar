package com.frelsical.nativeapp.external

import android.content.Intent
import android.net.Uri
import android.os.Build

/**
 * Translates intents sent by other apps into [ExternalEventRequest]s.
 *
 * Supports the platform contract for new events
 * (`ACTION_INSERT` with `vnd.android.cursor.dir/event`) and calendar files
 * opened or shared with Frelsi Cal.
 */
object ExternalEventIntents {

    fun parse(intent: Intent?): ExternalEventRequest? = when (intent?.action) {
        Intent.ACTION_INSERT,
        Intent.ACTION_INSERT_OR_EDIT,
        // Some apps add events through ACTION_EDIT on the events collection.
        Intent.ACTION_EDIT,
        -> ExternalEventRequest.NewEvent(ExternalEventParser.draftFromExtras(intent.extrasAsMap()))

        Intent.ACTION_VIEW -> intent.data?.let(ExternalEventRequest::ImportIcs)
        Intent.ACTION_SEND -> sharedCalendar(intent)
        else -> null
    }

    private fun sharedCalendar(intent: Intent): ExternalEventRequest? {
        intent.streamUri()?.let { return ExternalEventRequest.ImportIcs(it) }
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        return text
            ?.takeIf { it.contains("BEGIN:VCALENDAR", ignoreCase = true) }
            ?.let(ExternalEventRequest::ImportIcsText)
    }

    @Suppress("DEPRECATION")
    private fun Intent.extrasAsMap(): Map<String, Any?> {
        val bundle = extras ?: return emptyMap()
        return bundle.keySet().associateWith { bundle.get(it) }
    }

    private fun Intent.streamUri(): Uri? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            getParcelableExtra(Intent.EXTRA_STREAM)
        }
}
