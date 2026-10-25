package com.frelsical.nativeapp.ui

import android.app.AlarmManager
import android.app.Application
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.frelsical.nativeapp.FrelsiApplication
import com.frelsical.nativeapp.data.CalendarRecord
import com.frelsical.nativeapp.data.Event
import com.frelsical.nativeapp.network.CalDavClient
import com.frelsical.nativeapp.sync.SyncReport
import com.frelsical.nativeapp.sync.SyncSchedule
import com.frelsical.nativeapp.ui.theme.calendarColorHex
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import androidx.compose.ui.graphics.Color

class CalendarViewModel(application: Application) : AndroidViewModel(application) {

    private val app = application as FrelsiApplication
    private val repository = app.repository
    private val settings = app.settings
    private val secureStore = app.secureStore
    private val syncManager = app.syncManager
    private val scheduler = app.reminderScheduler

    val events = repository.events
    val calendars = repository.calendars
    val eventsLoaded = repository.loaded

    val calDavServerUrl: String get() = settings.serverUrl
    val calDavUsername: String get() = settings.username

    suspend fun readStoredPassword(): String = kotlinx.coroutines.withContext(
        kotlinx.coroutines.Dispatchers.IO,
    ) { secureStore.readPassword() }

    private val _syncing = MutableStateFlow(false)
    val syncing = _syncing.asStateFlow()

    private val _syncStatus = MutableStateFlow<String?>(null)
    val syncStatus = _syncStatus.asStateFlow()

    private val _secondaryTimezone = MutableStateFlow(settings.secondaryTimezone)
    val secondaryTimezone = _secondaryTimezone.asStateFlow()

    private val _messages = MutableSharedFlow<String>(extraBufferCapacity = 8)
    val messages = _messages.asSharedFlow()

    init {
        viewModelScope.launch {
            if (settings.allDayMigrationVersion < ALL_DAY_MIGRATION_VERSION) {
                repository.normalizeStoredAllDayEvents()
                settings.allDayMigrationVersion = ALL_DAY_MIGRATION_VERSION
            }
            repository.reload()
            rescheduleReminders()
        }
    }

    private val syncInFlight = java.util.concurrent.atomic.AtomicBoolean(false)

    /**
     * [showIndicator] is false for automatic syncs, which should not flash the
     * progress bar every time the app comes back to the foreground.
     */
    fun sync(showMessage: Boolean = true, force: Boolean = true, showIndicator: Boolean = true) {
        if (!settings.isCalDavConfigured) {
            if (showMessage) _messages.tryEmit("Add your CalDAV server details in Settings first.")
            return
        }
        if (!force && !SyncSchedule.shouldAutoSync(
                configured = settings.isCalDavConfigured,
                hasNetwork = hasNetwork(),
                now = System.currentTimeMillis(),
                lastSyncFinishedAt = settings.lastSyncFinishedAt,
                lastSyncFailed = settings.lastSyncFailed,
            )
        ) {
            return
        }
        if (!syncInFlight.compareAndSet(false, true)) return
        if (showIndicator) {
            _syncing.value = true
            _syncStatus.value = "Syncing\u2026"
        }
        viewModelScope.launch {
            var succeeded = false
            var cancelled = false
            try {
                val report = withTimeoutOrNull(SYNC_TIMEOUT_MS) {
                    syncManager.performSync { message ->
                        if (showIndicator) _syncStatus.value = message
                    }
                } ?: SyncReport(
                        success = false,
                        message = "Sync timed out. Check that the server is reachable and try again.",
                    )
                succeeded = report.success
                repository.reload()
                if (showMessage || !report.success) {
                    _messages.tryEmit(report.message)
                }
            } catch (exception: CancellationException) {
                cancelled = true
                throw exception
            } catch (exception: Exception) {
                _messages.tryEmit("Sync failed: ${exception.message}")
            } finally {
                // A cancelled sync says nothing about the server, so it must not
                // start the failure back-off.
                if (!cancelled) {
                    settings.lastSyncFinishedAt = System.currentTimeMillis()
                    settings.lastSyncFailed = !succeeded
                }
                syncInFlight.set(false)
                _syncStatus.value = null
                _syncing.value = false
                rescheduleReminders()
            }
        }
    }

