package com.frelsical.nativeapp.ical

import com.frelsical.nativeapp.data.Event
import com.frelsical.nativeapp.data.EventWithCalendar
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

class RecurrenceExpanderTest {

    private val utc = ZoneId.of("UTC")

    @Test
    fun expandsDailyOccurrencesWithCount() {
        val event = timedEvent(
            start = "2026-01-01T10:00:00Z",
            end = "2026-01-01T11:00:00Z",
            rule = "FREQ=DAILY;COUNT=3",
        )

        val result = RecurrenceExpander.expand(
            events = listOf(EventWithCalendar(event, null)),
            windowStart = Instant.parse("2025-12-01T00:00:00Z"),
            windowEnd = Instant.parse("2026-02-01T00:00:00Z"),
            zone = utc,
        )

        val dates = result.keys.filter { it.year == 2026 && it.monthValue == 1 }.sorted()
        assertEquals(listOf(LocalDate.of(2026, 1, 1), LocalDate.of(2026, 1, 2), LocalDate.of(2026, 1, 3)), dates)
        for (date in dates) {
            val occurrence = result.getValue(date).single { it.event.uid == event.uid }
            assertEquals(10, Instant.ofEpochMilli(occurrence.start).atZone(utc).hour)
            assertEquals(11, Instant.ofEpochMilli(occurrence.end).atZone(utc).hour)
        }
    }

    @Test
    fun honoursUntil() {
        val event = timedEvent(
            start = "2026-01-01T10:00:00Z",
            end = "2026-01-01T11:00:00Z",
            rule = "FREQ=DAILY;UNTIL=20260103T235959Z",
        )

        val result = RecurrenceExpander.expand(
            events = listOf(EventWithCalendar(event, null)),
            windowStart = Instant.parse("2025-12-01T00:00:00Z"),
            windowEnd = Instant.parse("2026-02-01T00:00:00Z"),
            zone = utc,
        )

        val dates = result.keys.filter { it.year == 2026 && it.monthValue == 1 }.sorted()
        assertEquals(3, dates.size)
        assertEquals(LocalDate.of(2026, 1, 3), dates.last())
    }

    @Test
    fun expandsAllDayOccurrences() {
        val start = LocalDate.of(2026, 3, 1).atStartOfDay(utc).toInstant().toEpochMilli()
        val end = LocalDate.of(2026, 3, 2).atStartOfDay(utc).toInstant().toEpochMilli()
        val event = Event(
            uid = "all-day",
            title = "All day",
            start = start,
            end = end,
            recurrenceRule = "FREQ=DAILY;COUNT=2",
            allDay = true,
        )

        val result = RecurrenceExpander.expand(
            events = listOf(EventWithCalendar(event, null)),
            windowStart = Instant.parse("2026-02-01T00:00:00Z"),
            windowEnd = Instant.parse("2026-04-01T00:00:00Z"),
            zone = utc,
        )

        val occurrence = result.getValue(LocalDate.of(2026, 3, 2)).single { it.event.uid == "all-day" }
        assertTrue(occurrence.isRecurringInstance)
        assertEquals(
            LocalDate.of(2026, 3, 3).atStartOfDay(utc).toInstant().toEpochMilli(),
            occurrence.end,
        )
    }

    @Test
    fun limitsExpansionToTheWindow() {
        val event = timedEvent(
            start = "2020-01-01T10:00:00Z",
            end = "2020-01-01T11:00:00Z",
            rule = "FREQ=DAILY",
        )

        val windowStart = Instant.parse("2026-01-01T00:00:00Z")
        val windowEnd = Instant.parse("2026-01-05T00:00:00Z")
        val result = RecurrenceExpander.expand(
            events = listOf(EventWithCalendar(event, null)),
            windowStart = windowStart,
            windowEnd = windowEnd,
            zone = utc,
        )

        val occurrences = result.flatMap { it.value }
            .filter { it.event.uid == event.uid && it.isRecurringInstance }
        assertTrue(occurrences.isNotEmpty())
        assertTrue(occurrences.all { it.start >= windowStart.toEpochMilli() })
        assertTrue(occurrences.all { it.start <= windowEnd.toEpochMilli() })
    }

    @Test
    fun includesTodayEvenWithoutEvents() {
        val result = RecurrenceExpander.expand(
            events = emptyList(),
            windowStart = Instant.now().minusSeconds(86_400),
            windowEnd = Instant.now().plusSeconds(86_400),
            zone = utc,
        )

        assertTrue(result.containsKey(LocalDate.now(utc)))
    }

