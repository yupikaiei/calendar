package com.frelsical.nativeapp.ical

import com.frelsical.nativeapp.data.Event
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

class IcsParserTest {

    private val utc = ZoneId.of("UTC")

    @Test
    fun parsesTimedEvent() {
        val ics = """
            BEGIN:VCALENDAR
            VERSION:2.0
            BEGIN:VEVENT
            UID:event-1
            SUMMARY:Team meeting
            DTSTART:20260101T100000Z
            DTEND:20260101T110000Z
            DESCRIPTION:Agenda line 1\nAgenda line 2
            LOCATION:Room 4
            RRULE:FREQ=WEEKLY;COUNT=3
            END:VEVENT
            END:VCALENDAR
        """.trimIndent()

        val event = IcsParser.parseEvent(ics, utc)

        assertNotNull(event)
        assertEquals("event-1", event!!.uid)
        assertEquals("Team meeting", event.title)
        assertEquals(Instant.parse("2026-01-01T10:00:00Z").toEpochMilli(), event.start)
        assertEquals(Instant.parse("2026-01-01T11:00:00Z").toEpochMilli(), event.end)
        assertEquals("Agenda line 1\nAgenda line 2", event.description)
        assertEquals("Room 4", event.location)
        assertEquals("FREQ=WEEKLY;COUNT=3", event.recurrenceRule)
        assertFalse(event.allDay)
    }

    @Test
    fun parsesAllDayEvent() {
        val ics = """
            BEGIN:VCALENDAR
            BEGIN:VEVENT
            UID:all-day-1
            SUMMARY:Conference
            DTSTART;VALUE=DATE:20260410
            DTEND;VALUE=DATE:20260412
            END:VEVENT
            END:VCALENDAR
        """.trimIndent()

        val event = IcsParser.parseEvent(ics, utc)!!

        assertTrue(event.allDay)
        assertEquals(LocalDate.of(2026, 4, 10).atStartOfDay(utc).toInstant().toEpochMilli(), event.start)
        assertEquals(LocalDate.of(2026, 4, 12).atStartOfDay(utc).toInstant().toEpochMilli(), event.end)
    }

    @Test
    fun unfoldsContinuationLines() {
        val ics = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:folded\r\n" +
            "SUMMARY:A very long title that has been folded by the exporter \r\n" +
            " and continues here\r\nDTSTART:20260101T100000Z\r\n" +
            "DTEND:20260101T110000Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

        val event = IcsParser.parseEvent(ics, utc)!!

        assertEquals(
            "A very long title that has been folded by the exporter and continues here",
            event.title,
        )
    }

    @Test
    fun parsesMultipleEvents() {
        val ics = """
            BEGIN:VCALENDAR
            BEGIN:VEVENT
            UID:one
            SUMMARY:One
            DTSTART:20260101T100000Z
            DTEND:20260101T110000Z
            END:VEVENT
            BEGIN:VEVENT
            UID:two
            SUMMARY:Two
            DTSTART:20260102T100000Z
            DTEND:20260102T110000Z
            END:VEVENT
            END:VCALENDAR
        """.trimIndent()

        val events = IcsParser.parseEvents(ics, utc)

        assertEquals(2, events.size)
        assertEquals(listOf("one", "two"), events.map { it.uid })
    }

    @Test
    fun generatesAndParsesRoundTrip() {
        val allDayEvent = Event(
            uid = "round-trip",
            title = "Planning; Q1, review",
            start = LocalDate.of(2026, 5, 1).atStartOfDay(utc).toInstant().toEpochMilli(),
            end = LocalDate.of(2026, 5, 2).atStartOfDay(utc).toInstant().toEpochMilli(),
            description = "Line one\nLine two",
            location = "HQ",
            recurrenceRule = "FREQ=YEARLY",
            allDay = true,
        )

        val ics = IcsParser.generateIcs(allDayEvent, utc)

        assertTrue(ics.contains("DTSTART;VALUE=DATE:20260501"))
        assertTrue(ics.contains("DTEND;VALUE=DATE:20260502"))
        assertTrue(ics.contains("SUMMARY:Planning\\; Q1\\, review"))

        val parsed = IcsParser.parseEvent(ics, utc)!!
        assertEquals(allDayEvent.uid, parsed.uid)
        assertEquals(allDayEvent.title, parsed.title)
        assertEquals(allDayEvent.start, parsed.start)
        assertEquals(allDayEvent.end, parsed.end)
        assertEquals(allDayEvent.description, parsed.description)
        assertEquals(allDayEvent.location, parsed.location)
        assertEquals(allDayEvent.recurrenceRule, parsed.recurrenceRule)
        assertTrue(parsed.allDay)
    }

