package com.frelsical.nativeapp.ical

import com.frelsical.nativeapp.data.Event
import com.frelsical.nativeapp.data.EventWithCalendar
import com.frelsical.nativeapp.data.Occurrence
import org.dmfs.rfc5545.DateTime
import org.dmfs.rfc5545.recur.RecurrenceRule
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.util.TimeZone
import java.util.logging.Level
import java.util.logging.Logger

object RecurrenceExpander {

    private val logger = Logger.getLogger(RecurrenceExpander::class.java.name)
    private const val MAX_INSTANCES = 10_000

    /**
     * Returns all events grouped by local day. The original event is always
     * included; recurring events are expanded into the supplied window.
     */
    fun expand(
        events: List<EventWithCalendar>,
        windowStart: Instant,
        windowEnd: Instant,
        zone: ZoneId = ZoneId.systemDefault(),
    ): Map<LocalDate, List<Occurrence>> {
        val result = linkedMapOf<LocalDate, MutableList<Occurrence>>()
        // Keep "today" visible in the agenda even when it has no events.
        result[LocalDate.now(zone)] = mutableListOf()

        for (item in events) {
            val event = item.event
            val base = occurrenceFor(event, item.calendar, event.start, event.end, zone)
            result.getOrPut(base.date) { mutableListOf() }.add(base)

            val rule = RecurrenceRules.normalize(event.recurrenceRule) ?: continue
            for (instance in expandRule(event, rule, windowStart, windowEnd, zone)) {
                if (instance.start == event.start) continue
                val occurrence = occurrenceFor(
                    event,
                    item.calendar,
                    instance.start,
                    instance.end,
                    zone,
                )
                result.getOrPut(occurrence.date) { mutableListOf() }.add(occurrence)
            }
        }

        for (list in result.values) {
            list.sortBy { it.start }
        }
        return result
    }

    private data class Instance(val start: Long, val end: Long, val date: LocalDate)

    private fun occurrenceFor(
        event: Event,
        calendar: com.frelsical.nativeapp.data.CalendarRecord?,
        start: Long,
        end: Long,
        zone: ZoneId,
    ): Occurrence {
        val date = Instant.ofEpochMilli(start).atZone(zone).toLocalDate()
        return Occurrence(
            event = event,
            calendar = calendar,
            start = start,
            end = end,
            date = date,
            isRecurringInstance = start != event.start,
        )
    }

    private fun expandRule(
        event: Event,
        ruleText: String,
        windowStart: Instant,
        windowEnd: Instant,
        zone: ZoneId,
    ): List<Instance> {
        val instances = mutableListOf<Instance>()
        try {
            val rule = RecurrenceRule(ruleText, RecurrenceRule.RfcMode.RFC5545_LAX)
            val iteratorZone = if (event.allDay) UTC else TimeZone.getTimeZone(zone)
            val startDateTime = if (event.allDay) {
                val date = Instant.ofEpochMilli(event.start).atZone(zone).toLocalDate()
                DateTime.parse(date.toString().replace("-", ""))
            } else {
                DateTime(iteratorZone, event.start)
            }

            val iterator = rule.iterator(startDateTime)
            val forwardTo = if (event.allDay) {
                val date = windowStart.atZone(zone).toLocalDate()
                DateTime.parse(date.toString().replace("-", ""))
            } else {
                DateTime(iteratorZone, windowStart.toEpochMilli())
            }
            iterator.fastForward(forwardTo)

            val windowEndMillis = windowEnd.toEpochMilli()
            val dayCount = RecurrenceRules.dayCount(event.start, event.end, zone)
            val duration = (event.end - event.start).coerceAtLeast(0L)
            var guard = 0

            while (iterator.hasNext() && guard < MAX_INSTANCES) {
                val next = iterator.nextDateTime()
                guard++
                val instanceMillis = next.timestamp

                val instanceDate = if (event.allDay) {
                    Instant.ofEpochMilli(instanceMillis).atZone(ZoneOffset.UTC).toLocalDate()
                } else {
                    Instant.ofEpochMilli(instanceMillis).atZone(zone).toLocalDate()
                }
                val start = if (event.allDay) {
                    instanceDate.atStartOfDay(zone).toInstant().toEpochMilli()
                } else {
                    instanceMillis
                }
                if (start > windowEndMillis) break

                val end = if (event.allDay) {
                    instanceDate.plusDays(dayCount).atStartOfDay(zone).toInstant().toEpochMilli()
                } else {
                    start + duration
                }
                instances += Instance(start, end, instanceDate)
            }
        } catch (exception: Exception) {
            logger.log(Level.WARNING, "Unable to expand RRULE \"$ruleText\"", exception)
        }
        return instances
    }

    private val UTC: TimeZone = TimeZone.getTimeZone("UTC")
    /**
     * Returns the start of the next occurrence at or after [afterMillis], or null
     * when the event does not repeat again. Used to chain reminder alarms.
     */
    fun nextOccurrenceStart(
        event: Event,
        afterMillis: Long,
        zone: ZoneId = ZoneId.systemDefault(),
    ): Long? {
        if (event.start >= afterMillis) return event.start
        val ruleText = RecurrenceRules.normalize(event.recurrenceRule) ?: return null

        return try {
            val rule = RecurrenceRule(ruleText, RecurrenceRule.RfcMode.RFC5545_LAX)
            val iteratorZone = if (event.allDay) UTC else TimeZone.getTimeZone(zone)
            val startDateTime = if (event.allDay) {
                val date = Instant.ofEpochMilli(event.start).atZone(zone).toLocalDate()
                DateTime.parse(dateKey(date))
            } else {
                DateTime(iteratorZone, event.start)
            }

            val iterator = rule.iterator(startDateTime)
            val forwardTo = if (event.allDay) {
                val date = Instant.ofEpochMilli(afterMillis).atZone(zone).toLocalDate()
                DateTime.parse(dateKey(date))
            } else {
                DateTime(iteratorZone, afterMillis)
            }
            iterator.fastForward(forwardTo)

            var guard = 0
            while (iterator.hasNext() && guard < MAX_INSTANCES) {
                val occurrence = iterator.nextDateTime()
                guard++
                val start = if (event.allDay) {
                    val date = Instant.ofEpochMilli(occurrence.timestamp)
                        .atZone(ZoneOffset.UTC)
                        .toLocalDate()
                    date.atStartOfDay(zone).toInstant().toEpochMilli()
                } else {
                    occurrence.timestamp
                }
                if (start >= afterMillis) return start
            }
            null
        } catch (exception: Exception) {
            logger.log(Level.WARNING, "Unable to find next occurrence for \"$ruleText\"", exception)
            null
        }
    }

    private fun dateKey(date: LocalDate): String = date.toString().replace("-", "")

}