    @Test
    fun keepsBaseEventOnce() {
        val event = timedEvent(
            start = "2026-01-01T10:00:00Z",
            end = "2026-01-01T11:00:00Z",
            rule = null,
        )

        val result = RecurrenceExpander.expand(
            events = listOf(EventWithCalendar(event, null)),
            windowStart = Instant.parse("2025-12-01T00:00:00Z"),
            windowEnd = Instant.parse("2026-02-01T00:00:00Z"),
            zone = utc,
        )

        assertEquals(1, result.getValue(LocalDate.of(2026, 1, 1)).size)
    }

    private fun timedEvent(start: String, end: String, rule: String?) = Event(
        uid = "event-$start",
        title = "Event",
        start = Instant.parse(start).toEpochMilli(),
        end = Instant.parse(end).toEpochMilli(),
        recurrenceRule = rule,
    )

    @Test
    fun weeklyOccurrencesPreserveLocalTimeAcrossDst() {
        val berlin = ZoneId.of("Europe/Berlin")
        val start = java.time.LocalDateTime.of(2026, 3, 22, 9, 0)
            .atZone(berlin).toInstant().toEpochMilli()
        val end = start + 60 * 60 * 1000L
        val event = Event(
            uid = "dst-weekly",
            title = "Weekly",
            start = start,
            end = end,
            recurrenceRule = "FREQ=WEEKLY;COUNT=3",
        )

        val result = RecurrenceExpander.expand(
            events = listOf(EventWithCalendar(event, null)),
            windowStart = Instant.parse("2026-03-01T00:00:00Z"),
            windowEnd = Instant.parse("2026-05-01T00:00:00Z"),
            zone = berlin,
        )

        val occurrences = result.values.flatten()
            .filter { it.event.uid == "dst-weekly" }
            .sortedBy { it.start }
        assertEquals(3, occurrences.size)
        assertEquals(
            listOf(22, 29, 5),
            occurrences.map { Instant.ofEpochMilli(it.start).atZone(berlin).dayOfMonth },
        )
        occurrences.forEach {
            assertEquals(9, Instant.ofEpochMilli(it.start).atZone(berlin).hour)
            assertEquals(60 * 60 * 1000L, it.end - it.start)
        }
    }

    @Test
    fun allDayWeeklyStaysOnLocalDatesAcrossDst() {
        val berlin = ZoneId.of("Europe/Berlin")
        val start = java.time.LocalDate.of(2026, 3, 22).atStartOfDay(berlin)
            .toInstant().toEpochMilli()
        val end = java.time.LocalDate.of(2026, 3, 23).atStartOfDay(berlin)
            .toInstant().toEpochMilli()
        val event = Event(
            uid = "dst-all-day",
            title = "All day weekly",
            start = start,
            end = end,
            recurrenceRule = "FREQ=WEEKLY;COUNT=3",
            allDay = true,
        )

        val result = RecurrenceExpander.expand(
            events = listOf(EventWithCalendar(event, null)),
            windowStart = Instant.parse("2026-03-01T00:00:00Z"),
            windowEnd = Instant.parse("2026-05-01T00:00:00Z"),
            zone = berlin,
        )

        val occurrences = result.values.flatten()
            .filter { it.event.uid == "dst-all-day" }
            .sortedBy { it.start }
        assertEquals(
            listOf(
                java.time.LocalDate.of(2026, 3, 22),
                java.time.LocalDate.of(2026, 3, 29),
                java.time.LocalDate.of(2026, 4, 5),
            ),
            occurrences.map { it.date },
        )
        occurrences.forEach {
            assertEquals(1, java.time.temporal.ChronoUnit.DAYS.between(
                Instant.ofEpochMilli(it.start).atZone(berlin).toLocalDate(),
                Instant.ofEpochMilli(it.end).atZone(berlin).toLocalDate(),
            ))
        }
    }

    @Test
    fun countIsNotLostWhenFastForwarding() {
        val event = timedEvent(
            start = "2020-01-01T10:00:00Z",
            end = "2020-01-01T11:00:00Z",
            rule = "FREQ=DAILY;COUNT=10",
        )

        val result = RecurrenceExpander.expand(
            events = listOf(EventWithCalendar(event, null)),
            windowStart = Instant.parse("2026-01-01T00:00:00Z"),
            windowEnd = Instant.parse("2026-02-01T00:00:00Z"),
            zone = utc,
        )

        val recurring = result.values.flatten().filter { it.isRecurringInstance }
        assertTrue(recurring.isEmpty())
    }

