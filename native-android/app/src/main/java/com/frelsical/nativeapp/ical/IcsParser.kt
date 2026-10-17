package com.frelsical.nativeapp.ical

import com.frelsical.nativeapp.data.Event
import java.nio.charset.StandardCharsets
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.UUID

data class ParsedEvent(
    val uid: String,
    val title: String,
    val start: Long,
    val end: Long,
    val allDay: Boolean,
    val description: String?,
    val location: String?,
    val recurrenceRule: String?,
    val excludedStarts: Set<Long> = emptySet(),
)

/**
 * Small, dependency-free iCalendar reader/writer covering the VEVENT subset the
 * app uses (UID, SUMMARY, DTSTART, DTEND, DESCRIPTION, LOCATION, RRULE, EXDATE).
 */
object IcsParser {

    private data class Property(
        val name: String,
        val params: Map<String, String>,
        val value: String,
    )

    private data class ParsedDate(val millis: Long, val allDay: Boolean)

    private val basicDate: DateTimeFormatter = DateTimeFormatter.BASIC_ISO_DATE
    private val basicTime: DateTimeFormatter = DateTimeFormatter.ofPattern("HHmmss")

    fun parseEvents(
        icsData: String,
        zone: ZoneId = ZoneId.systemDefault(),
    ): List<ParsedEvent> {
        val events = mutableListOf<ParsedEvent>()
        var current: MutableMap<String, MutableList<Property>>? = null
        var nestedDepth = 0

        for (line in unfold(icsData)) {
            val property = parseProperty(line) ?: continue
            when (property.name) {
                "BEGIN" -> {
                    val component = property.value.trim()
                    if (component.equals("VEVENT", ignoreCase = true) && current == null) {
                        current = linkedMapOf()
                        nestedDepth = 0
                    } else if (current != null) {
                        nestedDepth++
                    }
                }

                "END" -> {
                    val component = property.value.trim()
                    if (component.equals("VEVENT", ignoreCase = true) &&
                        current != null &&
                        nestedDepth == 0
                    ) {
                        mapEvent(current, zone)?.let(events::add)
                        current = null
                    } else if (current != null && nestedDepth > 0) {
                        nestedDepth--
                    }
                }

                else -> if (current != null && nestedDepth == 0) {
                    current.getOrPut(property.name) { mutableListOf() }.add(property)
                }
            }
        }

        // Tolerate unterminated VEVENT blocks from sloppy exporters.
        if (events.isEmpty() && current != null) {
            mapEvent(current, zone)?.let(events::add)
        }

        return events
    }

    fun parseEvent(
        icsData: String,
        zone: ZoneId = ZoneId.systemDefault(),
    ): ParsedEvent? = parseEvents(icsData, zone).firstOrNull()

    fun generateIcs(event: Event, zone: ZoneId = ZoneId.systemDefault()): String {
        val allDayStart = Instant.ofEpochMilli(event.start).atZone(zone).toLocalDate()
        val allDayEnd = Instant.ofEpochMilli(event.end).atZone(zone).toLocalDate()
            .let { if (it.isAfter(allDayStart)) it else allDayStart.plusDays(1) }

        val lines = mutableListOf(
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Frelsi Cal Native//EN",
            "CALSCALE:GREGORIAN",
            "BEGIN:VEVENT",
            "UID:${event.uid}",
            "DTSTAMP:${formatUtc(Instant.now().toEpochMilli())}",
            "SUMMARY:${escapeText(event.title)}",
        )

        if (event.allDay) {
            lines += "DTSTART;VALUE=DATE:${basicDate.format(allDayStart)}"
            lines += "DTEND;VALUE=DATE:${basicDate.format(allDayEnd)}"
        } else {
            lines += "DTSTART:${formatUtc(event.start)}"
            lines += "DTEND:${formatUtc(event.end)}"
        }

        event.description?.takeIf { it.isNotBlank() }?.let {
            lines += "DESCRIPTION:${escapeText(it)}"
        }
        event.location?.takeIf { it.isNotBlank() }?.let {
            lines += "LOCATION:${escapeText(it)}"
        }
        event.recurrenceRule?.takeIf { it.isNotBlank() }?.let {
            val rule = it.removePrefix("RRULE:")
            lines += "RRULE:$rule"
            if (event.excludedStarts.isNotEmpty()) {
                if (event.allDay) {
                    val dates = event.excludedStarts.sorted()
                        .map { millis -> Instant.ofEpochMilli(millis).atZone(zone).toLocalDate() }
                        .distinct()
                        .joinToString(",") { basicDate.format(it) }
                    lines += "EXDATE;VALUE=DATE:$dates"
                } else {
                    val instants = event.excludedStarts.sorted()
                        .distinct()
                        .joinToString(",") { formatUtc(it) }
                    lines += "EXDATE:$instants"
                }
            }
        }

        lines += "END:VEVENT"
        lines += "END:VCALENDAR"

        return lines.joinToString("\r\n", postfix = "\r\n") { fold(it) }
    }

