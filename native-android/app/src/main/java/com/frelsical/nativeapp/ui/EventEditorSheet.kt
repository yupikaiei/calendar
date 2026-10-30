package com.frelsical.nativeapp.ui

import android.text.format.DateFormat
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.InputChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.frelsical.nativeapp.data.CalendarRecord
import com.frelsical.nativeapp.data.Event
import com.frelsical.nativeapp.data.EventDraft
import com.frelsical.nativeapp.data.Occurrence
import com.frelsical.nativeapp.ical.RecurrenceRules
import com.frelsical.nativeapp.ui.theme.parseCalendarColor
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.util.UUID

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun EventEditorSheet(
    event: Event?,
    occurrence: Occurrence?,
    initialDate: LocalDate,
    calendars: List<CalendarRecord>,
    onDismiss: () -> Unit,
    viewModel: CalendarViewModel,
    draft: EventDraft? = null,
) {
    val zone: ZoneId = remember { ZoneId.systemDefault() }
    val context = LocalContext.current
    val editingOccurrence = occurrence != null
    val prefilledAllDay = event?.allDay ?: draft?.allDay ?: false
    val defaultStart = remember(event?.id, occurrence?.start, initialDate, draft) {
        occurrence?.start ?: event?.start ?: draft?.start ?: DateFormats.combine(
            initialDate,
            LocalTime.now().withSecond(0).withNano(0),
            zone,
        )
    }
    val defaultEnd = remember(event?.id, occurrence?.start, draft) {
        occurrence?.end ?: event?.end ?: draft?.end ?: (defaultStart + 60 * 60 * 1000L)
    }

    var title by rememberSaveable { mutableStateOf(event?.title ?: draft?.title.orEmpty()) }
    var description by rememberSaveable {
        mutableStateOf(event?.description ?: draft?.description.orEmpty())
    }
    var location by rememberSaveable { mutableStateOf(event?.location ?: draft?.location.orEmpty()) }
    var allDay by rememberSaveable { mutableStateOf(prefilledAllDay) }
    var startDate by rememberSaveable { mutableStateOf(DateFormats.millisToDate(defaultStart, zone)) }
    var startTime by rememberSaveable { mutableStateOf(DateFormats.millisToTime(defaultStart, zone)) }
    var endDate by rememberSaveable {
        mutableStateOf(
            DateFormats.millisToDate(defaultEnd, zone).let {
                if (prefilledAllDay) it.minusDays(1) else it
            },
        )
    }
    var endTime by rememberSaveable { mutableStateOf(DateFormats.millisToTime(defaultEnd, zone)) }
    var recurrence by rememberSaveable {
        mutableStateOf(RecurrenceRules.normalize(event?.recurrenceRule ?: draft?.recurrenceRule))
    }
    var recurrenceEndDate by rememberSaveable {
        mutableStateOf(
            RecurrenceRules.parseUntilDate(event?.recurrenceRule ?: draft?.recurrenceRule, zone),
        )
    }
    var reminders by remember { mutableStateOf(listOf<Int>()) }
    var originalReminders by remember { mutableStateOf(listOf<Int>()) }
    var selectedCalendarId by rememberSaveable { mutableStateOf(event?.calendarId) }
    var titleError by remember { mutableStateOf(false) }
    var showDeleteConfirm by remember { mutableStateOf(false) }
    var showReminderDialog by remember { mutableStateOf(false) }
    var datePickerTarget by remember { mutableStateOf<DateTarget?>(null) }
    var timePickerTarget by remember { mutableStateOf<TimeTarget?>(null) }
    val exactAlarmsAllowed = viewModel.canScheduleExactAlarms()

    LaunchedEffect(event?.id) {
        if (event != null) {
            val loaded = viewModel.remindersFor(event.id)
            reminders = loaded
            originalReminders = loaded
        }
    }
    LaunchedEffect(calendars) {
        if (selectedCalendarId == null) {
            selectedCalendarId = calendars.firstOrNull { it.urlPath.contains("frelsi") }?.id
                ?: calendars.firstOrNull()?.id
        }
    }

    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.surface,
    ) {
        Column(
            modifier = Modifier
                .fillMaxHeight(0.94f)
                .navigationBarsPadding()
                .imePadding(),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(onClick = onDismiss) { Text("Cancel") }
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = when {
                            editingOccurrence -> "Edit Occurrence"
                            event == null -> "New Event"
                            else -> "Edit Event"
                        },
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                    )
                    if (editingOccurrence) {
                        Text(
                            text = "This occurrence only",
                            fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.secondary,
                        )
                    }
                }
                if (event != null) {
                    IconButton(onClick = { showDeleteConfirm = true }) {
                        Icon(Icons.Filled.Delete, contentDescription = "Delete", tint = MaterialTheme.colorScheme.error)
                    }
                }
                TextButton(onClick = {
                    if (title.isBlank()) {
                        titleError = true
                        return@TextButton
                    }
                    val start = if (allDay) {
                        DateFormats.dateToMillis(startDate, zone)
                    } else {
                        DateFormats.combine(startDate, startTime, zone)
                    }
                    val end = if (allDay) {
                        val lastDay = if (endDate.isBefore(startDate)) startDate else endDate
                        DateFormats.dateToMillis(lastDay.plusDays(1), zone)
                    } else {
                        DateFormats.combine(endDate, endTime, zone)
                    }
                    if (end <= start) {
                        viewModel.notify("End time must be after the start time.")
                        return@TextButton
                    }
                    if (event != null && occurrence != null) {
                        val standalone = Event(
                            uid = UUID.randomUUID().toString(),
                            title = title.trim(),
                            start = start,
                            end = end,
                            description = description.trim().takeIf { it.isNotEmpty() },
                            location = location.trim().takeIf { it.isNotEmpty() },
                            recurrenceRule = null,
                            calendarId = selectedCalendarId,
                            allDay = allDay,
                        )
                        viewModel.saveOccurrence(
                            baseEvent = event,
                            occurrenceStart = occurrence.start,
                            editedEvent = standalone,
                            reminderMinutes = reminders,
                        )
                    } else {
                        val saved = Event(
                            id = event?.id ?: 0L,
                            uid = event?.uid ?: UUID.randomUUID().toString(),
                            title = title.trim(),
                            start = start,
                            end = end,
                            description = description.trim().takeIf { it.isNotEmpty() },
                            location = location.trim().takeIf { it.isNotEmpty() },
                            recurrenceRule = recurrence?.let {
                                RecurrenceRules.withUntil(it, recurrenceEndDate, zone)
                            },
                            calendarId = selectedCalendarId,
                            allDay = allDay,
                            excludedStarts = event?.excludedStarts ?: emptySet(),
                        )
                        viewModel.saveEvent(saved, reminders, originalReminders)
                    }
                    onDismiss()
                }) {
                    Text("Save", fontWeight = FontWeight.Bold)
                }
            }
            HorizontalDivider()

            LazyColumn(
                modifier = Modifier.fillMaxWidth(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                item {
                    OutlinedTextField(
                        value = title,
                        onValueChange = {
                            title = it
                            titleError = false
                        },
                        label = { Text("Event Title") },
                        isError = titleError,
                        supportingText = if (titleError) {
                            { Text("Title is required") }
                        } else {
                            null
                        },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }

                if (calendars.isNotEmpty()) {
                    item {
                        DropdownField(
                            label = "Calendar",
                            selected = selectedCalendarId,
                            options = calendars.map { it.id to it.displayName },
                            onSelect = { selectedCalendarId = it },
                            leadingColor = { id -> calendars.firstOrNull { it.id == id }?.color },
                        )
                    }
                }

                item {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("All-day", modifier = Modifier.weight(1f), color = Color.White)
                        Switch(checked = allDay, onCheckedChange = { allDay = it })
                    }
                }

                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        EditorField(
                            label = "Start Date",
                            value = DateFormats.isoDate(startDate),
                            modifier = Modifier.weight(1f),
                            onClick = { datePickerTarget = DateTarget.StartDate },
                        )
                        if (!allDay) {
                            EditorField(
                                label = "Start Time",
                                value = startTime.formatTime(),
                                modifier = Modifier.weight(1f),
                                onClick = { timePickerTarget = TimeTarget.StartTime },
                            )
                        }
                    }
                }

                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        EditorField(
                            label = "End Date",
                            value = DateFormats.isoDate(endDate),
                            modifier = Modifier.weight(1f),
                            onClick = { datePickerTarget = DateTarget.EndDate },
                        )
                        if (!allDay) {
                            EditorField(
                                label = "End Time",
                                value = endTime.formatTime(),
                                modifier = Modifier.weight(1f),
                                onClick = { timePickerTarget = TimeTarget.EndTime },
                            )
                        }
                    }
                }

                if (!editingOccurrence) {
                    item {
                        val options = buildList {
                            add(null to "Does not repeat")
                            add(RecurrenceRules.DAILY to "Every Day")
                            add(RecurrenceRules.WEEKLY to "Every Week")
                            add(RecurrenceRules.MONTHLY to "Every Month")
                            add(RecurrenceRules.YEARLY to "Every Year")
                            val current = recurrence
                            if (current != null && !RecurrenceRules.isPreset(current)) {
                                add(current to "Custom")
                            }
                        }
                        DropdownField(
                            label = "Repeat",
                            selected = recurrence,
                            options = options,
                            onSelect = { value ->
                                recurrence = value
                                if (value == null) recurrenceEndDate = null
                            },
                        )
                    }

                    if (recurrence != null) {
                        item {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                Text("Ends", color = Color.White.copy(alpha = 0.8f))
                                OutlinedButton(
                                    onClick = { datePickerTarget = DateTarget.RecurrenceEnd },
                                    modifier = Modifier.weight(1f),
                                ) {
                                    Text(recurrenceEndDate?.let(DateFormats::isoDate) ?: "Never")
                                }
                                if (recurrenceEndDate != null) {
                                    IconButton(onClick = { recurrenceEndDate = null }) {
                                        Icon(Icons.Filled.Close, contentDescription = "Remove end date")
                                    }
                                }
                            }
                        }
                    }
                }

                item {
                    Column {
                        Text(
                            "Reminders",
                            fontWeight = FontWeight.Bold,
                            fontSize = 16.sp,
                            color = Color.White,
                        )
                        Spacer(Modifier.height(8.dp))
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            reminders.forEach { minutes ->
                                InputChip(
                                    selected = false,
                                    onClick = {},
                                    label = { Text(reminderLabel(minutes)) },
                                    trailingIcon = {
                                        Icon(
                                            Icons.Filled.Close,
                                            contentDescription = "Remove reminder",
                                            modifier = Modifier
                                                .size(16.dp)
                                                .clickable {
                                                    reminders = reminders - minutes
                                                },
                                        )
                                    },
                                )
                            }
                            AssistChip(
                                onClick = { showReminderDialog = true },
                                label = { Text("Add reminder") },
                                leadingIcon = {
                                    Icon(
                                        Icons.Filled.Add,
                                        contentDescription = null,
                                        modifier = Modifier.size(16.dp),
                                    )
                                },
                            )
                        }
                        if (reminders.isNotEmpty() && !exactAlarmsAllowed) {
                            Spacer(Modifier.height(8.dp))
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(
                                    text = "Reminders may be delayed. Allow exact alarms to keep them on time.",
                                    modifier = Modifier.weight(1f),
                                    fontSize = 13.sp,
                                    color = Color.White.copy(alpha = 0.65f),
                                )
                                TextButton(onClick = { openExactAlarmSettings(context) }) {
                                    Text("Enable")
                                }
                            }
                        }
                    }
                }

                item {
                    OutlinedTextField(
                        value = location,
                        onValueChange = { location = it },
                        label = { Text("Location") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }

                item {
                    OutlinedTextField(
                        value = description,
                        onValueChange = { description = it },
                        label = { Text("Description") },
                        minLines = 3,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }

                item { Spacer(Modifier.height(32.dp)) }
            }
        }
    }

    if (showDeleteConfirm && event != null) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = {
                Text(if (editingOccurrence) "Delete this occurrence?" else "Delete event?")
            },
            text = {
                if (editingOccurrence) {
                    Text("Only this occurrence will be removed from the repeating series.")
                } else {
                    val localOnly = calendars.firstOrNull { it.id == event.calendarId }
                        ?.urlPath?.startsWith("/local/") == true
                    Text(
                        if (localOnly) {
                            "This event will be deleted from this device."
                        } else {
                            "This event will also be removed from the connected CalDAV server."
                        },
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    if (occurrence != null) {
                        viewModel.deleteOccurrence(event, occurrence.start)
                    } else {
                        viewModel.deleteEvent(event, reminders)
                    }
                    onDismiss()
                }) {
                    Text("Delete", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) { Text("Cancel") }
            },
        )
    }

    if (showReminderDialog) {
        AlertDialog(
            onDismissRequest = { showReminderDialog = false },
            title = { Text("Add Reminder") },
            text = {
                Column {
                    listOf(0, 10, 60, 1440).forEach { minutes ->
                        Text(
                            text = reminderLabel(minutes),
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    if (!reminders.contains(minutes)) reminders = reminders + minutes
                                    showReminderDialog = false
                                }
                                .padding(vertical = 12.dp),
                            fontSize = 16.sp,
                        )
                    }
                }
            },
            confirmButton = {},
            dismissButton = {
                TextButton(onClick = { showReminderDialog = false }) { Text("Cancel") }
            },
        )
    }

    datePickerTarget?.let { target ->
        val initial = when (target) {
            DateTarget.StartDate -> startDate
            DateTarget.EndDate -> endDate
            DateTarget.RecurrenceEnd -> recurrenceEndDate ?: startDate
        }
        DatePickerModal(
            initialDate = initial,
            onDismiss = { datePickerTarget = null },
            onSelect = { picked ->
                when (target) {
                    DateTarget.StartDate -> {
                        startDate = picked
                        if (endDate.isBefore(picked)) endDate = picked
                    }

                    DateTarget.EndDate -> endDate = picked
                    DateTarget.RecurrenceEnd -> recurrenceEndDate = picked
                }
                datePickerTarget = null
            },
        )
    }

    timePickerTarget?.let { target ->
        val initial = when (target) {
            TimeTarget.StartTime -> startTime
            TimeTarget.EndTime -> endTime
        }
        TimePickerModal(
            initialTime = initial,
            onDismiss = { timePickerTarget = null },
            onSelect = { picked ->
                when (target) {
                    TimeTarget.StartTime -> startTime = picked
                    TimeTarget.EndTime -> endTime = picked
                }
                timePickerTarget = null
            },
        )
    }
}

