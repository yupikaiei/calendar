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
import com.frelsical.nativeapp.ui.theme.calendarColorHex
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
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

    val calDavServerUrl: String get() = settings.serverUrl
    val calDavUsername: String get() = settings.username

    suspend fun readStoredPassword(): String = kotlinx.coroutines.withContext(
        kotlinx.coroutines.Dispatchers.IO,
    ) { secureStore.readPassword() }

    private val _syncing = MutableStateFlow(false)
    val syncing = _syncing.asStateFlow()

    private val _secondaryTimezone = MutableStateFlow(settings.secondaryTimezone)
    val secondaryTimezone = _secondaryTimezone.asStateFlow()

    private val _messages = MutableSharedFlow<String>(extraBufferCapacity = 8)
    val messages = _messages.asSharedFlow()

    init {
        viewModelScope.launch { repository.reload() }
        rescheduleReminders()
    }

    fun sync(showMessage: Boolean = true) {
        if (!_syncing.compareAndSet(expect = false, update = true)) return
        viewModelScope.launch {
            try {
                val report = syncManager.performSync()
                repository.reload()
                if (showMessage || (!report.success && settings.isCalDavConfigured)) {
                    _messages.tryEmit(report.message)
                }
            } finally {
                _syncing.value = false
                rescheduleReminders()
            }
        }
    }

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
            try {
                val slug = name.lowercase()
                    .replace(Regex("[^a-z0-9]+"), "-")
                    .trim('-')
                    .ifBlank { "calendar" }
                val path = "/${settings.username}/$slug/"
                if (client.createCalendar(path, name)) {
                    _messages.tryEmit("Calendar \"$name\" created")
                    val report = syncManager.performSync()
                    repository.reload()
                    if (!report.success) _messages.tryEmit(report.message)
                } else {
                    _messages.tryEmit("Failed to create the calendar on the server.")
                }
            } finally {
                client.close()
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
}
