package com.frelsical.nativeapp.data

import android.content.Context
import android.net.Uri
import com.frelsical.nativeapp.ical.IcsParser
import com.frelsical.nativeapp.ical.RecurrenceRules
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import java.util.UUID

class EventRepository(
    private val context: Context,
    private val database: CalendarDatabase,
) {
    private val _events = MutableStateFlow<List<EventWithCalendar>>(emptyList())
    val events: StateFlow<List<EventWithCalendar>> = _events.asStateFlow()

    private val _calendars = MutableStateFlow<List<CalendarRecord>>(emptyList())
    val calendars: StateFlow<List<CalendarRecord>> = _calendars.asStateFlow()

    suspend fun reload() = withContext(Dispatchers.IO) {
        _events.value = database.getEventsWithCalendars()
        _calendars.value = database.getCalendars()
    }

    suspend fun getEvent(id: Long): Event? = withContext(Dispatchers.IO) {
        database.getEvent(id)
    }

    suspend fun getReminderMinutes(eventId: Long): List<Int> = withContext(Dispatchers.IO) {
        database.getReminderMinutes(eventId)
    }

    suspend fun saveEvent(event: Event, reminderMinutes: List<Int>): Event =
        withContext(Dispatchers.IO) {
            val previous = event.id.takeIf { it != 0L }?.let(database::getEvent)
            val saved = if (event.id == 0L) {
                val id = database.insertEvent(event)
                event.copy(id = id)
            } else {
                database.updateEvent(event)
                event
            }
            val preserveExceptions = previous != null &&
                baseRule(previous.recurrenceRule) == baseRule(saved.recurrenceRule)
            database.replaceRecurrenceExceptions(
                saved.id,
                if (saved.recurrenceRule != null && preserveExceptions) {
                    saved.excludedStarts
                } else {
                    emptySet()
                },
            )
            database.replaceReminders(saved.id, reminderMinutes)
            reload()
            saved
        }

    suspend fun addRecurrenceException(eventId: Long, occurrenceStart: Long) =
        withContext(Dispatchers.IO) {
            database.addRecurrenceException(eventId, occurrenceStart)
            reload()
        }

    suspend fun deleteEvent(event: Event) = withContext(Dispatchers.IO) {
        val calendar = event.calendarId?.let(database::getCalendar)
        // Local/imported events have no server counterpart, so they need no tombstone.
        if (calendar != null && !calendar.urlPath.startsWith("/local/")) {
            database.markEventDeleted(event.uid)
        }
        database.deleteEvent(event.id)
        reload()
    }

    suspend fun allEventsWithReminders(): List<EventWithReminders> = withContext(Dispatchers.IO) {
        database.getEventWithReminders()
    }

    suspend fun importIcs(uri: Uri): ImportResult = withContext(Dispatchers.IO) {
        try {
            val contents = context.contentResolver.openInputStream(uri)?.use { stream ->
                stream.bufferedReader(Charsets.UTF_8).readText()
            } ?: return@withContext ImportResult(0, "Unable to open the selected file.")

            val parsed = IcsParser.parseEvents(contents)
            if (parsed.isEmpty()) return@withContext ImportResult(0, "No events found in this file.")

            val calendarId = database.insertLocalCalendar(
                urlPath = "/local/imported/${System.currentTimeMillis()}/",
                displayName = "Imported Calendar",
                color = "#4CAF50",
            )

            for (item in parsed) {
                database.insertEvent(
                    Event(
                        uid = item.uid.ifBlank { UUID.randomUUID().toString() },
                        title = item.title,
                        start = item.start,
                        end = item.end,
                        description = item.description,
                        location = item.location,
                        recurrenceRule = item.recurrenceRule,
                        calendarId = calendarId,
                        allDay = item.allDay,
                    ),
                )
            }
            reload()
            ImportResult(parsed.size, "Imported ${parsed.size} event(s) successfully.")
        } catch (exception: Exception) {
            ImportResult(0, "Failed to import ICS: ${exception.message}")
        }
    }

    suspend fun createLocalCalendar(name: String): CalendarRecord = withContext(Dispatchers.IO) {
        val slug = name.lowercase()
            .replace(Regex("[^a-z0-9]+"), "-")
            .trim('-')
            .ifBlank { "calendar" }
        val id = database.insertLocalCalendar(
            urlPath = "/local/$slug-${System.currentTimeMillis()}/",
            displayName = name,
            color = "#6C63FF",
        )
        reload()
        database.getCalendar(id)!!
    }

    suspend fun updateCalendarName(calendarId: Long, name: String) = withContext(Dispatchers.IO) {
        database.updateCalendarName(calendarId, name)
        reload()
    }

    suspend fun updateCalendarColor(calendarId: Long, color: String) = withContext(Dispatchers.IO) {
        database.updateCalendarColor(calendarId, color)
        reload()
    }

    suspend fun deleteCalendar(calendarId: Long) = withContext(Dispatchers.IO) {
        database.deleteCalendar(calendarId)
        reload()
    }
}

private fun baseRule(rule: String?): String? {
    return RecurrenceRules.normalize(rule)?.let(RecurrenceRules::stripUntil)
}

data class ImportResult(val importedCount: Int, val message: String)
