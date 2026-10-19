package com.frelsical.nativeapp.settings

import android.content.Context
import androidx.core.content.edit

class SettingsStore(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    var serverUrl: String
        get() = prefs.getString(KEY_SERVER_URL, "")?.trim().orEmpty()
        set(value) = prefs.edit { putString(KEY_SERVER_URL, value.trim()) }

    var username: String
        get() = prefs.getString(KEY_USERNAME, "")?.trim().orEmpty()
        set(value) = prefs.edit { putString(KEY_USERNAME, value.trim()) }

    var allDayMigrationVersion: Int
        get() = prefs.getInt(KEY_ALL_DAY_MIGRATION_VERSION, 0)
        set(value) = prefs.edit { putInt(KEY_ALL_DAY_MIGRATION_VERSION, value) }

    var secondaryTimezone: String?
        get() = prefs.getString(KEY_SECONDARY_TIMEZONE, null)?.takeIf { it.isNotBlank() }
        set(value) = prefs.edit {
            if (value.isNullOrBlank()) remove(KEY_SECONDARY_TIMEZONE)
            else putString(KEY_SECONDARY_TIMEZONE, value)
        }

    val isCalDavConfigured: Boolean
        get() = serverUrl.isNotBlank() && username.isNotBlank()

    private companion object {
        const val PREFS_NAME = "frelsi_settings"
        const val KEY_SERVER_URL = "server_url"
        const val KEY_USERNAME = "username"
        const val KEY_SECONDARY_TIMEZONE = "secondary_timezone"
        const val KEY_ALL_DAY_MIGRATION_VERSION = "all_day_migration_version"
    }
}
