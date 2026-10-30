package com.frelsical.nativeapp.external

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset

class ExternalEventParserTest {

    private val zone = ZoneId.of("America/New_York")

    @Test
    fun `maps timed event extras`() {
        val start = 1_790_000_000_000L
        val end = start + 90 * 60 * 1000L

        val draft = ExternalEventParser.draftFromExtras(
            mapOf(
                ExternalEventParser.EXTRA_TITLE to "Dentist",
                ExternalEventParser.EXTRA_DESCRIPTION to "Bring the referral",
                ExternalEventParser.EXTRA_LOCATION to "Main Street 4",
                ExternalEventParser.EXTRA_BEGIN_TIME to start,
                ExternalEventParser.EXTRA_END_TIME to end,
                ExternalEventParser.EXTRA_RRULE to "FREQ=MONTHLY",
            ),
            zone = zone,
        )

        assertEquals("Dentist", draft.title)
        assertEquals("Bring the referral", draft.description)
        assertEquals("Main Street 4", draft.location)
        assertEquals(start, draft.start)
        assertEquals(end, draft.end)
        assertEquals(false, draft.allDay)
        assertEquals("FREQ=MONTHLY", draft.recurrenceRule)
    }

    @Test
    fun `converts all-day UTC midnight to local midnight`() {
        val utcStart = LocalDate.of(2026, 10, 29).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
        val utcEnd = LocalDate.of(2026, 10, 30).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()

        val draft = ExternalEventParser.draftFromExtras(
            mapOf(
                ExternalEventParser.EXTRA_ALL_DAY to true,
                ExternalEventParser.EXTRA_BEGIN_TIME to utcStart,
                ExternalEventParser.EXTRA_END_TIME to utcEnd,
            ),
            zone = zone,
        )

        assertEquals(true, draft.allDay)
        assertEquals(LocalDate.of(2026, 10, 29).atStartOfDay(zone).toInstant().toEpochMilli(), draft.start)
        assertEquals(LocalDate.of(2026, 10, 30).atStartOfDay(zone).toInstant().toEpochMilli(), draft.end)
    }

    @Test
    fun `accepts string millis and ISO timestamps`() {
        val fromMillis = ExternalEventParser.draftFromExtras(
            mapOf(ExternalEventParser.EXTRA_BEGIN_TIME to "1790000000000"),
            zone = zone,
        )
        assertEquals(1_790_000_000_000L, fromMillis.start)

        val fromIso = ExternalEventParser.draftFromExtras(
            mapOf(ExternalEventParser.EXTRA_BEGIN_TIME to "2026-10-29T10:15:00Z"),
            zone = zone,
        )
        assertEquals(1_793_268_900_000L, fromIso.start)
    }

    @Test
    fun `falls back to an hour when end is missing or invalid`() {
        val start = 1_790_000_000_000L

        val missingEnd = ExternalEventParser.draftFromExtras(
            mapOf(ExternalEventParser.EXTRA_BEGIN_TIME to start),
            zone = zone,
        )
        assertEquals(start + 60 * 60 * 1000L, missingEnd.end)

        val earlierEnd = ExternalEventParser.draftFromExtras(
            mapOf(
                ExternalEventParser.EXTRA_BEGIN_TIME to start,
                ExternalEventParser.EXTRA_END_TIME to start - 5_000L,
            ),
            zone = zone,
        )
        assertEquals(start + 60 * 60 * 1000L, earlierEnd.end)
    }

    @Test
    fun `uses default title and now when extras are absent`() {
        val now = 1_790_000_000_000L
        val draft = ExternalEventParser.draftFromExtras(
            mapOf(ExternalEventParser.EXTRA_ANDROID_TITLE to "From share sheet"),
            now = now,
            zone = zone,
        )

        assertEquals("From share sheet", draft.title)
        assertEquals(now, draft.start)
        assertEquals(now + 60 * 60 * 1000L, draft.end)
        assertNull(draft.description)
        assertNull(draft.location)
    }

    @Test
    fun `blank optional extras become null`() {
        val draft = ExternalEventParser.draftFromExtras(
            mapOf(
                ExternalEventParser.EXTRA_TITLE to "  ",
                ExternalEventParser.EXTRA_DESCRIPTION to " ",
                ExternalEventParser.EXTRA_LOCATION to "",
                ExternalEventParser.EXTRA_RRULE to "  ",
            ),
            zone = zone,
        )

        assertEquals("", draft.title)
        assertNull(draft.description)
        assertNull(draft.location)
        assertNull(draft.recurrenceRule)
    }
}
