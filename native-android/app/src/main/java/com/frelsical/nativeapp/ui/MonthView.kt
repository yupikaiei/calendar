package com.frelsical.nativeapp.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.frelsical.nativeapp.data.Occurrence
import com.frelsical.nativeapp.ui.theme.parseCalendarColor
import java.time.LocalDate
import java.time.YearMonth

@Composable
fun MonthView(
    dayEvents: Map<LocalDate, List<Occurrence>>,
    selectedDay: LocalDate,
    onSelectedDayChange: (LocalDate) -> Unit,
    secondaryTimezone: String?,
    windowStart: LocalDate,
    windowEnd: LocalDate,
    onExtendPast: () -> Unit,
    onExtendFuture: () -> Unit,
    onEventClick: (Occurrence) -> Unit,
) {
    var monthCursor by rememberSaveable { mutableStateOf(YearMonth.from(selectedDay).toString()) }
    val currentMonth = remember(monthCursor) { YearMonth.parse(monthCursor) }

    Column(Modifier.fillMaxWidth()) {
        MonthHeader(
            currentMonth = currentMonth,
            onPrevious = {
                val previous = currentMonth.minusMonths(1)
                monthCursor = previous.toString()
                if (!previous.atDay(1).isAfter(windowStart)) onExtendPast()
            },
            onNext = {
                val next = currentMonth.plusMonths(1)
                monthCursor = next.toString()
                if (!next.atEndOfMonth().isBefore(windowEnd)) onExtendFuture()
            },
            onToday = {
                val today = LocalDate.now()
                monthCursor = YearMonth.from(today).toString()
                onSelectedDayChange(today)
            },
        )
        WeekdayHeader()
        MonthGrid(
            currentMonth = currentMonth,
            selectedDay = selectedDay,
            dayEvents = dayEvents,
            onSelectedDayChange = onSelectedDayChange,
        )
        Spacer(Modifier.height(4.dp))
        HorizontalDivider(color = Color.White.copy(alpha = 0.08f))
        DayAgenda(
            selectedDay = selectedDay,
            events = dayEvents[selectedDay].orEmpty(),
            secondaryTimezone = secondaryTimezone,
            onEventClick = onEventClick,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun MonthHeader(
    currentMonth: YearMonth,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
    onToday: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onPrevious) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = "Previous month")
        }
        Text(
            text = DateFormats.monthYear(currentMonth.atDay(1)),
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold,
            color = Color.White,
            modifier = Modifier.clickable(onClick = onToday),
        )
        IconButton(onClick = onNext) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = "Next month")
        }
    }
}

@Composable
private fun WeekdayHeader() {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp),
    ) {
        for (label in listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")) {
            Box(
                modifier = Modifier.weight(1f),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = label,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color(0xFF8A8A9B),
                )
            }
        }
    }
}

@Composable
private fun MonthGrid(
    currentMonth: YearMonth,
    selectedDay: LocalDate,
    dayEvents: Map<LocalDate, List<Occurrence>>,
    onSelectedDayChange: (LocalDate) -> Unit,
) {
    val today = LocalDate.now()
    val firstOfMonth = currentMonth.atDay(1)
    val leadingBlanks = firstOfMonth.dayOfWeek.value - 1
    val daysInMonth = currentMonth.lengthOfMonth()
    val totalCells = leadingBlanks + daysInMonth
    val weekCount = (totalCells + 6) / 7

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp),
    ) {
        for (week in 0 until weekCount) {
            Row(Modifier.fillMaxWidth()) {
                for (column in 0 until 7) {
                    val dayNumber = week * 7 + column - leadingBlanks + 1
                    if (dayNumber < 1 || dayNumber > daysInMonth) {
                        Spacer(Modifier.weight(1f).height(52.dp))
                    } else {
                        val date = currentMonth.atDay(dayNumber)
                        DayCell(
                            date = date,
                            isToday = date == today,
                            isSelected = date == selectedDay,
                            events = dayEvents[date].orEmpty(),
                            onClick = { onSelectedDayChange(date) },
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun DayCell(
    date: LocalDate,
    isToday: Boolean,
    isSelected: Boolean,
    events: List<Occurrence>,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val dotColors = remember(events) {
        events.map { parseCalendarColor(it.calendar?.color) }.distinct().take(4)
    }

    Box(
        modifier = modifier
            .height(52.dp)
            .padding(1.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(if (isSelected) Color.White.copy(alpha = 0.08f) else Color.Transparent)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Box(
                modifier = Modifier
                    .size(28.dp)
                    .clip(CircleShape)
                    .background(if (isToday) MaterialTheme.colorScheme.primary else Color.Transparent),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = date.dayOfMonth.toString(),
                    fontSize = 14.sp,
                    fontWeight = if (isToday || isSelected) FontWeight.Bold else FontWeight.Normal,
                    color = if (isToday) Color.White else Color.White.copy(alpha = 0.75f),
                )
            }
            Spacer(Modifier.height(2.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                if (dotColors.isEmpty()) {
                    Spacer(Modifier.height(6.dp))
                } else {
                    for (color in dotColors) {
                        Box(
                            Modifier
                                .size(6.dp)
                                .clip(CircleShape)
                                .background(color),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun DayAgenda(
    selectedDay: LocalDate,
    events: List<Occurrence>,
    secondaryTimezone: String?,
    onEventClick: (Occurrence) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxWidth()) {
        Text(
            text = DateFormats.fullDate(selectedDay),
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White,
            modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 8.dp),
        )
        if (events.isEmpty()) {
            Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
                Text("No events", color = Color(0xFF8A8A9B), fontSize = 14.sp)
            }
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxWidth(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(
                    start = 16.dp,
                    end = 16.dp,
                    bottom = 120.dp,
                ),
            ) {
                items(events, key = { "${it.event.id}_${it.start}" }) { occurrence ->
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
