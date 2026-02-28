import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui';
import 'event_edit_screen.dart';
import 'settings_screen.dart';
import '../core/providers/providers.dart';
import '../core/db/database.dart';
import '../core/sync/sync_manager.dart';
import '../core/parsers/nlp_parser.dart';
import 'package:timezone/standalone.dart' as tz;
import 'package:rrule/rrule.dart';

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
  bool _hasText = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _nlpController.removeListener(_onTextChanged);
    _nlpController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {
      _hasText = _nlpController.text.isNotEmpty;
    });
  }

  @override
  void initState() {
    super.initState();
    _nlpController.addListener(_onTextChanged);
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
        content: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.8),
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
        ),
      ),
    );
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

  String? _extractMeetingUrl(String? description) {
    if (description == null || description.isEmpty) return null;
    final regex = RegExp(
      r'(https?:\/\/(?:www\.)?(?:zoom\.us|meet\.google\.com|teams\.microsoft\.com|webex\.com)[^\s]+)',
    );
    final match = regex.firstMatch(description);
    return match?.group(0);
  }

  void _submitNlpEvent(String text) async {
    if (text.trim().isEmpty || _isLoading) return;

    setState(() => _isLoading = true);

    _showModernSnackBar(
      context,
      'Extracting details...',
      icon: Icons.auto_awesome,
      duration: const Duration(milliseconds: 500),
    );

    final db = ref.read(databaseProvider);
    final events = await db.getEvents();
    final now = DateTime.now();
    final recentEvents = events
        .where(
          (e) =>
              e.startDate.isAfter(now.subtract(const Duration(days: 1))) &&
              e.startDate.isBefore(now.add(const Duration(days: 14))),
        )
        .toList();

    final contextStr = recentEvents
        .map((e) => "- ${e.title}: ${e.startDate} to ${e.endDate}")
        .join("\\n");

    debugPrint("RAG Context Sent to LLM: \\n$contextStr");

    final result = await NlpParser.parse(text, contextEvents: contextStr);

    if (!mounted) return;

    setState(() => _isLoading = false);

    _nlpController.clear();
    FocusScope.of(context).unfocus();

    _showModernSnackBar(
      context,
      result.assistantResponse,
      icon: Icons.check_circle_outline,
      duration: const Duration(seconds: 4),
    );

    if (result.intent == NlpIntent.create || result.intent == NlpIntent.edit) {
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
    } else if (result.intent == NlpIntent.delete &&
        result.targetEventTitle != null) {
      final toDelete = events
          .where(
            (e) => e.title.toLowerCase().contains(
              result.targetEventTitle!.toLowerCase(),
            ),
          )
          .firstOrNull;
      if (toDelete != null) {
        await db.delete(db.events).delete(toDelete);
        // Note: For true CalDAV sync we'd also insert into DeletedEvents table,
        // but local delete is immediately reflected in the UI.
      }
    }
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

                final horizonStart = today.subtract(
                  const Duration(days: 365 * 2),
                );
                final horizonEnd = today.add(const Duration(days: 365 * 5));
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
                      e.recurrenceRule!.isNotEmpty) {
                    try {
                      final rruleStr = e.recurrenceRule!.startsWith('RRULE:')
                          ? e.recurrenceRule!
                          : 'RRULE:${e.recurrenceRule!}';
                      final rrule = RecurrenceRule.fromString(rruleStr);
                      final instances = rrule.getInstances(
                        start: e.startDate.isUtc
                            ? e.startDate
                            : e.startDate.toUtc(),
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
                            EventWithCalendar(
                              event: newEvent,
                              calendar: item.calendar,
                            ),
                          );
                        }
                      }
                    } catch (_) {}
                  }
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
                    final dayEvents = dayEventsMap[date] ?? [];

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
                          enabled: !_isLoading,
                          decoration: InputDecoration(
                            hintText: _isLoading
                                ? 'Thinking...'
                                : 'e.g., Lunch with Sarah tomorrow at 1pm',
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
                        backgroundColor: _isLoading
                            ? Colors.white.withValues(alpha: 0.1)
                            : (_hasText
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.white.withValues(alpha: 0.1)),
                        radius: 24,
                        child: _isLoading
                            ? const Padding(
                                padding: EdgeInsets.all(12.0),
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : IconButton(
                                icon: Icon(
                                  Icons.send,
                                  color: _hasText
                                      ? Colors.white
                                      : Colors.white54,
                                  size: 20,
                                ),
                                onPressed: () {
                                  if (_hasText && !_isLoading) {
                                    _submitNlpEvent(_nlpController.text);
                                  }
                                },
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
                : Consumer(
                    builder: (context, ref, child) {
                      final secondaryTz = ref.watch(secondaryTimezoneProvider);
                      return Column(
                        children: events
                            .map(
                              (e) => _buildEventCard(context, e, secondaryTz),
                            )
                            .toList(),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard(
    BuildContext context,
    EventWithCalendar item,
    String? secondaryTz,
  ) {
    final event = item.event;
    final calendarColor = _parseColor(item.calendar?.color);
    final isPast = event.endDate.toLocal().isBefore(DateTime.now());

    String? secondaryTimeString;
    if (secondaryTz != null) {
      try {
        final location = tz.getLocation(secondaryTz);
        final startInTz = tz.TZDateTime.from(event.startDate, location);
        final endInTz = tz.TZDateTime.from(event.endDate, location);

        // Extract a short code like "EST" or "GMT" or just use the location name
        final shortName = startInTz.timeZoneName;
        secondaryTimeString =
            '[$shortName] ${DateFormat('HH:mm').format(startInTz)} - ${DateFormat('HH:mm').format(endInTz)}';
      } catch (e) {
        debugPrint('Error converting timezone: $e');
      }
    }

    // Filter local time variables for all-day resolution
    final localStart = event.startDate.toLocal();
    final localEnd = event.endDate.toLocal();
    final isAllDay =
        localStart.hour == 0 &&
        localStart.minute == 0 &&
        localEnd.hour == 0 &&
        localEnd.minute == 0 &&
        localEnd.difference(localStart).inDays >= 1;

    // Glassmorphic effect on the card
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) =>
              EventEditScreen(event: event, initialDate: localStart),
        );
      },
      child: Opacity(
        opacity: isPast ? 0.4 : 1.0,
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
                    right: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
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
                          isAllDay ? Icons.today : Icons.access_time,
                          size: 14,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isAllDay
                              ? 'All day'
                              : '${DateFormat('HH:mm').format(localStart)} - ${DateFormat('HH:mm').format(localEnd)}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                    if (secondaryTimeString != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.public,
                            size: 14,
                            color: Theme.of(
                              context,
                            ).colorScheme.secondary.withValues(alpha: 0.8),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            secondaryTimeString,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (event.location != null &&
                        event.location!.isNotEmpty) ...[
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
                    Builder(
                      builder: (context) {
                        final meetingUrl = _extractMeetingUrl(
                          event.description,
                        );
                        final hasLocation =
                            event.location != null &&
                            event.location!.isNotEmpty;

                        if (meetingUrl == null && !hasLocation) {
                          return const SizedBox.shrink();
                        }

                        return Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: Row(
                            children: [
                              if (meetingUrl != null)
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () =>
                                        launchUrl(Uri.parse(meetingUrl)),
                                    icon: const Icon(
                                      Icons.video_call,
                                      size: 18,
                                    ),
                                    label: const Text('Join Meeting'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                    ),
                                  ),
                                ),
                              if (meetingUrl != null && hasLocation)
                                const SizedBox(width: 8),
                              if (hasLocation)
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      final url =
                                          'https://maps.google.com/?q=${Uri.encodeComponent(event.location!)}';
                                      launchUrl(Uri.parse(url));
                                    },
                                    icon: const Icon(Icons.map, size: 18),
                                    label: const Text('Map'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: BorderSide(
                                        color: Colors.white.withValues(
                                          alpha: 0.3,
                                        ),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
