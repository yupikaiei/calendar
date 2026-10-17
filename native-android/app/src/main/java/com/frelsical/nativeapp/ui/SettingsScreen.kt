package com.frelsical.nativeapp.ui

import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.frelsical.nativeapp.data.CalendarRecord
import com.frelsical.nativeapp.notify.ReminderScheduler
import com.frelsical.nativeapp.ui.theme.parseCalendarColor
import java.time.ZoneId

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun SettingsScreen(
    viewModel: CalendarViewModel,
    calendars: List<CalendarRecord>,
    secondaryTimezone: String?,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }

    var serverUrl by rememberSaveable { mutableStateOf(viewModel.calDavServerUrl) }
    var username by rememberSaveable { mutableStateOf(viewModel.calDavUsername) }
    var password by remember { mutableStateOf("") }
    LaunchedEffect(Unit) { password = viewModel.readStoredPassword() }

    var showTimezonePicker by remember { mutableStateOf(false) }
    var showCreateCalendar by remember { mutableStateOf(false) }
    var renameTarget by remember { mutableStateOf<CalendarRecord?>(null) }
    var deleteTarget by remember { mutableStateOf<CalendarRecord?>(null) }
    var colorTarget by remember { mutableStateOf<CalendarRecord?>(null) }

    val importLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument(),
    ) { uri -> uri?.let(viewModel::importIcs) }

    LaunchedEffect(Unit) {
        viewModel.messages.collect { snackbarHostState.showSnackbar(it) }
    }

    val exactAlarmsAllowed = remember { viewModel.canScheduleExactAlarms() }
    val notificationsAllowed = remember { ReminderScheduler.notificationsAllowed(context) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.linearGradient(listOf(Color(0xFF1E1E2C), Color(0xFF12121D))),
            ),
    ) {
        Scaffold(
            containerColor = Color.Transparent,
            snackbarHost = { SnackbarHost(snackbarHostState) },
            topBar = {
                TopAppBar(
                    title = { Text("Settings") },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent),
                    navigationIcon = {
                        IconButton(onClick = onBack) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                        }
                    },
                )
            },
        ) { padding ->
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                item { SectionTitle("CalDAV Server Settings") }
                item {
                    OutlinedTextField(
                        value = serverUrl,
                        onValueChange = { serverUrl = it },
                        label = { Text("Server URL") },
                        singleLine = true,
                        placeholder = { Text("https://radicale.example.com") },
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                item {
                    OutlinedTextField(
                        value = username,
                        onValueChange = { username = it },
                        label = { Text("Username") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                item {
                    OutlinedTextField(
                        value = password,
                        onValueChange = { password = it },
                        label = { Text("Password") },
                        singleLine = true,
                        visualTransformation = PasswordVisualTransformation(),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                item {
                    Button(
                        onClick = {
                            if (serverUrl.isBlank() || username.isBlank()) {
                                viewModel.notify("Server URL and username are required.")
                            } else {
                                viewModel.saveCalDavSettings(serverUrl, username, password)
                            }
                        },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text("Save Connections")
                    }
                }

                item { HorizontalDivider(Modifier.padding(vertical = 8.dp)) }
                item { SectionTitle("Timezone Settings") }
                item {
                    OutlinedButton(
                        onClick = { showTimezonePicker = true },
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(12.dp),
                    ) {
                        Column(Modifier.fillMaxWidth()) {
                            Text(
                                "Secondary Timezone",
                                fontSize = 11.sp,
                                color = Color.White.copy(alpha = 0.6f),
                            )
                            Spacer(Modifier.height(2.dp))
                            Text(
                                secondaryTimezone ?: "None (Local Time Only)",
                                fontSize = 15.sp,
                                color = Color.White,
                            )
                        }
                    }
                }

                item { HorizontalDivider(Modifier.padding(vertical = 8.dp)) }
                item { SectionTitle("Notifications") }
                item {
                    Text(
                        text = if (notificationsAllowed) {
                            "Notifications are enabled."
                        } else {
                            "Notifications are disabled. Reminders will not be shown."
                        },
                        color = Color.White.copy(alpha = 0.7f),
                    )
                }
                if (!notificationsAllowed) {
                    item {
                        OutlinedButton(
                            onClick = {
                                context.startActivity(
                                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                        putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                                    },
                                )
                            },
                        ) { Text("Open notification settings") }
                    }
                }
                item {
                    Text(
                        text = if (exactAlarmsAllowed) {
                            "Exact alarms are allowed; reminders arrive on time."
                        } else {
                            "Exact alarms are not allowed; reminders may be delayed."
                        },
                        color = Color.White.copy(alpha = 0.7f),
                    )
                }
                if (!exactAlarmsAllowed && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    item {
                        OutlinedButton(
                            onClick = { openExactAlarmSettings(context) },
                        ) { Text("Allow exact alarms") }
                    }
                }

                item { HorizontalDivider(Modifier.padding(vertical = 8.dp)) }
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        SectionTitle("My Calendars", Modifier.weight(1f))
                        TextButton(onClick = { importLauncher.launch(arrayOf("*/*")) }) {
                            Text("Import .ics")
                        }
                        IconButton(onClick = { showCreateCalendar = true }) {
                            Icon(Icons.Filled.Add, contentDescription = "Create calendar")
                        }
                    }
                }
                if (calendars.isEmpty()) {
                    item {
                        Text(
                            "No calendars synced yet. Tap Sync on the main screen or create one.",
                            color = Color.White.copy(alpha = 0.7f),
                        )
                    }
                } else {
                    items(calendars, key = { it.id }) { calendar ->
                        CalendarRow(
                            calendar = calendar,
                            onColor = { colorTarget = calendar },
                            onRename = { renameTarget = calendar },
                            onDelete = { deleteTarget = calendar },
                        )
                    }
                }

                item { HorizontalDivider(Modifier.padding(vertical = 8.dp)) }
                item { SectionTitle("About") }
                item {
                    Text(
                        "Frelsi Cal Native · 1.0.0",
                        color = Color.White.copy(alpha = 0.7f),
                    )
                }
                item {
                    Text(
                        "Offline-first calendar with CalDAV sync, recurrence and reminders.",
                        color = Color.White.copy(alpha = 0.5f),
                        fontSize = 13.sp,
                    )
                }
            }
        }
    }

    if (showTimezonePicker) {
        TimezonePickerDialog(
            current = secondaryTimezone,
            onDismiss = { showTimezonePicker = false },
            onSelect = {
                viewModel.setSecondaryTimezone(it)
                showTimezonePicker = false
            },
        )
    }

    if (showCreateCalendar) {
        TextInputDialog(
            title = "New Calendar",
            label = "Calendar Name",
            initialValue = "",
            confirmLabel = "Create",
            onDismiss = { showCreateCalendar = false },
            onConfirm = {
                viewModel.createCalendar(it)
                showCreateCalendar = false
            },
        )
    }

    renameTarget?.let { calendar ->
        TextInputDialog(
            title = "Rename Calendar",
            label = "Calendar Name",
            initialValue = calendar.displayName,
            confirmLabel = "Save",
            onDismiss = { renameTarget = null },
            onConfirm = {
                viewModel.renameCalendar(calendar, it)
                renameTarget = null
            },
        )
    }

    deleteTarget?.let { calendar ->
        AlertDialog(
            onDismissRequest = { deleteTarget = null },
            title = { Text("Delete calendar?") },
            text = {
                Text(
                    if (calendar.urlPath.startsWith("/local/")) {
                        "Delete \"${calendar.displayName}\" and all of its events?"
                    } else {
                        "Delete \"${calendar.displayName}\" from the server and this device?"
                    },
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.deleteCalendar(calendar)
                    deleteTarget = null
                }) {
                    Text("Delete", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { deleteTarget = null }) { Text("Cancel") }
            },
        )
    }

    colorTarget?.let { calendar ->
        ColorPickerDialog(
            current = parseCalendarColor(calendar.color),
            onDismiss = { colorTarget = null },
            onSelect = { color ->
                viewModel.updateCalendarColor(calendar, color)
                colorTarget = null
            },
        )
    }
}

@Composable
private fun SectionTitle(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        modifier = modifier,
        fontSize = 18.sp,
        fontWeight = FontWeight.Bold,
        color = Color.White,
    )
}

