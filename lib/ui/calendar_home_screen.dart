import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:intl/intl.dart';

import 'dart:async';
import 'event_card.dart';
import 'event_edit_screen.dart';
import 'month_view.dart';
import 'settings_screen.dart';
import '../core/providers/providers.dart';
import '../core/db/database.dart';
import '../core/sync/sync_manager.dart';
import 'package:rrule/rrule.dart';

class CalendarHomeScreen extends ConsumerStatefulWidget {
  const CalendarHomeScreen({super.key});

  @override
  ConsumerState<CalendarHomeScreen> createState() => _CalendarHomeScreenState();
}

enum _ViewMode { agenda, month }

class _CalendarHomeScreenState extends ConsumerState<CalendarHomeScreen> {
  static final _logger = Logger('CalendarHomeScreen');
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  late List<DateTime> _days;
  int _initialIndex = 0;
  DateTime _selectedDate = DateTime.now();
  Timer? _scrollDebounce;
  _ViewMode _viewMode = _ViewMode.agenda;

  // Cached recurrence expansion results
  List<EventWithCalendar>? _lastAllEvents;
  Map<DateTime, List<EventWithCalendar>>? _cachedDayEventsMap;
  List<DateTime>? _cachedDays;

  @override
  void dispose() {
    _scrollDebounce?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _generateDays();

    // Listen to scroll to update the top week strip if needed (debounced)
    _itemPositionsListener.itemPositions.addListener(() {
      _scrollDebounce?.cancel();
      _scrollDebounce = Timer(const Duration(milliseconds: 100), () {
        final positions = _itemPositionsListener.itemPositions.value;
        if (positions.isNotEmpty) {
          int visibleIndex = positions.first.index;
          if (visibleIndex >= 0 && visibleIndex < _days.length) {
            final topDate = _days[visibleIndex];
            if (topDate.day != _selectedDate.day ||
                topDate.month != _selectedDate.month) {
              // Can update UI state to mark current scrolling day
            }
          }
        }
      });
    });
  }

  void _generateDays() {
    // We will dynamically generate days in the builder now
    // but keep _initialIndex initialized safely
    _initialIndex = 0;
  }

  /// Expands recurrence rules and builds the day-events map.
  /// Extracted from build() so this expensive work only runs when data changes.
  Map<DateTime, List<EventWithCalendar>> _expandRecurrences(
    List<EventWithCalendar> allEvents,
  ) {
    final todayNow = DateTime.now();
    final today = DateTime(todayNow.year, todayNow.month, todayNow.day);
    final horizonStart = today.subtract(const Duration(days: 365 * 2));
    final horizonEnd = today.add(const Duration(days: 365 * 5));

    final Set<DateTime> uniqueDaysSet = {today};
    final Map<DateTime, List<EventWithCalendar>> dayEventsMap = {};

    void addDayEvent(DateTime day, EventWithCalendar item) {
      dayEventsMap.putIfAbsent(day, () => []).add(item);
    }

    for (var item in allEvents) {
      final e = item.event;
      final localStart = e.startDate.toLocal();
      final originalDay = DateTime(
        localStart.year,
        localStart.month,
        localStart.day,
      );

      uniqueDaysSet.add(originalDay);
      addDayEvent(originalDay, item);

      if (e.recurrenceRule != null &&
          e.recurrenceRule!.isNotEmpty &&
          e.recurrenceRule!.contains('FREQ=')) {
        try {
          final rruleStr = e.recurrenceRule!.startsWith('RRULE:')
              ? e.recurrenceRule!
              : 'RRULE:${e.recurrenceRule!}';
          final rrule = RecurrenceRule.fromString(rruleStr);
          final instances = rrule.getInstances(
            start: e.startDate.isUtc ? e.startDate : e.startDate.toUtc(),
            after: horizonStart.toUtc(),
            before: horizonEnd.toUtc(),
          );
          for (final inst in instances) {
            final localInst = inst.toLocal();
            final instDay = DateTime(
              localInst.year,
              localInst.month,
              localInst.day,
            );

            if (instDay != originalDay) {
              uniqueDaysSet.add(instDay);
              final offset = localInst.difference(localStart);
              final newEvent = e.copyWith(
                startDate: e.startDate.add(offset),
                endDate: e.endDate.add(offset),
              );
              addDayEvent(
                instDay,
                EventWithCalendar(event: newEvent, calendar: item.calendar),
              );
            }
          }
        } catch (err) {
          _logger.warning(
            'Recurrence rule parsing failed for rule "${e.recurrenceRule}": $err',
          );
        }
      }
    }

    for (final dayEvents in dayEventsMap.values) {
      dayEvents.sort(
        (a, b) => a.event.startDate.compareTo(b.event.startDate),
      );
    }

    _cachedDays = uniqueDaysSet.toList()..sort();
    return dayEventsMap;
  }