    fun autoSync() = sync(showMessage = false, force = false, showIndicator = false)

    fun saveEvent(event: Event, reminderMinutes: List<Int>, previousReminders: List<Int>) {
        viewModelScope.launch {
            if (event.id != 0L) {
                scheduler.cancelAll(event.id, previousReminders)
            }
            val saved = repository.saveEvent(event, reminderMinutes)
            reminderMinutes.forEach { scheduler.scheduleNext(saved, it) }
            _messages.tryEmit(if (event.id == 0L) "Event created" else "Event updated")
        }
    }

    fun deleteEvent(event: Event, reminderMinutes: List<Int>) {
        viewModelScope.launch {
            scheduler.cancelAll(event.id, reminderMinutes)
            repository.deleteEvent(event)
            _messages.tryEmit("Event deleted")
        }
    }

    /**
     * Saves a single occurrence as an independent event and excludes it from the
     * recurring series.
     */
    fun saveOccurrence(
        baseEvent: Event,
        occurrenceStart: Long,
        editedEvent: Event,
        reminderMinutes: List<Int>,
    ) {
        viewModelScope.launch {
            val saved = repository.saveEvent(editedEvent, reminderMinutes)
            repository.addRecurrenceException(baseEvent.id, occurrenceStart)
            reminderMinutes.forEach { scheduler.scheduleNext(saved, it) }
            rescheduleReminders()
            _messages.tryEmit("Occurrence updated")
        }
    }

    fun deleteOccurrence(baseEvent: Event, occurrenceStart: Long) {
        viewModelScope.launch {
            repository.addRecurrenceException(baseEvent.id, occurrenceStart)
            rescheduleReminders()
            _messages.tryEmit("Occurrence deleted")
        }
    }

    fun saveCalDavSettings(serverUrl: String, username: String, password: String) {
        settings.serverUrl = serverUrl
        settings.username = username
        secureStore.writePassword(password)
        _messages.tryEmit("Settings saved")
        sync(showMessage = false)
    }

    fun testConnection(serverUrl: String, username: String, password: String) {
        if (serverUrl.isBlank() || username.isBlank()) {
            _messages.tryEmit("Enter the server URL and username first.")
            return
        }
        viewModelScope.launch {
            _messages.tryEmit("Testing connection\u2026")
            val client = try {
                CalDavClient(serverUrl, username.trim(), password)
            } catch (exception: Exception) {
                _messages.tryEmit("Invalid server URL: ${exception.message}")
                return@launch
            }
            try {
                val result = client.testConnection("/${username.trim()}/")
                _messages.tryEmit(result.message)
            } finally {
                client.close()
            }
        }
    }

    fun setSecondaryTimezone(timezone: String?) {
        settings.secondaryTimezone = timezone
        _secondaryTimezone.value = timezone
    }

    fun createCalendar(name: String) {
        if (name.isBlank()) return
        if (!settings.isCalDavConfigured) {
            _messages.tryEmit("Configure your CalDAV server first.")
            return
        }
        viewModelScope.launch {
            val client = openClient() ?: return@launch
            val slug = name.lowercase()
                .replace(Regex("[^a-z0-9]+"), "-")
                .trim('-')
                .ifBlank { "calendar" }
            val path = "/${settings.username}/$slug/"
            val created = try {
                client.createCalendar(path, name)
            } finally {
                client.close()
            }
            if (created) {
                _messages.tryEmit("Calendar \"$name\" created")
                sync(showMessage = false)
            } else {
                _messages.tryEmit("Failed to create the calendar on the server.")
            }
        }
    }

