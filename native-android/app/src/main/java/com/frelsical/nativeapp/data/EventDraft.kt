package com.frelsical.nativeapp.data

/**
 * Values used to pre-fill the editor for a new event. External apps supply a
 * draft instead of writing an event directly, so the user still reviews and
 * confirms what lands in the calendar.
 */
data class EventDraft(
    val title: String = "",
    val description: String? = null,
    val location: String? = null,
    val start: Long? = null,
    /** Exclusive end, matching the [Event] convention. */
    val end: Long? = null,
    val allDay: Boolean = false,
    val recurrenceRule: String? = null,
)
