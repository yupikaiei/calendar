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
}
