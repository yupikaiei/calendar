package com.frelsical.nativeapp.ui

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.frelsical.nativeapp.data.Event
import com.frelsical.nativeapp.data.EventDraft
import com.frelsical.nativeapp.data.Occurrence
import com.frelsical.nativeapp.external.ExternalEventRequest
import com.frelsical.nativeapp.ical.RecurrenceExpander
import java.time.LocalDate
import java.time.ZoneId

private enum class ViewMode { Agenda, Month }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CalendarApp(
    viewModel: CalendarViewModel = viewModel(),
    externalRequest: ExternalEventRequest? = null,
    onExternalRequestConsumed: () -> Unit = {},
) {
    val events by viewModel.events.collectAsStateWithLifecycle()
    val eventsLoaded by viewModel.eventsLoaded.collectAsStateWithLifecycle()
    val calendars by viewModel.calendars.collectAsStateWithLifecycle()
    val secondaryTimezone by viewModel.secondaryTimezone.collectAsStateWithLifecycle()
    val syncing by viewModel.syncing.collectAsStateWithLifecycle()
    val syncStatus by viewModel.syncStatus.collectAsStateWithLifecycle()

    val snackbarHostState = remember { SnackbarHostState() }
    var viewMode by rememberSaveable { mutableStateOf(ViewMode.Agenda) }
    var selectedDay by rememberSaveable { mutableStateOf(LocalDate.now()) }
    var showSettings by rememberSaveable { mutableStateOf(false) }
    var scrollToTodaySignal by rememberSaveable { mutableIntStateOf(0) }
    var todayKey by rememberSaveable { mutableStateOf(LocalDate.now().toString()) }

    var editorVisible by remember { mutableStateOf(false) }
    var editorEvent by remember { mutableStateOf<Event?>(null) }
    var editorDraft by remember { mutableStateOf<EventDraft?>(null) }
    var editorDate by remember { mutableStateOf(LocalDate.now()) }
    var editorOccurrence by remember { mutableStateOf<Occurrence?>(null) }
    var scopeOccurrence by remember { mutableStateOf<Occurrence?>(null) }

    LaunchedEffect(Unit) {
        viewModel.messages.collect { message ->
            snackbarHostState.showSnackbar(message)
        }
    }

    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                val today = LocalDate.now()
                if (today.toString() != todayKey) {
                    // The app was last used on an earlier day: re-expand the
                    // agenda around the new today and scroll back to it.
                    todayKey = today.toString()
                    selectedDay = today
                    scrollToTodaySignal++
                }
                viewModel.autoSync()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    val zone = remember { ZoneId.systemDefault() }

    LaunchedEffect(externalRequest) {
        when (val request = externalRequest) {
            null -> Unit

            is ExternalEventRequest.NewEvent -> {
                // Show the request in the editor so the user confirms the event.
                showSettings = false
                editorEvent = null
                editorOccurrence = null
                editorDraft = request.draft
                editorDate = request.draft.start
                    ?.let { DateFormats.millisToDate(it, zone) }
                    ?: LocalDate.now(zone)
                editorVisible = true
                onExternalRequestConsumed()
            }

            is ExternalEventRequest.ImportIcs -> {
                showSettings = false
                viewModel.importIcs(request.uri)
                onExternalRequestConsumed()
            }

            is ExternalEventRequest.ImportIcsText -> {
                showSettings = false
                viewModel.importIcsText(request.contents)
                onExternalRequestConsumed()
            }
        }
    }
    var windowStart by rememberSaveable { mutableStateOf(LocalDate.now(zone).minusYears(2)) }
    var windowEnd by rememberSaveable { mutableStateOf(LocalDate.now(zone).plusYears(5)) }
    val days = remember(events, zone, windowStart, windowEnd, todayKey) {
        RecurrenceExpander.expand(
            events = events,
            windowStart = windowStart.atStartOfDay(zone).toInstant(),
            windowEnd = windowEnd.atStartOfDay(zone).toInstant(),
            zone = zone,
        )
    }

    fun extendPast() {
        windowStart = windowStart.minusYears(5)
    }

    fun extendFuture() {
        windowEnd = windowEnd.plusYears(5)
    }

    fun openOccurrence(occurrence: Occurrence) {
        if (occurrence.event.recurrenceRule != null) {
            scopeOccurrence = occurrence
        } else {
            editorEvent = occurrence.event
            editorDraft = null
            editorDate = occurrence.date
            editorOccurrence = null
            editorVisible = true
        }
    }

    if (showSettings) {
        SettingsScreen(
            viewModel = viewModel,
            calendars = calendars,
            secondaryTimezone = secondaryTimezone,
            onBack = { showSettings = false },
        )
        return
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.linearGradient(
                    listOf(Color(0xFF1E1E2C), Color(0xFF12121D)),
                ),
            ),
    ) {
        Scaffold(
            containerColor = Color.Transparent,
            snackbarHost = { SnackbarHost(snackbarHostState) },
            topBar = {
                Column {
                    TopAppBar(
                        title = {
                            Text(
                                text = if (viewMode == ViewMode.Agenda) "Agenda" else "Month",
                                style = MaterialTheme.typography.titleLarge,
                            )
                        },
                        colors = TopAppBarDefaults.topAppBarColors(
                            containerColor = Color.Transparent,
                        ),
                        actions = {
                            IconButton(
                                onClick = {
                                    viewMode = if (viewMode == ViewMode.Agenda) {
                                        ViewMode.Month
                                    } else {
                                        ViewMode.Agenda
                                    }
                                },
                            ) {
                                Icon(
                                    imageVector = if (viewMode == ViewMode.Agenda) {
                                        Icons.Filled.DateRange
                                    } else {
                                        Icons.AutoMirrored.Filled.List
                                    },
                                    contentDescription = "Toggle view",
                                )
                            }
                            if (viewMode == ViewMode.Agenda) {
                                TextButton(onClick = {
                                    selectedDay = LocalDate.now()
                                    scrollToTodaySignal++
                                }) {
                                    Text("Today")
                                }
                            }
                            val rotation = rememberInfiniteRotation(active = syncing)
                            IconButton(onClick = { viewModel.sync() }) {
                                Icon(
                                    imageVector = Icons.Filled.Refresh,
                                    contentDescription = "Sync",
                                    modifier = Modifier.rotate(if (syncing) rotation else 0f),
                                )
                            }
                            IconButton(onClick = { showSettings = true }) {
                                Icon(Icons.Filled.Settings, contentDescription = "Settings")
                            }
                        },
                    )
                    if (syncing) {
                        LinearProgressIndicator(Modifier.fillMaxWidth().height(2.dp))
                        syncStatus?.let { status ->
                            Text(
                                text = status,
                                style = MaterialTheme.typography.labelSmall,
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 2.dp),
                            )
                        }
                    }
                }
            },
            floatingActionButton = {
                FloatingActionButton(
                    containerColor = MaterialTheme.colorScheme.primary,
                    onClick = {
                        editorEvent = null
                        editorDraft = null
                        editorOccurrence = null
                        editorDate = if (viewMode == ViewMode.Month) selectedDay else LocalDate.now()
                        editorVisible = true
                    },
                ) {
                    Icon(Icons.Filled.Add, contentDescription = "New event")
                }
            },
        ) { padding ->
            Box(Modifier.padding(padding)) {
                when (viewMode) {
                    ViewMode.Agenda -> AgendaView(
                        dayEvents = days,
                        eventsLoaded = eventsLoaded,
                        secondaryTimezone = secondaryTimezone,
                        scrollToTodaySignal = scrollToTodaySignal,
                        onEventClick = ::openOccurrence,
                        onExtendPast = ::extendPast,
                        onExtendFuture = ::extendFuture,
                    )

                    ViewMode.Month -> MonthView(
                        dayEvents = days,
                        selectedDay = selectedDay,
                        onSelectedDayChange = { selectedDay = it },
                        secondaryTimezone = secondaryTimezone,
                        windowStart = windowStart,
                        windowEnd = windowEnd,
                        onExtendPast = ::extendPast,
                        onExtendFuture = ::extendFuture,
                        onEventClick = ::openOccurrence,
                    )
                }
            }
        }
    }

    if (editorVisible) {
        key(editorDraft) {
            EventEditorSheet(
                event = editorEvent,
                occurrence = editorOccurrence,
                initialDate = editorDate,
                draft = editorDraft,
                calendars = calendars,
                onDismiss = {
                    editorVisible = false
                    editorOccurrence = null
                    editorDraft = null
                },
                viewModel = viewModel,
            )
        }
    }

    scopeOccurrence?.let { occurrence ->
        AlertDialog(
            onDismissRequest = { scopeOccurrence = null },
            title = { Text("Repeating event") },
            text = { Text("Edit this occurrence or the entire series?") },
            confirmButton = {
                Row {
                    TextButton(onClick = { scopeOccurrence = null }) {
                        Text("Cancel")
                    }
                    TextButton(onClick = {
                        scopeOccurrence = null
                        editorEvent = occurrence.event
                        editorDraft = null
                        editorDate = occurrence.date
                        editorOccurrence = null
                        editorVisible = true
                    }) {
                        Text("All events")
                    }
                    TextButton(onClick = {
                        scopeOccurrence = null
                        editorEvent = occurrence.event
                        editorDraft = null
                        editorDate = occurrence.date
                        editorOccurrence = occurrence
                        editorVisible = true
                    }) {
                        Text("This event")
                    }
                }
            },
            dismissButton = {},
        )
    }
}

@Composable
private fun rememberInfiniteRotation(active: Boolean): Float {
    if (!active) return 0f
    val transition = rememberInfiniteTransition(label = "sync")
    val rotation by transition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(
                durationMillis = 900,
                easing = LinearEasing,
            ),
        ),
        label = "rotation",
    )
    return rotation
}