    @Test
    fun generatesUtcTimesForTimedEvents() {
        val event = Event(
            uid = "timed",
            title = "Lunch",
            start = Instant.parse("2026-02-03T12:30:00Z").toEpochMilli(),
            end = Instant.parse("2026-02-03T13:30:00Z").toEpochMilli(),
        )

        val ics = IcsParser.generateIcs(event, utc)

        assertTrue(ics.contains("DTSTART:20260203T123000Z"))
        assertTrue(ics.contains("DTEND:20260203T133000Z"))
        assertNull(IcsParser.parseEvent(ics, utc)!!.recurrenceRule)
    }

    @Test
    fun ignoresNestedAlarmProperties() {
        val ics = """
            BEGIN:VCALENDAR
            BEGIN:VEVENT
            UID:with-alarm
            SUMMARY:Standup
            DTSTART:20260101T100000Z
            DTEND:20260101T110000Z
            BEGIN:VALARM
            ACTION:DISPLAY
            DESCRIPTION:Alarm text, not the event description
            TRIGGER:-PT10M
            END:VALARM
            END:VEVENT
            END:VCALENDAR
        """.trimIndent()

        val event = IcsParser.parseEvent(ics, utc)!!

        assertEquals("Standup", event.title)
        assertNull(event.description)
    }

    @Test
    fun generatesUidWhenMissing() {
        val ics = """
            BEGIN:VCALENDAR
            BEGIN:VEVENT
            SUMMARY:No UID
            DTSTART;VALUE=DATE:20260101
            END:VEVENT
            END:VCALENDAR
        """.trimIndent()

        val event = IcsParser.parseEvent(ics, utc)!!

        assertTrue(event.uid.isNotBlank())
        assertEquals(LocalDate.of(2026, 1, 2).atStartOfDay(utc).toInstant().toEpochMilli(), event.end)
    }

    @Test
    fun parsesExcludedDates() {
        val ics = """
            BEGIN:VCALENDAR
            BEGIN:VEVENT
            UID:exdate-timed
            SUMMARY:Series
            DTSTART:20260101T100000Z
            DTEND:20260101T110000Z
            RRULE:FREQ=DAILY;COUNT=3
            EXDATE:20260102T100000Z
            END:VEVENT
            END:VCALENDAR
        """.trimIndent()

        val event = IcsParser.parseEvent(ics, utc)!!

        assertEquals(
            setOf(Instant.parse("2026-01-02T10:00:00Z").toEpochMilli()),
            event.excludedStarts,
        )
    }

    @Test
    fun parsesAllDayExcludedDates() {
        val ics = """
            BEGIN:VCALENDAR
            BEGIN:VEVENT
            UID:exdate-all-day
            SUMMARY:All day series
            DTSTART;VALUE=DATE:20260101
            DTEND;VALUE=DATE:20260102
            RRULE:FREQ=DAILY;COUNT=3
            EXDATE;VALUE=DATE:20260102
            END:VEVENT
            END:VCALENDAR
        """.trimIndent()

        val event = IcsParser.parseEvent(ics, utc)!!

        assertTrue(event.allDay)
        assertEquals(
            setOf(LocalDate.of(2026, 1, 2).atStartOfDay(utc).toInstant().toEpochMilli()),
            event.excludedStarts,
        )
    }

    @Test
    fun generatesExcludedDates() {
        val excluded = Instant.parse("2026-01-02T10:00:00Z").toEpochMilli()
        val timed = Event(
            uid = "exdate-generate",
            title = "Series",
            start = Instant.parse("2026-01-01T10:00:00Z").toEpochMilli(),
            end = Instant.parse("2026-01-01T11:00:00Z").toEpochMilli(),
            recurrenceRule = "FREQ=DAILY;COUNT=3",
            excludedStarts = setOf(excluded),
        )

        val ics = IcsParser.generateIcs(timed, utc)

        assertTrue(ics.contains("EXDATE:20260102T100000Z"))
        assertEquals(setOf(excluded), IcsParser.parseEvent(ics, utc)!!.excludedStarts)

        val allDayExcluded = LocalDate.of(2026, 2, 2)
            .atStartOfDay(utc).toInstant().toEpochMilli()
        val allDay = Event(
            uid = "exdate-all-day-generate",
            title = "All day series",
            start = LocalDate.of(2026, 2, 1).atStartOfDay(utc).toInstant().toEpochMilli(),
            end = LocalDate.of(2026, 2, 2).atStartOfDay(utc).toInstant().toEpochMilli(),
            recurrenceRule = "FREQ=DAILY",
            allDay = true,
            excludedStarts = setOf(allDayExcluded),
        )

        val allDayIcs = IcsParser.generateIcs(allDay, utc)
        assertTrue(allDayIcs.contains("EXDATE;VALUE=DATE:20260202"))
        assertEquals(setOf(allDayExcluded), IcsParser.parseEvent(allDayIcs, utc)!!.excludedStarts)
    }

