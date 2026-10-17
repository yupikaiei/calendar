package com.frelsical.nativeapp.ical

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId

class RecurrenceRulesTest {

    private val berlin = ZoneId.of("Europe/Berlin")

    @Test
    fun parsesDateOnlyUntil() {
        assertEquals(
            LocalDate.of(2026, 4, 15),
            RecurrenceRules.parseUntilDate("FREQ=DAILY;UNTIL=20260415", berlin),
        )
    }

    @Test
    fun parsesUtcUntilInLocalZone() {
        assertEquals(
            LocalDate.of(2026, 4, 15),
            RecurrenceRules.parseUntilDate("FREQ=WEEKLY;UNTIL=20260415T215959Z", berlin),
        )
    }

    @Test
    fun stripsExistingUntilBeforeRewriting() {
        val rewritten = RecurrenceRules.withUntil(
            rule = "FREQ=WEEKLY;UNTIL=20250101T000000Z",
            endDate = LocalDate.of(2026, 4, 15),
            zone = berlin,
        )

        assertEquals("FREQ=WEEKLY;UNTIL=20260415T215959Z", rewritten)
    }

    @Test
    fun normalizesRulePrefix() {
        assertEquals("FREQ=DAILY", RecurrenceRules.normalize("RRULE:FREQ=DAILY"))
        assertNull(RecurrenceRules.normalize(""))
        assertNull(RecurrenceRules.normalize("NOT-A-RULE"))
    }

    @Test
    fun labelsPresetAndCustomRules() {
        assertEquals("Every Day", RecurrenceRules.presetLabel("FREQ=DAILY"))
        assertEquals("Every Week", RecurrenceRules.presetLabel("RRULE:FREQ=WEEKLY"))
        assertEquals("Custom", RecurrenceRules.presetLabel("FREQ=WEEKLY;BYDAY=MO"))
        assertEquals("Does not repeat", RecurrenceRules.presetLabel(null))
        assertTrue(RecurrenceRules.isPreset("FREQ=MONTHLY"))
        assertFalse(RecurrenceRules.isPreset("FREQ=WEEKLY;BYDAY=MO"))
    }
}
