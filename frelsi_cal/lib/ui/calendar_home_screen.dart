import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:intl/intl.dart';
import 'dart:ui';
import 'event_edit_screen.dart';
import 'settings_screen.dart';
import '../core/providers/providers.dart';
import '../core/db/database.dart';
import '../core/sync/sync_manager.dart';
import '../core/parsers/nlp_parser.dart';

class CalendarHomeScreen extends ConsumerStatefulWidget {
  const CalendarHomeScreen({super.key});

  @override
  ConsumerState<CalendarHomeScreen> createState() => _CalendarHomeScreenState();
}

class _CalendarHomeScreenState extends ConsumerState<CalendarHomeScreen> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  late List<DateTime> _days;
  int _initialIndex = 0;
  DateTime _selectedDate = DateTime.now();
  final TextEditingController _nlpController = TextEditingController();

  @override
  void dispose() {
    _nlpController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _generateDays();

    // Listen to scroll to update the top week strip if needed
    _itemPositionsListener.itemPositions.addListener(() {
      final positions = _itemPositionsListener.itemPositions.value;
      if (positions.isNotEmpty) {
        int visibleIndex = positions.first.index;
        if (visibleIndex >= 0 && visibleIndex < _days.length) {
          final topDate = _days[visibleIndex];
          if (topDate.day != _selectedDate.day ||
              topDate.month != _selectedDate.month) {
            // Can update UI state to mark current scrolling day
            // But we debounce it or keep it simple for now
          }
        }
      }
    });
  }

  void _generateDays() {
    // We will dynamically generate days in the builder now
    // but keep _initialIndex initialized safely
    _initialIndex = 0;
  }

  Color _parseColor(String? colorStr) {
    if (colorStr == null || colorStr.isEmpty) return Colors.blue;
    try {
      var hex = colorStr.replaceAll('#', '');
      if (hex.length == 6) hex = 'FF$hex';
      if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      }
      return Colors.blue;
    } catch (_) {
      return Colors.blue;
    }
  }

  void _scrollToToday() {
    _itemScrollController.scrollTo(
      index: _initialIndex,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
    setState(() => _selectedDate = DateTime.now());
  }

  void _submitNlpEvent(String text) {
    if (text.trim().isEmpty) return;

    final result = NlpParser.parse(text);
    _nlpController.clear();
    FocusScope.of(context).unfocus();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EventEditScreen(
        initialDate: result.startDate ?? DateTime.now(),
        prefilledTitle: result.title,
        prefilledStartDate: result.startDate,
        prefilledEndDate: result.endDate,
        prefilledLocation: result.location,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Agenda',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.today), onPressed: _scrollToToday),
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () {
              ref.read(syncManagerProvider).performSync();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Syncing with Radicale...'),
                  behavior: SnackBarBehavior.floating,
                ),
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
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final allEvents = snapshot.data ?? [];

                // Extract unique days with events
                final Set<DateTime> uniqueDaysSet = {};
                final todayNow = DateTime.now();
                final today = DateTime(
                  todayNow.year,
                  todayNow.month,
                  todayNow.day,
                );
                uniqueDaysSet.add(today);

                for (var e in allEvents) {
                  final localStart = e.event.startDate.toLocal();
                  uniqueDaysSet.add(
                    DateTime(localStart.year, localStart.month, localStart.day),
                  );
                }

                _days = uniqueDaysSet.toList()..sort();
                _initialIndex = _days.indexOf(today);
                if (_initialIndex < 0) _initialIndex = 0;

                return ScrollablePositionedList.builder(
                  itemCount: _days.length,
                  itemScrollController: _itemScrollController,
                  itemPositionsListener: _itemPositionsListener,
                  initialScrollIndex: _initialIndex,
                  itemBuilder: (context, index) {
                    final date = _days[index];
                    final dayEvents = allEvents.where((e) {
                      return e.event.startDate.toLocal().year == date.year &&
                          e.event.startDate.toLocal().month == date.month &&
                          e.event.startDate.toLocal().day == date.day;
                    }).toList();

                    // Sort day events by time
                    dayEvents.sort(
                      (a, b) => a.event.startDate.compareTo(b.event.startDate),
                    );

                    final isToday =
                        date.day == todayNow.day &&
                        date.month == todayNow.month &&
                        date.year == todayNow.year;

                    return _buildDayRow(context, date, dayEvents, isToday);
                  },
                );
              },
            ),
          ),

          // Smart Input Bar
          Align(
            alignment: Alignment.bottomCenter,
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ).copyWith(
                        bottom: MediaQuery.of(context).padding.bottom + 12,
                      ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.7),
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nlpController,
                          decoration: InputDecoration(
                            hintText: 'e.g., Lunch with Sarah tomorrow at 1pm',
                            hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                          ),
                          style: const TextStyle(color: Colors.white),
                          onSubmitted: _submitNlpEvent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        radius: 24,
                        child: IconButton(
                          icon: const Icon(
                            Icons.send,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: () => _submitNlpEvent(_nlpController.text),
                        ),
                      ),
                    ],
                  ),
                ),
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
                        .map((e) => _buildEventCard(context, e))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard(BuildContext context, EventWithCalendar item) {
    final event = item.event;
    final calendarColor = _parseColor(item.calendar?.color);

    // Glassmorphic effect on the card
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => EventEditScreen(
            event: event,
            initialDate: event.startDate.toLocal(),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  right: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                  left: BorderSide(
                    color: calendarColor,
                    width: 4,
                  ), // Calendar color strip
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${DateFormat('HH:mm').format(event.startDate.toLocal())} - ${DateFormat('HH:mm').format(event.endDate.toLocal())}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                  if (event.location != null && event.location!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 14,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            event.location!,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
