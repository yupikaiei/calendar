package com.frelsical.nativeapp.sync

/**
 * Throttling rules for syncs that are not requested by the user. The last sync
 * time is persisted, so reopening the app does not start another sync and a
 * failing server is retried with a longer pause instead of on every resume.
 */
object SyncSchedule {

    const val MIN_INTERVAL_MS = 5 * 60_000L
    const val FAILURE_RETRY_INTERVAL_MS = 15 * 60_000L

    fun shouldAutoSync(
        configured: Boolean,
        hasNetwork: Boolean,
        now: Long,
        lastSyncFinishedAt: Long,
        lastSyncFailed: Boolean,
    ): Boolean {
        if (!configured || !hasNetwork) return false
        if (lastSyncFinishedAt <= 0L) return true
        // A clock change can move "now" behind the stored timestamp; sync then.
        if (now < lastSyncFinishedAt) return true
        val interval = if (lastSyncFailed) FAILURE_RETRY_INTERVAL_MS else MIN_INTERVAL_MS
        return now - lastSyncFinishedAt >= interval
    }
}
