package com.frelsical.nativeapp.data

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

class CalendarDatabase(context: Context) :
    SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {

    override fun onConfigure(db: SQLiteDatabase) {
        super.onConfigure(db)
        db.setForeignKeyConstraintsEnabled(true)
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE calendars (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                url_path TEXT NOT NULL UNIQUE,
                display_name TEXT NOT NULL,
                color TEXT,
                ctag TEXT
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                uid TEXT NOT NULL,
                title TEXT NOT NULL,
                start_date INTEGER NOT NULL,
                end_date INTEGER NOT NULL,
                description TEXT,
                location TEXT,
                recurrence_rule TEXT,
                calendar_id INTEGER REFERENCES calendars(id) ON DELETE CASCADE,
                all_day INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE reminders (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                event_id INTEGER NOT NULL REFERENCES events(id) ON DELETE CASCADE,
                minutes_before INTEGER NOT NULL
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE deleted_events (
                uid TEXT PRIMARY KEY
            )
            """.trimIndent(),
        )
        db.execSQL("CREATE INDEX idx_events_calendar ON events(calendar_id)")
        db.execSQL("CREATE INDEX idx_reminders_event ON reminders(event_id)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Version 1 is the initial native schema. Future migrations should be additive.
    }

    // --- Events ---

    fun getEventsWithCalendars(): List<EventWithCalendar> {
        val sql =
            """
            SELECT e.id, e.uid, e.title, e.start_date, e.end_date, e.description,
                   e.location, e.recurrence_rule, e.calendar_id, e.all_day,
                   c.id AS c_id, c.url_path AS c_url_path,
                   c.display_name AS c_display_name, c.color AS c_color,
                   c.ctag AS c_ctag
            FROM events e
            LEFT JOIN calendars c ON c.id = e.calendar_id
            ORDER BY e.start_date ASC
            """.trimIndent()

        return readableDatabase.rawQuery(sql, null).use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    val calendar = cursor.toCalendarOrNull(prefix = "c_")
                    add(EventWithCalendar(cursor.toEvent(), calendar))
                }
            }
        }
    }

    fun getEvent(id: Long): Event? {
        return readableDatabase.query(
            "events",
            null,
            "id = ?",
            arrayOf(id.toString()),
            null,
            null,
            null,
        ).use { cursor ->
            if (cursor.moveToFirst()) cursor.toEvent() else null
        }
    }

    fun getEventByUid(uid: String): Event? {
        return readableDatabase.query(
            "events",
            null,
            "uid = ?",
            arrayOf(uid),
            null,
            null,
            "id ASC",
            "1",
        ).use { cursor ->
            if (cursor.moveToFirst()) cursor.toEvent() else null
        }
    }

    fun insertEvent(event: Event): Long {
        return writableDatabase.insertOrThrow("events", null, event.toValues(includeId = false))
    }

    fun updateEvent(event: Event): Boolean {
        val updated = writableDatabase.update(
            "events",
            event.toValues(includeId = false),
            "id = ?",
            arrayOf(event.id.toString()),
        )
        return updated > 0
    }

    fun deleteEvent(id: Long) {
        writableDatabase.delete("events", "id = ?", arrayOf(id.toString()))
    }

    fun getEventWithReminders(): List<EventWithReminders> {
        val events = getEventsWithCalendars().map { it.event }
        return events.map { event -> EventWithReminders(event, getReminderMinutes(event.id)) }
    }

    // --- Reminders ---

    fun getReminderMinutes(eventId: Long): List<Int> {
        return readableDatabase.query(
            "reminders",
            arrayOf("minutes_before"),
            "event_id = ?",
            arrayOf(eventId.toString()),
            null,
            null,
            "minutes_before ASC",
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) add(cursor.getInt(0))
            }
        }
    }

    fun replaceReminders(eventId: Long, minutes: List<Int>) {
        writableDatabase.inTransaction {
            delete("reminders", "event_id = ?", arrayOf(eventId.toString()))
            for (value in minutes.distinct()) {
                insertOrThrow(
                    "reminders",
                    null,
                    ContentValues().apply {
                        put("event_id", eventId)
                        put("minutes_before", value)
                    },
                )
            }
        }
    }

    // --- Calendars ---

    fun getCalendars(): List<CalendarRecord> {
        return readableDatabase.query(
            "calendars",
            null,
            null,
            null,
            null,
            null,
            "display_name COLLATE NOCASE ASC",
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) add(cursor.toCalendar())
            }
        }
    }

    fun getCalendarByPath(urlPath: String): CalendarRecord? {
        return readableDatabase.query(
            "calendars",
            null,
            "url_path = ?",
            arrayOf(urlPath),
            null,
            null,
            null,
        ).use { cursor ->
            if (cursor.moveToFirst()) cursor.toCalendar() else null
        }
    }

    fun getCalendar(id: Long): CalendarRecord? {
        return readableDatabase.query(
            "calendars",
            null,
            "id = ?",
            arrayOf(id.toString()),
            null,
            null,
            null,
        ).use { cursor ->
            if (cursor.moveToFirst()) cursor.toCalendar() else null
        }
    }

    /**
     * Updates metadata for an existing calendar or inserts a new one. Unlike
     * SQLite's REPLACE conflict strategy this never deletes (and therefore never
     * cascades into) the calendar's events.
     */
    fun upsertCalendar(urlPath: String, displayName: String, color: String?): CalendarRecord {
        val existing = getCalendarByPath(urlPath)
        if (existing == null) {
            val id = writableDatabase.insertOrThrow(
                "calendars",
                null,
                ContentValues().apply {
                    put("url_path", urlPath)
                    put("display_name", displayName)
                    put("color", color)
                },
            )
            return CalendarRecord(id, urlPath, displayName, color, null)
        }

        writableDatabase.update(
            "calendars",
            ContentValues().apply {
                put("display_name", displayName)
                if (color != null) put("color", color)
            },
            "id = ?",
            arrayOf(existing.id.toString()),
        )
        return existing.copy(displayName = displayName, color = color ?: existing.color)
    }

    fun insertLocalCalendar(urlPath: String, displayName: String, color: String?): Long {
        return writableDatabase.insertOrThrow(
            "calendars",
            null,
            ContentValues().apply {
                put("url_path", urlPath)
                put("display_name", displayName)
                put("color", color)
            },
        )
    }

    fun updateCalendarName(id: Long, displayName: String) {
        writableDatabase.update(
            "calendars",
            ContentValues().apply { put("display_name", displayName) },
            "id = ?",
            arrayOf(id.toString()),
        )
    }

    fun updateCalendarColor(id: Long, color: String) {
        writableDatabase.update(
            "calendars",
            ContentValues().apply { put("color", color) },
            "id = ?",
            arrayOf(id.toString()),
        )
    }

    fun updateCalendarCTag(id: Long, cTag: String) {
        writableDatabase.update(
            "calendars",
            ContentValues().apply { put("ctag", cTag) },
            "id = ?",
            arrayOf(id.toString()),
        )
    }

    fun deleteCalendar(id: Long) {
        writableDatabase.inTransaction {
            delete(
                "reminders",
                "event_id IN (SELECT id FROM events WHERE calendar_id = ?)",
                arrayOf(id.toString()),
            )
            delete("events", "calendar_id = ?", arrayOf(id.toString()))
            delete("calendars", "id = ?", arrayOf(id.toString()))
        }
    }

    // --- Deleted event tombstones ---

    fun markEventDeleted(uid: String) {
        writableDatabase.insertWithOnConflict(
            "deleted_events",
            null,
            ContentValues().apply { put("uid", uid) },
            SQLiteDatabase.CONFLICT_IGNORE,
        )
    }

    fun getDeletedEventUids(): Set<String> {
        return readableDatabase.query(
            "deleted_events",
            arrayOf("uid"),
            null,
            null,
            null,
            null,
            null,
        ).use { cursor ->
            buildSet {
                while (cursor.moveToNext()) add(cursor.getString(0))
            }
        }
    }

    fun removeDeletedEventUid(uid: String) {
        writableDatabase.delete("deleted_events", "uid = ?", arrayOf(uid))
    }

    private inline fun <T> SQLiteDatabase.inTransaction(block: SQLiteDatabase.() -> T): T {
        beginTransaction()
        try {
            val result = block()
            setTransactionSuccessful()
            return result
        } finally {
            endTransaction()
        }
    }
}

private fun Cursor.toEvent(): Event {
    return Event(
        id = getLong(getColumnIndexOrThrow("id")),
        uid = getString(getColumnIndexOrThrow("uid")),
        title = getString(getColumnIndexOrThrow("title")),
        start = getLong(getColumnIndexOrThrow("start_date")),
        end = getLong(getColumnIndexOrThrow("end_date")),
        description = getString(getColumnIndexOrThrow("description")),
        location = getString(getColumnIndexOrThrow("location")),
        recurrenceRule = getString(getColumnIndexOrThrow("recurrence_rule")),
        calendarId = getColumnIndex("calendar_id").takeIf { it >= 0 && !isNull(it) }?.let { getLong(it) },
        allDay = getInt(getColumnIndexOrThrow("all_day")) != 0,
    )
}

private fun Cursor.toCalendarOrNull(prefix: String = ""): CalendarRecord? {
    val idIndex = getColumnIndex("${prefix}id")
    if (idIndex < 0 || isNull(idIndex)) return null
    return CalendarRecord(
        id = getLong(idIndex),
        urlPath = getString(getColumnIndexOrThrow("${prefix}url_path")),
        displayName = getString(getColumnIndexOrThrow("${prefix}display_name")),
        color = nullableString("${prefix}color"),
        cTag = nullableString("${prefix}ctag"),
    )
}

private fun Cursor.nullableString(columnName: String): String? {
    val index = getColumnIndex(columnName)
    return if (index >= 0 && !isNull(index)) getString(index) else null
}

private fun Cursor.toCalendar(): CalendarRecord = toCalendarOrNull()!!

private fun Event.toValues(includeId: Boolean): ContentValues {
    return ContentValues().apply {
        if (includeId && id != 0L) put("id", id)
        put("uid", uid)
        put("title", title)
        put("start_date", start)
        put("end_date", end)
        put("description", description)
        put("location", location)
        put("recurrence_rule", recurrenceRule)
        put("calendar_id", calendarId)
        put("all_day", if (allDay) 1 else 0)
    }
}

private const val DATABASE_NAME = "frelsi_cal_native.db"
private const val DATABASE_VERSION = 1