private enum class DateTarget { StartDate, EndDate, RecurrenceEnd }
private enum class TimeTarget { StartTime, EndTime }

private fun LocalTime.formatTime(): String {
    return "%02d:%02d".format(hour, minute)
}

private fun reminderLabel(minutes: Int): String {
    if (minutes == 0) return "At time of event"
    if (minutes < 60) return "$minutes minutes before"
    if (minutes < 1440) return "${minutes / 60} hours before"
    return "${minutes / 1440} days before"
}

@Composable
private fun EditorField(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    OutlinedButton(
        onClick = onClick,
        modifier = modifier,
        shape = RoundedCornerShape(12.dp),
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 12.dp),
    ) {
        Column(Modifier.fillMaxWidth()) {
            Text(label, fontSize = 11.sp, color = Color.White.copy(alpha = 0.6f))
            Spacer(Modifier.height(2.dp))
            Text(value, fontSize = 15.sp, color = Color.White)
        }
    }
}

@Composable
private fun <T> DropdownField(
    label: String,
    selected: T,
    options: List<Pair<T, String>>,
    onSelect: (T) -> Unit,
    leadingColor: ((T) -> String?)? = null,
) {
    var expanded by remember { mutableStateOf(false) }
    Column {
        Text(label, fontSize = 12.sp, color = Color.White.copy(alpha = 0.6f))
        Spacer(Modifier.height(4.dp))
        Box {
            OutlinedButton(
                onClick = { expanded = true },
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp),
            ) {
                val color = leadingColor?.invoke(selected)?.let(::parseCalendarColor)
                if (color != null) {
                    Box(
                        Modifier
                            .size(12.dp)
                            .clip(CircleShape)
                            .background(color),
                    )
                    Spacer(Modifier.width(8.dp))
                }
                Text(
                    text = options.firstOrNull { it.first == selected }?.second ?: "None",
                    modifier = Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Icon(Icons.Filled.KeyboardArrowDown, contentDescription = null)
            }
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                options.forEach { (value, text) ->
                    DropdownMenuItem(
                        text = { Text(text) },
                        onClick = {
                            expanded = false
                            onSelect(value)
                        },
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DatePickerModal(
    initialDate: LocalDate,
    onDismiss: () -> Unit,
    onSelect: (LocalDate) -> Unit,
) {
    val state = rememberDatePickerState(
        initialSelectedDateMillis = initialDate
            .atStartOfDay(ZoneOffset.UTC)
            .toInstant()
            .toEpochMilli(),
    )
    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = {
                state.selectedDateMillis?.let { millis ->
                    onSelect(Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate())
                }
                onDismiss()
            }) { Text("OK") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    ) {
        DatePicker(state = state)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TimePickerModal(
    initialTime: LocalTime,
    onDismiss: () -> Unit,
    onSelect: (LocalTime) -> Unit,
) {
    val context = LocalContext.current
    val state = rememberTimePickerState(
        initialHour = initialTime.hour,
        initialMinute = initialTime.minute,
        is24Hour = DateFormat.is24HourFormat(context),
    )
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = {
                onSelect(LocalTime.of(state.hour, state.minute))
                onDismiss()
            }) { Text("OK") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
        text = { TimePicker(state = state) },
    )
}
