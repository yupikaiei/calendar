package com.frelsical.nativeapp.data

import java.time.LocalDate

data class CalendarRecord(
    val id: Long,
    val urlPath: String,
    val displayName: String,
    val color: String?,
    val cTag: String?,
)

data class Event(
    val id: Long = 0L,
    val uid: String,
    val title: String,
    val start: Long,
    val end: Long,
    val description: String? = null,
    val location: String? = null,
    val recurrenceRule: String? = null,
    val calendarId: Long? = null,
    val allDay: Boolean = false,
    /** Original occurrence starts that were edited or deleted individually. */
    val excludedStarts: Set<Long> = emptySet(),
    /** True when the local copy has changes that still need to be uploaded. */
    val dirty: Boolean = false,
)

data class Reminder(
    val id: Long,
    val eventId: Long,
    val minutesBefore: Int,
)

data class EventWithCalendar(
    val event: Event,
    val calendar: CalendarRecord?,
)

/**
 * A concrete rendering of an event on a specific day. Recurring events produce one
 * occurrence per instance while the base [Event] is left untouched.
 */
data class Occurrence(
    val event: Event,
    val calendar: CalendarRecord?,
    val start: Long,
    val end: Long,
    val date: LocalDate,
    val isRecurringInstance: Boolean,
) {
    val durationMillis: Long get() = end - start
}

data class EventWithReminders(
    val event: Event,
    val reminderMinutes: List<Int>,
)
