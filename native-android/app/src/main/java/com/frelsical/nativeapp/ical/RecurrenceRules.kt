package com.frelsical.nativeapp.ical

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Helpers for the simple RRULE presets shown by the editor plus UNTIL
 * serialization/parsing that keeps the recurrence end date timezone-safe.
 */
object RecurrenceRules {

    const val DAILY = "FREQ=DAILY"
    const val WEEKLY = "FREQ=WEEKLY"
    const val MONTHLY = "FREQ=MONTHLY"
    const val YEARLY = "FREQ=YEARLY"

    private val untilRegex = Regex(""";?UNTIL=\d{8}(T\d{6}Z?)?;?""")
    private val untilValueRegex = Regex("""UNTIL=(\d{8})(T\d{6}Z?)?""")
    private val basicDate: DateTimeFormatter = DateTimeFormatter.BASIC_ISO_DATE

    fun normalize(rule: String?): String? {
        return rule?.trim()
            ?.removePrefix("RRULE:")
            ?.takeIf { it.contains("FREQ=", ignoreCase = true) }
    }

    fun stripUntil(rule: String): String {
        return rule.replace(untilRegex, "").trimEnd(';')
    }

    fun presetLabel(rule: String?): String {
        return when (normalize(rule)) {
            null -> "Does not repeat"
            DAILY -> "Every Day"
            WEEKLY -> "Every Week"
            MONTHLY -> "Every Month"
            YEARLY -> "Every Year"
            else -> "Custom"
        }
    }

    fun isPreset(rule: String?): Boolean {
        return normalize(rule) in setOf(DAILY, WEEKLY, MONTHLY, YEARLY)
    }

    fun parseUntilDate(rule: String?, zone: ZoneId = ZoneId.systemDefault()): LocalDate? {
        val match = untilValueRegex.find(rule ?: return null) ?: return null
        val datePart = match.groupValues[1]
        val timePart = match.groupValues[2]
        return runCatching {
            if (timePart.isEmpty()) {
                LocalDate.parse(datePart, basicDate)
            } else {
                val hasZulu = timePart.endsWith("Z")
                val core = timePart.removePrefix("T").removeSuffix("Z")
                if (core.length != 6) return null
                val date = LocalDate.parse(datePart, basicDate)
                val hour = core.substring(0, 2).toInt()
                val minute = core.substring(2, 4).toInt()
                val second = core.substring(4, 6).toInt()
                val local = date.atTime(hour, minute, second)
                if (hasZulu) {
                    local.toInstant(ZoneOffset.UTC).atZone(zone).toLocalDate()
                } else {
                    local.toLocalDate()
                }
            }
        }.getOrNull()
    }

    fun withUntil(
        rule: String,
        endDate: LocalDate?,
        zone: ZoneId = ZoneId.systemDefault(),
    ): String {
        val base = stripUntil(rule)
        if (endDate == null) return base

        val endOfDay = endDate.atTime(23, 59, 59).atZone(zone).toInstant()
        val until = DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'", Locale.US)
            .format(endOfDay.atZone(ZoneOffset.UTC))
        return "$base;UNTIL=$until"
    }

    fun dateLabel(date: LocalDate): String {
        return DateTimeFormatter.ofPattern("yyyy-MM-dd", Locale.US).format(date)
    }

    fun dayCount(start: Long, end: Long, zone: ZoneId): Long {
        val startDate = Instant.ofEpochMilli(start).atZone(zone).toLocalDate()
        val endDate = Instant.ofEpochMilli(end).atZone(zone).toLocalDate()
        return java.time.temporal.ChronoUnit.DAYS.between(startDate, endDate).coerceAtLeast(1)
    }
}
