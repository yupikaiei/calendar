package com.frelsical.nativeapp.sync

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SyncScheduleTest {

    private val now = 1_000_000_000_000L

    @Test
    fun syncsWhenItHasNeverSynced() {
        assertTrue(shouldAutoSync(lastSyncFinishedAt = 0L))
    }

    @Test
    fun skipsWhileTheLastSyncIsRecent() {
        assertFalse(
            shouldAutoSync(
                lastSyncFinishedAt = now - 60_000L,
            ),
        )
    }

    @Test
    fun syncsAfterTheMinimumInterval() {
        assertTrue(
            shouldAutoSync(
                lastSyncFinishedAt = now - SyncSchedule.MIN_INTERVAL_MS,
            ),
        )
    }

    @Test
    fun waitsLongerAfterAFailure() {
        assertFalse(
            shouldAutoSync(
                lastSyncFinishedAt = now - SyncSchedule.MIN_INTERVAL_MS,
                lastSyncFailed = true,
            ),
        )
        assertTrue(
            shouldAutoSync(
                lastSyncFinishedAt = now - SyncSchedule.FAILURE_RETRY_INTERVAL_MS,
                lastSyncFailed = true,
            ),
        )
    }

    @Test
    fun skipsWhenNotConfiguredOrOffline() {
        assertFalse(shouldAutoSync(configured = false, lastSyncFinishedAt = 0L))
        assertFalse(shouldAutoSync(hasNetwork = false, lastSyncFinishedAt = 0L))
    }

    @Test
    fun syncsWhenTheClockMovedBackwards() {
        assertTrue(shouldAutoSync(lastSyncFinishedAt = now + 60_000L))
    }

    private fun shouldAutoSync(
        configured: Boolean = true,
        hasNetwork: Boolean = true,
        lastSyncFinishedAt: Long,
        lastSyncFailed: Boolean = false,
    ) = SyncSchedule.shouldAutoSync(
        configured = configured,
        hasNetwork = hasNetwork,
        now = now,
        lastSyncFinishedAt = lastSyncFinishedAt,
        lastSyncFailed = lastSyncFailed,
    )
}