    @Test
    fun nextOccurrenceHandlesNonRecurringEvents() {
        val event = timedEvent(
            start = "2026-01-01T10:00:00Z",
            end = "2026-01-01T11:00:00Z",
            rule = null,
        )

        assertEquals(
            Instant.parse("2026-01-01T10:00:00Z").toEpochMilli(),
            RecurrenceExpander.nextOccurrenceStart(
                event,
                Instant.parse("2025-12-31T00:00:00Z").toEpochMilli(),
                utc,
            ),
        )
        assertEquals(
            null,
            RecurrenceExpander.nextOccurrenceStart(
                event,
                Instant.parse("2026-01-02T00:00:00Z").toEpochMilli(),
                utc,
            ),
        )
    }

    @Test
    fun nextOccurrenceAdvancesThroughRecurringSeries() {
        val event = timedEvent(
            start = "2026-01-01T10:00:00Z",
            end = "2026-01-01T11:00:00Z",
            rule = "FREQ=DAILY",
        )

        assertEquals(
            Instant.parse("2026-01-04T10:00:00Z").toEpochMilli(),
            RecurrenceExpander.nextOccurrenceStart(
                event,
                Instant.parse("2026-01-03T12:00:00Z").toEpochMilli(),
                utc,
            ),
        )
    }

    @Test
    fun nextOccurrenceRespectsCountAndUntil() {
        val countLimited = timedEvent(
            start = "2026-01-01T10:00:00Z",
            end = "2026-01-01T11:00:00Z",
            rule = "FREQ=DAILY;COUNT=2",
        )
        val untilLimited = timedEvent(
            start = "2026-01-01T10:00:00Z",
            end = "2026-01-01T11:00:00Z",
            rule = "FREQ=DAILY;UNTIL=20260102T235959Z",
        )

        assertEquals(
            null,
            RecurrenceExpander.nextOccurrenceStart(
                countLimited,
                Instant.parse("2026-01-02T12:00:00Z").toEpochMilli(),
                utc,
            ),
        )
        assertEquals(
            null,
            RecurrenceExpander.nextOccurrenceStart(
                untilLimited,
                Instant.parse("2026-01-03T00:00:00Z").toEpochMilli(),
                utc,
            ),
        )
    }

    @Test
    fun nextOccurrencePreservesLocalTimeAcrossDst() {
        val berlin = ZoneId.of("Europe/Berlin")
        val start = java.time.LocalDateTime.of(2026, 3, 22, 9, 0)
            .atZone(berlin).toInstant().toEpochMilli()
        val event = Event(
            uid = "next-dst",
            title = "Weekly",
            start = start,
            end = start + 60 * 60 * 1000L,
            recurrenceRule = "FREQ=WEEKLY;COUNT=3",
        )

        val next = RecurrenceExpander.nextOccurrenceStart(
            event,
            java.time.LocalDateTime.of(2026, 3, 28, 0, 0)
                .atZone(berlin).toInstant().toEpochMilli(),
            berlin,
        )

        val nextLocal = Instant.ofEpochMilli(next!!).atZone(berlin)
        assertEquals(java.time.LocalDate.of(2026, 3, 29), nextLocal.toLocalDate())
        assertEquals(9, nextLocal.hour)
    }

    @Test
    fun nextOccurrenceForAllDayEventUsesLocalMidnight() {
        val berlin = ZoneId.of("Europe/Berlin")
        val start = java.time.LocalDate.of(2026, 3, 22)
            .atStartOfDay(berlin).toInstant().toEpochMilli()
        val event = Event(
            uid = "next-all-day",
            title = "All day",
            start = start,
            end = java.time.LocalDate.of(2026, 3, 23)
                .atStartOfDay(berlin).toInstant().toEpochMilli(),
            recurrenceRule = "FREQ=DAILY;COUNT=3",
            allDay = true,
        )

        val next = RecurrenceExpander.nextOccurrenceStart(
            event,
            java.time.LocalDate.of(2026, 3, 22)
                .atTime(12, 0).atZone(berlin).toInstant().toEpochMilli(),
            berlin,
        )

        assertEquals(
            java.time.LocalDate.of(2026, 3, 23).atStartOfDay(berlin)
                .toInstant().toEpochMilli(),
            next,
        )
    }
}