    fun renameCalendar(calendar: CalendarRecord, newName: String) {
        if (newName.isBlank() || newName == calendar.displayName) return
        viewModelScope.launch {
            if (calendar.urlPath.startsWith("/local/")) {
                repository.updateCalendarName(calendar.id, newName)
                _messages.tryEmit("Calendar renamed")
                return@launch
            }
            val client = openClient() ?: return@launch
            try {
                if (client.updateCalendarName(calendar.urlPath, newName)) {
                    repository.updateCalendarName(calendar.id, newName)
                    _messages.tryEmit("Calendar renamed")
                } else {
                    _messages.tryEmit("Failed to rename the calendar on the server.")
                }
            } finally {
                client.close()
            }
        }
    }

    fun updateCalendarColor(calendar: CalendarRecord, color: Color) {
        val hex = calendarColorHex(color)
        viewModelScope.launch {
            if (calendar.urlPath.startsWith("/local/")) {
                repository.updateCalendarColor(calendar.id, hex)
                return@launch
            }
            val client = openClient() ?: return@launch
            try {
                if (client.updateCalendarColor(calendar.urlPath, hex)) {
                    repository.updateCalendarColor(calendar.id, hex)
                    _messages.tryEmit("Calendar color updated")
                } else {
                    _messages.tryEmit("Failed to update the color on the server.")
                }
            } finally {
                client.close()
            }
        }
    }

    fun deleteCalendar(calendar: CalendarRecord) {
        viewModelScope.launch {
            // Cancel alarms for events that are about to be cascaded away.
            events.value
                .filter { it.event.calendarId == calendar.id }
                .forEach { item ->
                    val reminders = repository.getReminderMinutes(item.event.id)
                    scheduler.cancelAll(item.event.id, reminders)
                }

            if (!calendar.urlPath.startsWith("/local/")) {
                val client = openClient() ?: return@launch
                try {
                    if (!client.deleteCalendar(calendar.urlPath)) {
                        _messages.tryEmit("Failed to delete the calendar on the server.")
                        return@launch
                    }
                } finally {
                    client.close()
                }
            }
            repository.deleteCalendar(calendar.id)
            _messages.tryEmit("Calendar deleted")
        }
    }

    fun importIcs(uri: Uri) {
        viewModelScope.launch {
            val result = repository.importIcs(uri)
            _messages.tryEmit(result.message)
        }
    }

    fun canScheduleExactAlarms(): Boolean {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.S) return true
        val manager = getApplication<Application>().getSystemService(AlarmManager::class.java)
        return manager?.canScheduleExactAlarms() ?: true
    }

    fun notify(message: String) {
        _messages.tryEmit(message)
    }

    private fun rescheduleReminders() {
        viewModelScope.launch(kotlinx.coroutines.Dispatchers.IO) {
            app.database.getEventWithReminders().forEach { item ->
                item.reminderMinutes.forEach { minutes ->
                    scheduler.scheduleNext(item.event, minutes)
                }
            }
        }
    }

    suspend fun remindersFor(eventId: Long): List<Int> = repository.getReminderMinutes(eventId)

    private fun hasNetwork(): Boolean {
        val manager = getApplication<Application>()
            .getSystemService(android.net.ConnectivityManager::class.java) ?: return true
        return manager.activeNetwork != null
    }

    private fun openClient(): CalDavClient? {
        if (!settings.isCalDavConfigured) {
            _messages.tryEmit("Configure your CalDAV server first.")
            return null
        }
        return try {
            CalDavClient(settings.serverUrl, settings.username, secureStore.readPassword())
        } catch (exception: Exception) {
            _messages.tryEmit("Invalid server URL: ${exception.message}")
            null
        }
    }

    private companion object {
        const val SYNC_TIMEOUT_MS = 300_000L
        const val ALL_DAY_MIGRATION_VERSION = 1
    }
}
