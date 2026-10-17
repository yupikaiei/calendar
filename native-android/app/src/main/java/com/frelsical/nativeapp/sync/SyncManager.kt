package com.frelsical.nativeapp.sync

import android.util.Log
import com.frelsical.nativeapp.data.CalendarDatabase
import com.frelsical.nativeapp.data.Event
import com.frelsical.nativeapp.ical.IcsParser
import com.frelsical.nativeapp.network.CalDavClient
import com.frelsical.nativeapp.settings.SecureStore
import com.frelsical.nativeapp.settings.SettingsStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class SyncReport(val success: Boolean, val message: String)

/**
 * Two-way CalDAV sync mirroring the Flutter implementation:
 * push local changes, push tombstones, then pull when the server ctag changes.
 */
class SyncManager(
    private val database: CalendarDatabase,
    private val settings: SettingsStore,
    private val secureStore: SecureStore,
) {
    suspend fun performSync(): SyncReport = withContext(Dispatchers.IO) {
        if (!settings.isCalDavConfigured) {
            return@withContext SyncReport(
                success = false,
                message = "Add your CalDAV server details in Settings first.",
            )
        }

        val client = try {
            CalDavClient(settings.serverUrl, settings.username, secureStore.readPassword())
        } catch (exception: Exception) {
            return@withContext SyncReport(false, "Invalid server URL: ${exception.message}")
        }

        try {
            val username = settings.username
            val userPath = "/$username/"
            var remoteCalendars = client.getCalendars(userPath)

            if (remoteCalendars.isEmpty()) {
                if (client.createCalendar("/$username/frelsi/", "Frelsi Calendar")) {
                    remoteCalendars = client.getCalendars(userPath)
                }
            }

            if (remoteCalendars.isEmpty()) {
                return@withContext SyncReport(
                    success = false,
                    message = "No CalDAV calendars found and none could be created.",
                )
            }

            for (remote in remoteCalendars) {
                database.upsertCalendar(remote.urlPath, remote.displayName, remote.color)
            }

            val localCalendars = database.getCalendars()
            val defaultCalendar = localCalendars.firstOrNull { it.urlPath.contains("frelsi") }
                ?: localCalendars.firstOrNull()
            val deletedUids = database.getDeletedEventUids().toMutableSet()

            var pushed = 0
            var pulled = 0
            var deletions = 0

            for (calendar in localCalendars) {
                // Imported calendars are local-only.
                if (calendar.urlPath.startsWith("/local/")) continue

                var cTag: String? = client.getCTag(calendar.urlPath) ?: continue

                val localEvents = database.getEventsWithCalendars()
                    .filter { item ->
                        item.event.calendarId == calendar.id ||
                            (item.event.calendarId == null && calendar.id == defaultCalendar?.id)
                    }
                    .map { it.event }

                for (event in localEvents) {
                    val ics = IcsParser.generateIcs(event)
                    if (client.putEvent(calendar.urlPath, "${event.uid}.ics", ics)) {
                        pushed++
                        if (event.calendarId == null) {
                            database.updateEvent(event.copy(calendarId = calendar.id))
                        }
                    }
                }

                for (uid in deletedUids.toList()) {
                    if (client.deleteEvent(calendar.urlPath, "$uid.ics")) {
                        database.removeDeletedEventUid(uid)
                        deletedUids.remove(uid)
                        deletions++
                    }
                }

                cTag = client.getCTag(calendar.urlPath)
                if (cTag != null && cTag != calendar.cTag) {
                    for (ics in client.getCalendarEvents(calendar.urlPath)) {
                        val parsed = IcsParser.parseEvent(ics) ?: continue
                        val existing = database.getEventByUid(parsed.uid)
                        val event = Event(
                            id = existing?.id ?: 0L,
                            uid = parsed.uid,
                            title = parsed.title,
                            start = parsed.start,
                            end = parsed.end,
                            description = parsed.description,
                            location = parsed.location,
                            recurrenceRule = parsed.recurrenceRule,
                            calendarId = calendar.id,
                            allDay = parsed.allDay,
                        )
                        if (existing == null) database.insertEvent(event) else database.updateEvent(event)
                        pulled++
                    }
                    database.updateCalendarCTag(calendar.id, cTag)
                }
            }

            SyncReport(
                success = true,
                message = buildString {
                    append("Sync complete")
                    if (pushed > 0) append(" · $pushed uploaded")
                    if (pulled > 0) append(" · $pulled downloaded")
                    if (deletions > 0) append(" · $deletions deleted")
                },
            )
        } catch (exception: Exception) {
            Log.e(TAG, "CalDAV sync failed", exception)
            SyncReport(false, "Sync failed: ${exception.message}")
        } finally {
            client.close()
        }
    }

    private companion object {
        const val TAG = "SyncManager"
    }
}