    private fun mapEvent(
        properties: Map<String, MutableList<Property>>,
        zone: ZoneId,
    ): ParsedEvent? {
        fun first(name: String): Property? = properties[name]?.firstOrNull()

        val startProperty = first("DTSTART") ?: return null
        val start = parseDate(startProperty, zone) ?: return null
        val end = first("DTEND")?.let { parseDate(it, zone) }

        val endMillis = when {
            end == null && start.allDay -> start.millis + Duration.DAY_MILLIS
            end == null -> start.millis + Duration.HOUR_MILLIS
            end.millis < start.millis -> start.millis + if (start.allDay) Duration.DAY_MILLIS else Duration.HOUR_MILLIS
            else -> end.millis
        }

        val rule = first("RRULE")?.value?.trim()?.let { raw ->
            raw.removePrefix("RRULE:").takeIf { it.contains("FREQ=", ignoreCase = true) }
        }

        val exclusions = properties["EXDATE"].orEmpty()
            .flatMap { property ->
                property.value.split(',').mapNotNull { raw ->
                    if (raw.isBlank()) {
                        null
                    } else {
                        parseDate(property.copy(value = raw.trim()), zone)?.millis
                    }
                }
            }
            .toSet()

        return ParsedEvent(
            uid = first("UID")?.value?.trim()?.takeIf { it.isNotEmpty() }
                ?: UUID.randomUUID().toString(),
            title = first("SUMMARY")?.value?.let(::unescapeText)?.takeIf { it.isNotBlank() }
                ?: "Untitled",
            start = start.millis,
            end = endMillis,
            allDay = start.allDay,
            description = first("DESCRIPTION")?.value?.let(::unescapeText)?.takeIf { it.isNotBlank() },
            location = first("LOCATION")?.value?.let(::unescapeText)?.takeIf { it.isNotBlank() },
            recurrenceRule = rule,
            excludedStarts = exclusions,
        )
    }

    private fun parseDate(property: Property, zone: ZoneId): ParsedDate? {
        val raw = property.value.trim()
        if (raw.isEmpty()) return null

        val dateOnly =
            property.params["VALUE"]?.equals("DATE", ignoreCase = true) == true || raw.length == 8

        if (dateOnly) {
            return runCatching {
                val date = LocalDate.parse(raw.substring(0, 8), basicDate)
                ParsedDate(date.atStartOfDay(zone).toInstant().toEpochMilli(), allDay = true)
            }.getOrNull()
        }

        if (raw.length >= 15 && raw[8] == 'T') {
            return runCatching {
                val date = LocalDate.parse(raw.substring(0, 8), basicDate)
                val time = LocalTime.parse(raw.substring(9, 15), basicTime)
                val timeZone = when {
                    raw.endsWith("Z", ignoreCase = true) -> ZoneOffset.UTC
                    else -> zoneFromTzid(property.params["TZID"]) ?: zone
                }
                ParsedDate(ZonedDateTime.of(date, time, timeZone).toInstant().toEpochMilli(), allDay = false)
            }.getOrNull()
        }

        return runCatching {
            ParsedDate(Instant.parse(raw).toEpochMilli(), allDay = false)
        }.getOrNull()
    }