@Composable
private fun CalendarRow(
    calendar: CalendarRecord,
    onColor: () -> Unit,
    onRename: () -> Unit,
    onDelete: () -> Unit,
) {
    var menuExpanded by remember { mutableStateOf(false) }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(16.dp)
                .clip(CircleShape)
                .background(parseCalendarColor(calendar.color)),
        )
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(calendar.displayName, color = Color.White, fontSize = 16.sp)
            Text(
                calendar.urlPath,
                color = Color.White.copy(alpha = 0.5f),
                fontSize = 12.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Box {
            IconButton(onClick = { menuExpanded = true }) {
                Icon(Icons.Filled.MoreVert, contentDescription = "Calendar options")
            }
            DropdownMenu(
                expanded = menuExpanded,
                onDismissRequest = { menuExpanded = false },
            ) {
                DropdownMenuItem(text = { Text("Change Color") }, onClick = {
                    menuExpanded = false
                    onColor()
                })
                DropdownMenuItem(text = { Text("Rename") }, onClick = {
                    menuExpanded = false
                    onRename()
                })
                DropdownMenuItem(text = { Text("Delete") }, onClick = {
                    menuExpanded = false
                    onDelete()
                })
            }
        }
    }
}

@Composable
private fun TimezonePickerDialog(
    current: String?,
    onDismiss: () -> Unit,
    onSelect: (String?) -> Unit,
) {
    var query by remember { mutableStateOf("") }
    val zones = remember {
        listOf<String?>(null) + ZoneId.getAvailableZoneIds().sorted()
    }
    val filtered = remember(query) {
        if (query.isBlank()) zones else zones.filter { it?.contains(query, ignoreCase = true) == true }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Secondary Timezone") },
        text = {
            Column {
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    label = { Text("Search") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(8.dp))
                LazyColumn(modifier = Modifier.height(360.dp)) {
                    items(filtered) { zone ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onSelect(zone) }
                                .padding(vertical = 10.dp, horizontal = 4.dp),
                        ) {
                            Text(
                                text = zone ?: "None (Local Time Only)",
                                color = if (zone == current) {
                                    MaterialTheme.colorScheme.primary
                                } else {
                                    Color.White
                                },
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}

@Composable
private fun TextInputDialog(
    title: String,
    label: String,
    initialValue: String,
    confirmLabel: String,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit,
) {
    var value by remember { mutableStateOf(initialValue) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            OutlinedTextField(
                value = value,
                onValueChange = { value = it },
                label = { Text(label) },
                singleLine = true,
            )
        },
        confirmButton = {
            TextButton(onClick = { if (value.isNotBlank()) onConfirm(value.trim()) }) {
                Text(confirmLabel)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ColorPickerDialog(
    current: Color,
    onDismiss: () -> Unit,
    onSelect: (Color) -> Unit,
) {
    val colors = remember {
        listOf(
            0xFFF44336, 0xFFE91E63, 0xFF9C27B0, 0xFF673AB7,
            0xFF3F51B5, 0xFF2196F3, 0xFF03A9F4, 0xFF00BCD4,
            0xFF009688, 0xFF4CAF50, 0xFF8BC34A, 0xFFCDDC39,
            0xFFFFEB3B, 0xFFFFC107, 0xFFFF9800, 0xFFFF5722,
            0xFF795548, 0xFF9E9E9E, 0xFF607D8B, 0xFF000000,
        ).map { Color(it) }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Select Calendar Color") },
        text = {
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                colors.forEach { color ->
                    Box(
                        modifier = Modifier
                            .size(40.dp)
                            .clip(CircleShape)
                            .background(color)
                            .clickable { onSelect(color) },
                        contentAlignment = Alignment.Center,
                    ) {
                        if (color == current) {
                            Icon(
                                Icons.Filled.Check,
                                contentDescription = "Current color",
                                tint = Color.White,
                                modifier = Modifier.size(18.dp),
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}
