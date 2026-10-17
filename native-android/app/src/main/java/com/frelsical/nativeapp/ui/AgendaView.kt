package com.frelsical.nativeapp.ui

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.net.toUri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.frelsical.nativeapp.data.Occurrence
import com.frelsical.nativeapp.ui.theme.parseCalendarColor
import java.time.LocalDate
import java.time.ZoneId

@Composable
fun AgendaView(
    dayEvents: Map<LocalDate, List<Occurrence>>,
    secondaryTimezone: String?,
    scrollToTodaySignal: Int,
    onEventClick: (Occurrence) -> Unit,
    onExtendPast: () -> Unit,
    onExtendFuture: () -> Unit,
) {
    val days = remember(dayEvents) { dayEvents.keys.sorted() }
    val today = LocalDate.now()
    val todayIndex = days.indexOf(today).coerceAtLeast(0)
    val listState = rememberLazyListState(initialFirstVisibleItemIndex = todayIndex + 1)

    LaunchedEffect(scrollToTodaySignal) {
        if (scrollToTodaySignal > 0) {
            listState.animateScrollToItem(todayIndex + 1)
        }
    }

    LazyColumn(
        state = listState,
        contentPadding = PaddingValues(top = 8.dp, bottom = 120.dp),
    ) {
        item(key = "load-past") {
            Box(
                modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                contentAlignment = Alignment.Center,
            ) {
                TextButton(onClick = onExtendPast) {
                    Text("Load earlier events")
                }
            }
        }
        items(days, key = { it.toEpochDay() }) { date ->
            DayRow(
                date = date,
                events = dayEvents[date].orEmpty(),
                secondaryTimezone = secondaryTimezone,
                onEventClick = onEventClick,
            )
        }
        item(key = "load-future") {
            Box(
                modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                contentAlignment = Alignment.Center,
            ) {
                TextButton(onClick = onExtendFuture) {
                    Text("Load more events")
                }
            }
        }
    }
}

@Composable
private fun DayRow(
    date: LocalDate,
    events: List<Occurrence>,
    secondaryTimezone: String?,
    onEventClick: (Occurrence) -> Unit,
) {
    val today = LocalDate.now()
    val isToday = date == today

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        Column(
            modifier = Modifier.width(60.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = DateFormats.weekdayShort(date),
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                color = if (isToday) MaterialTheme.colorScheme.primary else Color(0xFF8A8A9B),
            )
            Spacer(Modifier.height(4.dp))
            Box(
                modifier = Modifier
                    .width(36.dp)
                    .height(36.dp)
                    .clip(RoundedCornerShape(18.dp))
                    .background(if (isToday) MaterialTheme.colorScheme.primary else Color.Transparent),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = date.dayOfMonth.toString(),
                    fontSize = 18.sp,
                    fontWeight = if (isToday) FontWeight.Bold else FontWeight.Normal,
                    color = if (isToday) Color.White else Color.White.copy(alpha = 0.75f),
                )
            }
            if (date.month != today.month || date.year != today.year) {
                Spacer(Modifier.height(4.dp))
                Text(
                    text = DateFormats.monthShort(date),
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color(0xFF8A8A9B),
                )
            }
        }

        Spacer(Modifier.width(16.dp))

        Column(modifier = Modifier.weight(1f)) {
            if (events.isEmpty()) {
                Spacer(Modifier.height(60.dp))
            } else {
                events.forEach { occurrence ->
                    EventCard(
                        occurrence = occurrence,
                        secondaryTimezone = secondaryTimezone,
                        onClick = { onEventClick(occurrence) },
                    )
                }
            }
        }
    }
}

private val meetingUrlRegex = Regex(
    """(https?://(?:www\.)?(?:zoom\.us|meet\.google\.com|teams\.microsoft\.com|webex\.com)[^\s]+)""",
)

@Composable
fun EventCard(
    occurrence: Occurrence,
    secondaryTimezone: String?,
    onClick: () -> Unit,
) {
    val event = occurrence.event
    val calendarColor = parseCalendarColor(occurrence.calendar?.color)
    val isPast = occurrence.end < System.currentTimeMillis()
    val context = LocalContext.current
    val meetingUrl = remember(event.description) {
        event.description?.let { meetingUrlRegex.find(it)?.groupValues?.get(0) }
    }
    val zone = remember { ZoneId.systemDefault() }
    val secondaryLabel = remember(occurrence.start, occurrence.end, secondaryTimezone) {
        val timezone = secondaryTimezone?.let { runCatching { ZoneId.of(it) }.getOrNull() }
        if (event.allDay) null else DateFormats.secondaryTimeLabel(occurrence.start, occurrence.end, timezone)
    }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 12.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(Color.White.copy(alpha = 0.08f))
            .border(
                width = 1.dp,
                color = Color.White.copy(alpha = 0.1f),
                shape = RoundedCornerShape(16.dp),
            )
            .clickable(onClick = onClick),
    ) {
        Row(
            modifier = Modifier
                .height(IntrinsicSize.Min)
                .alpha(if (isPast) 0.55f else 1f),
        ) {
            Box(
                Modifier
                    .width(4.dp)
                    .fillMaxHeight()
                    .background(calendarColor),
            )
            Column(Modifier.padding(16.dp)) {
                Text(
                    text = event.title,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.White,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Spacer(Modifier.height(4.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Filled.DateRange,
                        contentDescription = null,
                        tint = Color.White.copy(alpha = 0.6f),
                        modifier = Modifier.width(14.dp).height(14.dp),
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(
                        text = DateFormats.rangeLabel(occurrence.start, occurrence.end, event.allDay, zone),
                        fontSize = 14.sp,
                        color = Color.White.copy(alpha = 0.6f),
                    )
                }
                if (secondaryLabel != null) {
                    Spacer(Modifier.height(2.dp))
                    Text(
                        text = secondaryLabel,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium,
                        color = MaterialTheme.colorScheme.secondary,
                    )
                }
                event.location?.takeIf { it.isNotBlank() }?.let { location ->
                    Spacer(Modifier.height(4.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            Icons.Filled.LocationOn,
                            contentDescription = null,
                            tint = Color.White.copy(alpha = 0.6f),
                            modifier = Modifier.width(14.dp).height(14.dp),
                        )
                        Spacer(Modifier.width(4.dp))
                        Text(
                            text = location,
                            fontSize = 14.sp,
                            color = Color.White.copy(alpha = 0.6f),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }

                if (meetingUrl != null || !event.location.isNullOrBlank()) {
                    Spacer(Modifier.height(12.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (meetingUrl != null) {
                            Button(
                                onClick = { openUrl(context, meetingUrl) },
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = MaterialTheme.colorScheme.primary,
                                ),
                                contentPadding = PaddingValues(horizontal = 14.dp, vertical = 8.dp),
                            ) {
                                Text("Join Meeting", fontSize = 14.sp)
                            }
                        }
                        event.location?.takeIf { it.isNotBlank() }?.let { location ->
                            OutlinedButton(
                                onClick = {
                                    openUrl(
                                        context,
                                        "https://maps.google.com/?q=${Uri.encode(location)}",
                                    )
                                },
                                contentPadding = PaddingValues(horizontal = 14.dp, vertical = 8.dp),
                            ) {
                                Text("Map", fontSize = 14.sp)
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun openUrl(context: Context, url: String) {
    try {
        context.startActivity(Intent(Intent.ACTION_VIEW, url.toUri()))
    } catch (_: ActivityNotFoundException) {
        // No app can handle the link; ignore silently.
    }
}
