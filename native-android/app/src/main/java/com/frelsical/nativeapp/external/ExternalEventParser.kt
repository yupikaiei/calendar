package com.frelsical.nativeapp.external

import com.frelsical.nativeapp.data.EventDraft
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset

/**
 * Reads the extras defined by the platform calendar contract
 * (`CalendarContract.Events`) into an [EventDraft].
 *
 * Kept free of Android types so the mapping can be unit tested on the JVM.
 */
object ExternalEventParser {

    const val EXTRA_TITLE = "title"
    const val EXTRA_ANDROID_TITLE = "android.intent.extra.TITLE"
    const val EXTRA_DESCRIPTION = "description"
    const val EXTRA_LOCATION = "eventLocation"
    const val EXTRA_RRULE = "rrule"
    const val EXTRA_BEGIN_TIME = "beginTime"
    const val EXTRA_END_TIME = "endTime"
    const val EXTRA_ALL_DAY = "allDay"

    private const val HOUR_MILLIS = 60 * 60 * 1000L
    private const val DAY_MILLIS = 24 * HOUR_MILLIS

    fun draftFromExtras(
        extras: Map<String, Any?>,
        now: Long = System.currentTimeMillis(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): EventDraft {
        val allDay = extras[EXTRA_ALL_DAY].asBoolean()
        val start = extras[EXTRA_BEGIN_TIME].asMillis()
            ?.let { if (allDay) utcDateToLocalMidnight(it, zone) else it }
            ?: now
        val fallbackEnd = start + if (allDay) DAY_MILLIS else HOUR_MILLIS
        val end = (
            extras[EXTRA_END_TIME].asMillis()
                ?.let { if (allDay) utcDateToLocalMidnight(it, zone) else it }
                ?: fallbackEnd
            ).takeIf { it > start } ?: fallbackEnd

        return EventDraft(
            title = extras.string(EXTRA_TITLE) ?: extras.string(EXTRA_ANDROID_TITLE).orEmpty(),
            description = extras.string(EXTRA_DESCRIPTION)?.takeIf { it.isNotBlank() },
            location = extras.string(EXTRA_LOCATION)?.takeIf { it.isNotBlank() },
            start = start,
            end = end,
            allDay = allDay,
            recurrenceRule = extras.string(EXTRA_RRULE)?.takeIf { it.isNotBlank() },
        )
    }

    /**
     * `CalendarContract` defines all-day begin/end as UTC midnight, while the
     * app stores all-day events at local midnight.
     */
    private fun utcDateToLocalMidnight(millis: Long, zone: ZoneId): Long {
        val date = Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate()
        return date.atStartOfDay(zone).toInstant().toEpochMilli()
    }

    private fun Map<String, Any?>.string(key: String): String? =
        this[key]?.toString()?.trim()?.takeIf { it.isNotEmpty() }

    private fun Any?.asBoolean(): Boolean = when (this) {
        is Boolean -> this
        is Number -> toInt() != 0
        is String -> equals("true", ignoreCase = true) || this == "1"
        else -> false
    }

    private fun Any?.asMillis(): Long? = when (this) {
        is Number -> toLong()
        is String -> toLongOrNull() ?: runCatching { Instant.parse(trim()).toEpochMilli() }.getOrNull()
        else -> null
    }
}
