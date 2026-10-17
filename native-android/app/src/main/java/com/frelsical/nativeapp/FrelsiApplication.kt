package com.frelsical.nativeapp

import android.app.Application
import com.frelsical.nativeapp.data.CalendarDatabase
import com.frelsical.nativeapp.data.EventRepository
import com.frelsical.nativeapp.notify.ReminderScheduler
import com.frelsical.nativeapp.settings.SecureStore
import com.frelsical.nativeapp.settings.SettingsStore
import com.frelsical.nativeapp.sync.SyncManager

class FrelsiApplication : Application() {

    val database: CalendarDatabase by lazy { CalendarDatabase(this) }
    val settings: SettingsStore by lazy { SettingsStore(this) }
    val secureStore: SecureStore by lazy { SecureStore(this) }
    val repository: EventRepository by lazy { EventRepository(this, database) }
    val syncManager: SyncManager by lazy { SyncManager(database, settings, secureStore) }
    val reminderScheduler: ReminderScheduler by lazy { ReminderScheduler(this) }

    override fun onCreate() {
        super.onCreate()
        ReminderScheduler.ensureChannel(this)
    }
}
