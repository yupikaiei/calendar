import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/db/database.dart';
import 'event_card.dart';
import 'utils.dart';

class MonthView extends StatefulWidget {
  final Map<DateTime, List<EventWithCalendar>> dayEventsMap;

  const MonthView({super.key, required this.dayEventsMap});

  @override
  State<MonthView> createState() => _MonthViewState();
}

class _MonthViewState extends State<MonthView> {
  late DateTime _currentMonth;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month);
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  void _goToPreviousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
    });
  }

  void _goToNextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
    });
  }

  void _goToToday() {
    final now = DateTime.now();
    setState(() {
      _currentMonth = DateTime(now.year, now.month);
      _selectedDay = DateTime(now.year, now.month, now.day);
    });
  }

  List<Color> _colorsForDay(DateTime day) {
    final events = widget.dayEventsMap[day];
    if (events == null || events.isEmpty) return [];
    final seen = <int>{};
    final colors = <Color>[];
    for (final e in events) {
      final c = parseColor(e.calendar?.color);
      if (seen.add(c.toARGB32())) {
        colors.add(c);
        if (colors.length >= 4) break;
      }
    }
    return colors;
  }

  @override
  Widget build(BuildContext context) {
    final todayNow = DateTime.now();
    final today = DateTime(todayNow.year, todayNow.month, todayNow.day);

    return Column(
      children: [
        _buildMonthGrid(context, today),
        const Divider(color: Colors.white12, height: 1),
        Expanded(child: _buildDayAgenda(context)),
      ],
    );
  }

  Widget _buildMonthGrid(BuildContext context, DateTime today) {
    final year = _currentMonth.year;
    final month = _currentMonth.month;
    final firstOfMonth = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    // Monday = 1, Sunday = 7 — shift so Monday is column 0
    final startWeekday = (firstOfMonth.weekday - 1) % 7;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Month header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.white70),
                onPressed: _goToPreviousMonth,
              ),
              GestureDetector(
                onTap: _goToToday,
                child: Text(
                  DateFormat('MMMM yyyy').format(_currentMonth),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: Colors.white70),
                onPressed: _goToNextMonth,
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Weekday headers
          Row(
            children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[500],
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 4),
          // Day cells grid
          ..._buildWeekRows(year, month, daysInMonth, startWeekday, today),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  List<Widget> _buildWeekRows(
    int year,
    int month,
    int daysInMonth,
    int startWeekday,
    DateTime today,
  ) {
    final rows = <Widget>[];
    int day = 1 - startWeekday; // may start negative for leading blanks
    while (day <= daysInMonth) {
      final cells = <Widget>[];
      for (int col = 0; col < 7; col++) {
        if (day < 1 || day > daysInMonth) {
          cells.add(const Expanded(child: SizedBox(height: 52)));
        } else {
          final date = DateTime(year, month, day);
          final isToday = date == today;
          final isSelected = _selectedDay != null && date == _selectedDay;
          final colors = _colorsForDay(date);
          cells.add(
            Expanded(child: _buildDayCell(date, isToday, isSelected, colors)),
          );
        }
        day++;
      }
      rows.add(Row(children: cells));
    }
    return rows;
  }

  Widget _buildDayCell(
    DateTime date,
    bool isToday,
    bool isSelected,
    List<Color> colors,
  ) {
    return GestureDetector(
      onTap: () => setState(() => _selectedDay = date),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isToday
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                        isToday || isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                    color: isToday ? Colors.white : Colors.white70,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            // Color dots row
            if (colors.isNotEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: colors
                    .map(
                      (c) => Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                    .toList(),
              )
            else
              const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _buildDayAgenda(BuildContext context) {
    if (_selectedDay == null) {
      return const Center(
        child: Text(
          'Tap a day to see events',
          style: TextStyle(color: Colors.white54, fontSize: 15),
        ),
      );
    }

    final events = widget.dayEventsMap[_selectedDay!] ?? [];
    final formattedDate = DateFormat('EEEE, MMMM d').format(_selectedDay!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            formattedDate,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: events.isEmpty
              ? Center(
                  child: Text(
                    'No events',
                    style: TextStyle(color: Colors.grey[500], fontSize: 14),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: events.length,
                  itemBuilder: (context, index) =>
                      EventCard(item: events[index]),
                ),
        ),
      ],
    );
  }
}