  void _showModernSnackBar(
    BuildContext context,
    String message, {
    IconData icon = Icons.info_outline,
    Duration duration = const Duration(seconds: 4),
  }) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
        duration: duration,
        content: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: Theme.of(context).colorScheme.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
        ),
      ),
    );
  }

  void _scrollToToday() {
    _itemScrollController.scrollTo(
      index: _initialIndex,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
    setState(() => _selectedDate = DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          _viewMode == _ViewMode.agenda ? 'Agenda' : 'Month',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _viewMode == _ViewMode.agenda
                  ? Icons.calendar_view_month
                  : Icons.view_agenda,
            ),
            tooltip: _viewMode == _ViewMode.agenda
                ? 'Month view'
                : 'Agenda view',
            onPressed: () {
              setState(() {
                _viewMode = _viewMode == _ViewMode.agenda
                    ? _ViewMode.month
                    : _ViewMode.agenda;
              });
            },
          ),
          if (_viewMode == _ViewMode.agenda)
            IconButton(icon: const Icon(Icons.today), onPressed: _scrollToToday),
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () {
              ref.read(syncManagerProvider).performSync();
              _showModernSnackBar(
                context,
                'Syncing with Radicale...',
                icon: Icons.sync,
                duration: const Duration(seconds: 2),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Background Gradient
          Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1E1E2C), Color(0xFF12121D)],
                  ),
                ),
              ),

              SafeArea(
                child: StreamBuilder<List<EventWithCalendar>>(
                  stream: ref.watch(databaseProvider).watchEventsWithCalendars(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        _cachedDayEventsMap == null) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final allEvents = snapshot.data ?? [];

                    // Only recompute recurrence expansion when data changes
                    final Map<DateTime, List<EventWithCalendar>> dayEventsMap;
                    if (!identical(allEvents, _lastAllEvents)) {
                      _lastAllEvents = allEvents;
                      dayEventsMap = _expandRecurrences(allEvents);
                      _cachedDayEventsMap = dayEventsMap;
                    } else {
                      dayEventsMap = _cachedDayEventsMap!;
                    }

                    final todayNow = DateTime.now();
                    final today = DateTime(
                      todayNow.year,
                      todayNow.month,
                      todayNow.day,
                    );

                    _days = _cachedDays ?? (dayEventsMap.keys.toList()..sort());

                    _initialIndex = _days.indexOf(today);
                    if (_initialIndex < 0) _initialIndex = 0;

                    if (_viewMode == _ViewMode.month) {
                      return MonthView(dayEventsMap: dayEventsMap);
                    }

                    return ScrollablePositionedList.builder(
                      itemCount: _days.length,
                      itemScrollController: _itemScrollController,
                      itemPositionsListener: _itemPositionsListener,
                      initialScrollIndex: _initialIndex,
                      itemBuilder: (context, index) {
                        final date = _days[index];
                        final dayEvents = dayEventsMap[date] ?? [];
                        final isToday = date.day == todayNow.day &&
                            date.month == todayNow.month &&
                            date.year == todayNow.year;

                        return _buildDayRow(context, date, dayEvents, isToday);
                      },
                    );
                  },
                ),
              ),


              // Floating Action Button
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom + 80,
                  ),
                  child: FloatingActionButton(
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (context) => const EventEditScreen(),
                      );
                    },
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: const Icon(Icons.add, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildDayRow(
    BuildContext context,
    DateTime date,
    List<EventWithCalendar> events,
    bool isToday,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date Column
          SizedBox(
            width: 60,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  DateFormat('EEE').format(date).toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isToday
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey[500],
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 36,
                  height: 36,
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
                        fontSize: 18,
                        fontWeight: isToday
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isToday ? Colors.white : Colors.white70,
                      ),
                    ),
                  ),
                ),
                if (date.month != DateTime.now().month ||
                    date.year != DateTime.now().year)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      DateFormat('MMM yy').format(date).toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[500],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Events Column
          Expanded(
            child: events.isEmpty
                ? const SizedBox(
                    height: 60,
                  ) // Spacer for empty days to maintain rhythm
                : Column(
                    children: events
                        .map((e) => EventCard(item: e))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