    @Test
    fun normalizesCentralEuropeanMidnightBirthdayToAllDay() {
        val zone = ZoneId.of("Europe/Berlin")
        val event = birthdayEvent(
            start = "2023-05-14T22:00:00Z",
            end = "2023-05-15T22:00:00Z",
            rule = "FREQ=YEARLY",
        )

        val normalized = IcsParser.normalizeAllDayImport(event, zone)

        assertTrue(normalized.allDay)
        assertEquals(LocalDate.of(2023, 5, 15), localDate(normalized.start, zone))
        assertEquals(LocalDate.of(2023, 5, 16), localDate(normalized.end, zone))
        assertEquals(LocalDate.of(2023, 5, 15).atStartOfDay(zone).toInstant().toEpochMilli(), normalized.start)
    }

    @Test
    fun normalizesWinterMidnightForWesternDevice() {
        val zone = ZoneId.of("America/Sao_Paulo")
        val event = birthdayEvent(
            start = "2008-02-19T23:00:00Z",
            end = "2008-02-20T23:00:00Z",
        )

        val normalized = IcsParser.normalizeAllDayImport(event, zone)

        assertTrue(normalized.allDay)
        assertEquals(LocalDate.of(2008, 2, 20), localDate(normalized.start, zone))
        assertEquals(LocalDate.of(2008, 2, 21), localDate(normalized.end, zone))
    }

    @Test
    fun keepsWholeDayEventSpanningTwoDays() {
        val event = birthdayEvent(
            start = "2023-05-14T22:00:00Z",
            end = "2023-05-16T22:00:00Z",
        )

        val normalized = IcsParser.normalizeAllDayImport(event, utc)

        assertTrue(normalized.allDay)
        assertEquals(2 * 86_400_000L, normalized.end - normalized.start)
    }

    @Test
    fun normalizesExcludedBirthdayDates() {
        val excluded = Instant.parse("2024-05-14T22:00:00Z").toEpochMilli()
        val event = birthdayEvent(
            start = "2023-05-14T22:00:00Z",
            end = "2023-05-15T22:00:00Z",
            rule = "FREQ=YEARLY",
            excluded = setOf(excluded),
        )

        val normalized = IcsParser.normalizeAllDayImport(event, utc)

        assertEquals(
            setOf(Instant.parse("2024-05-15T00:00:00Z").toEpochMilli()),
            normalized.excludedStarts,
        )
    }

    @Test
    fun leavesAfternoonAndShortEventsTimed() {
        val afternoon = birthdayEvent(
            start = "2024-01-01T15:00:00Z",
            end = "2024-01-02T15:00:00Z",
        )
        val short = birthdayEvent(
            start = "2024-01-01T22:00:00Z",
            end = "2024-01-01T23:00:00Z",
        )

        assertFalse(IcsParser.normalizeAllDayImport(afternoon, utc).allDay)
        assertFalse(IcsParser.normalizeAllDayImport(short, utc).allDay)
    }

    @Test
    fun leavesExistingAllDayEventUntouched() {
        val event = ParsedEvent(
            uid = "all-day",
            title = "All day",
            start = LocalDate.of(2026, 1, 1).atStartOfDay(utc).toInstant().toEpochMilli(),
            end = LocalDate.of(2026, 1, 2).atStartOfDay(utc).toInstant().toEpochMilli(),
            allDay = true,
            description = null,
            location = null,
            recurrenceRule = null,
        )

        assertEquals(event, IcsParser.normalizeAllDayImport(event, utc))
    }

    private fun birthdayEvent(
        start: String,
        end: String,
        rule: String? = null,
        excluded: Set<Long> = emptySet(),
    ) = ParsedEvent(
        uid = "birthday",
        title = "Birthday",
        start = Instant.parse(start).toEpochMilli(),
        end = Instant.parse(end).toEpochMilli(),
        allDay = false,
        description = null,
        location = null,
        recurrenceRule = rule,
        excludedStarts = excluded,
    )

    private fun localDate(millis: Long, zone: ZoneId): LocalDate =
        Instant.ofEpochMilli(millis).atZone(zone).toLocalDate()
}