    private fun zoneFromTzid(tzid: String?): ZoneId? {
        if (tzid.isNullOrBlank()) return null
        runCatching { return ZoneId.of(tzid) }
        val candidate = tzid.trimStart('/').substringAfter("Tzfile/")
        runCatching { return ZoneId.of(candidate) }
        return ZoneId.getAvailableZoneIds()
            .filter { tzid.endsWith(it) }
            .maxByOrNull { it.length }
            ?.let { runCatching { ZoneId.of(it) }.getOrNull() }
    }

    private fun unfold(data: String): List<String> {
        val normalized = data.replace("\r\n", "\n").replace('\r', '\n')
        val lines = mutableListOf<StringBuilder>()
        for (line in normalized.split('\n')) {
            if (line.startsWith(' ') || line.startsWith('\t')) {
                if (lines.isEmpty()) {
                    lines += StringBuilder(line)
                } else {
                    lines.last().append(line.substring(1))
                }
            } else {
                lines += StringBuilder(line)
            }
        }
        return lines.map { it.toString() }
    }

    private fun parseProperty(line: String): Property? {
        if (line.isBlank()) return null
        val colon = line.indexOf(':')
        if (colon <= 0) return null

        val head = line.substring(0, colon)
        val value = line.substring(colon + 1)
        val parts = head.split(';')
        if (parts.isEmpty()) return null

        val params = buildMap {
            for (part in parts.drop(1)) {
                val equals = part.indexOf('=')
                if (equals > 0) {
                    put(
                        part.substring(0, equals).uppercase(),
                        part.substring(equals + 1).trim('"'),
                    )
                }
            }
        }

        return Property(parts[0].uppercase(), params, value)
    }

    private fun escapeText(text: String): String {
        return text
            .replace("\\", "\\\\")
            .replace(";", "\\;")
            .replace(",", "\\,")
            .replace("\r\n", "\\n")
            .replace("\n", "\\n")
            .replace("\r", "\\n")
    }

    private fun unescapeText(text: String): String {
        val result = StringBuilder(text.length)
        var index = 0
        while (index < text.length) {
            val char = text[index]
            if (char == '\\' && index + 1 < text.length) {
                when (val next = text[index + 1]) {
                    'n', 'N' -> result.append('\n')
                    '\\', ';', ',' -> result.append(next)
                    else -> {
                        result.append(char)
                        result.append(next)
                    }
                }
                index += 2
            } else {
                result.append(char)
                index++
            }
        }
        return result.toString()
    }

    private fun formatUtc(millis: Long): String {
        val formatter = DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'")
        return formatter.format(Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC))
    }

    private fun fold(line: String): String {
        val bytes = line.toByteArray(StandardCharsets.UTF_8)
        if (bytes.size <= 75) return line

        val chunks = mutableListOf<String>()
        val current = StringBuilder()
        var currentBytes = 0
        for (char in line) {
            val charBytes = char.toString().toByteArray(StandardCharsets.UTF_8).size
            if (currentBytes + charBytes > 75 && current.isNotEmpty()) {
                chunks += current.toString()
                current.clear()
                currentBytes = 0
            }
            current.append(char)
            currentBytes += charBytes
        }
        if (current.isNotEmpty()) chunks += current.toString()
        return chunks.joinToString("\r\n ")
    }

    private object Duration {
        const val HOUR_MILLIS = 60L * 60L * 1000L
        const val DAY_MILLIS = 24L * HOUR_MILLIS
    }
}
