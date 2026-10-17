package com.frelsical.nativeapp.ui

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.frelsical.nativeapp.data.Event
import com.frelsical.nativeapp.ical.RecurrenceExpander
import java.time.LocalDate
import java.time.ZoneId

private enum class ViewMode { Agenda, Month }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CalendarApp(viewModel: CalendarViewModel = viewModel()) {
    val events by viewModel.events.collectAsStateWithLifecycle()
    val calendars by viewModel.calendars.collectAsStateWithLifecycle()
    val secondaryTimezone by viewModel.secondaryTimezone.collectAsStateWithLifecycle()
    val syncing by viewModel.syncing.collectAsStateWithLifecycle()

    val snackbarHostState = remember { SnackbarHostState() }
    var viewMode by rememberSaveable { mutableStateOf(ViewMode.Agenda) }
    var selectedDay by rememberSaveable { mutableStateOf(LocalDate.now()) }
    var showSettings by rememberSaveable { mutableStateOf(false) }
    var scrollToTodaySignal by rememberSaveable { mutableIntStateOf(0) }

    var editorVisible by remember { mutableStateOf(false) }
    var editorEvent by remember { mutableStateOf<Event?>(null) }
    var editorDate by remember { mutableStateOf(LocalDate.now()) }

    LaunchedEffect(Unit) {
        viewModel.messages.collect { message ->
            snackbarHostState.showSnackbar(message)
        }
    }

    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) viewModel.sync(showMessage = false)
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    val zone = remember { ZoneId.systemDefault() }
    val days = remember(events, zone) {
        val today = LocalDate.now(zone)
        RecurrenceExpander.expand(
            events = events,
            windowStart = today.minusYears(2).atStartOfDay(zone).toInstant(),
            windowEnd = today.plusYears(5).atStartOfDay(zone).toInstant(),
            zone = zone,
        )
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
                        val rotation = rememberInfiniteRotation()
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
            },
            floatingActionButton = {
                FloatingActionButton(
                    containerColor = MaterialTheme.colorScheme.primary,
                    onClick = {
                        editorEvent = null
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
                        secondaryTimezone = secondaryTimezone,
                        scrollToTodaySignal = scrollToTodaySignal,
                        onEventClick = { occurrence ->
                            editorEvent = occurrence.event
                            editorDate = occurrence.date
                            editorVisible = true
                        },
                    )

                    ViewMode.Month -> MonthView(
                        dayEvents = days,
                        selectedDay = selectedDay,
                        onSelectedDayChange = { selectedDay = it },
                        secondaryTimezone = secondaryTimezone,
                        onEventClick = { occurrence ->
                            editorEvent = occurrence.event
                            editorDate = occurrence.date
                            editorVisible = true
                        },
                    )
                }
            }
        }
    }

    if (editorVisible) {
        EventEditorSheet(
            event = editorEvent,
            initialDate = editorDate,
            calendars = calendars,
            onDismiss = { editorVisible = false },
            viewModel = viewModel,
        )
    }
}

@Composable
private fun rememberInfiniteRotation(): Float {
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
