package com.frelsical.nativeapp.ui

import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

object DateFormats {
    fun zone(): ZoneId = ZoneId.systemDefault()

    fun millisToDate(millis: Long, zone: ZoneId = zone()): LocalDate =
        Instant.ofEpochMilli(millis).atZone(zone).toLocalDate()

    fun dateToMillis(date: LocalDate, zone: ZoneId = zone()): Long =
        date.atStartOfDay(zone).toInstant().toEpochMilli()

    fun millisToTime(millis: Long, zone: ZoneId = zone()): LocalTime =
        Instant.ofEpochMilli(millis).atZone(zone).toLocalTime()

    fun combine(date: LocalDate, time: LocalTime, zone: ZoneId = zone()): Long =
        LocalDateTime.of(date, time).atZone(zone).toInstant().toEpochMilli()

    fun timeLabel(millis: Long, zone: ZoneId = zone()): String =
        DateTimeFormatter.ofPattern("HH:mm").format(Instant.ofEpochMilli(millis).atZone(zone))

    fun weekdayShort(date: LocalDate): String =
        DateTimeFormatter.ofPattern("EEE", Locale.getDefault()).format(date).uppercase(Locale.getDefault())

    fun monthShort(date: LocalDate): String =
        DateTimeFormatter.ofPattern("MMM yy", Locale.getDefault()).format(date).uppercase(Locale.getDefault())

    fun monthYear(date: LocalDate): String =
        DateTimeFormatter.ofPattern("MMMM yyyy", Locale.getDefault()).format(date)

    fun fullDate(date: LocalDate): String =
        DateTimeFormatter.ofPattern("EEEE, MMMM d", Locale.getDefault()).format(date)

    fun isoDate(date: LocalDate): String =
        DateTimeFormatter.ofPattern("yyyy-MM-dd", Locale.US).format(date)

    fun rangeLabel(start: Long, end: Long, allDay: Boolean, zone: ZoneId = zone()): String {
        if (allDay) return "All day"
        return "${timeLabel(start, zone)} - ${timeLabel(end, zone)}"
    }

    fun secondaryTimeLabel(start: Long, end: Long, timezone: ZoneId?): String? {
        if (timezone == null) return null
        val startZoned = Instant.ofEpochMilli(start).atZone(timezone)
        val endZoned = Instant.ofEpochMilli(end).atZone(timezone)
        val formatter = DateTimeFormatter.ofPattern("HH:mm")
        return "[${startZoned.zone.getDisplayName(java.time.format.TextStyle.SHORT, Locale.getDefault())}] " +
            "${formatter.format(startZoned)} - ${formatter.format(endZoned)}"
    }
}
