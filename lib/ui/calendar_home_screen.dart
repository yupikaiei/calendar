import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'event_edit_screen.dart';
import 'settings_screen.dart';
import 'utils.dart';
import '../core/providers/providers.dart';
import '../core/db/database.dart';
import '../core/sync/sync_manager.dart';
import '../core/parsers/nlp_parser.dart';
import 'package:timezone/standalone.dart' as tz;
import 'package:rrule/rrule.dart';
import 'dart:math' as math;
import 'package:record/record.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Smart Input Bar as a reusable widget
class SmartInputBar extends StatefulWidget {
  final Function(String) onSubmit;
  final bool isLoading;
  const SmartInputBar({super.key, required this.onSubmit, this.isLoading = false});

  @override
  State<SmartInputBar> createState() => _SmartInputBarState();
}

class _SmartInputBarState extends State<SmartInputBar> {
  final TextEditingController _controller = TextEditingController();
  final ValueNotifier<bool> _hasText = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    _hasText.value = _controller.text.isNotEmpty;
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _hasText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: !widget.isLoading,
              decoration: InputDecoration(
                hintText: widget.isLoading
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
              onSubmitted: (text) {
                if (text.isNotEmpty && !widget.isLoading) {
                  Navigator.of(context).pop();
                  widget.onSubmit(text);
                }
              },
            ),
          ),
          const SizedBox(width: 12),
          ValueListenableBuilder<bool>(
            valueListenable: _hasText,
            builder: (context, hasText, _) {
              return CircleAvatar(
                backgroundColor: widget.isLoading
                    ? Colors.white.withValues(alpha: 0.1)
                    : (hasText
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white.withValues(alpha: 0.1)),
                radius: 24,
                child: widget.isLoading
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
                          color: hasText ? Colors.white : Colors.white54,
                          size: 20,
                        ),
                        onPressed: () {
                          if (hasText && !widget.isLoading) {
                            Navigator.of(context).pop();
                            widget.onSubmit(_controller.text);
                          }
                        },
                      ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class CalendarHomeScreen extends ConsumerStatefulWidget {
  const CalendarHomeScreen({super.key});

  @override
  ConsumerState<CalendarHomeScreen> createState() => _CalendarHomeScreenState();
}

class _CalendarHomeScreenState extends ConsumerState<CalendarHomeScreen> {
  static final _logger = Logger('CalendarHomeScreen');
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  late List<DateTime> _days;
  int _initialIndex = 0;
  DateTime _selectedDate = DateTime.now();
  final TextEditingController _nlpController = TextEditingController();
  final ValueNotifier<bool> _hasText = ValueNotifier(false);
  bool _isLoading = false;
  Timer? _scrollDebounce;

  // Cached recurrence expansion results
  List<EventWithCalendar>? _lastAllEvents;
  Map<DateTime, List<EventWithCalendar>>? _cachedDayEventsMap;
  List<DateTime>? _cachedDays;

  @override
  void dispose() {
    _scrollDebounce?.cancel();
    _nlpController.removeListener(_onTextChanged);
    _nlpController.dispose();
    _hasText.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    _hasText.value = _nlpController.text.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _nlpController.addListener(_onTextChanged);
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

  String? _extractMeetingUrl(String? description) {
    if (description == null || description.isEmpty) return null;
    final regex = RegExp(
      r'(https?:\/\/(?:www\.)?(?:zoom\.us|meet\.google\.com|teams\.microsoft\.com|webex\.com)[^\s]+)',
    );
    final match = regex.firstMatch(description);
    return match?.group(0);
  }

  /// Programmatically checks the user's schedule for availability at the given
  /// time range. This is deterministic and avoids LLM hallucination.
  String _checkAvailability(
    List<Event> events,
    DateTime? queryStart,
    DateTime? queryEnd,
  ) {
    if (queryStart == null) {
      return "I couldn't determine the time you're asking about.";
    }
    final qStart = queryStart;
    final qEnd = queryEnd ?? qStart.add(const Duration(hours: 1));

    final conflicts = events.where((e) {
      // Two intervals overlap if one starts before the other ends and vice versa
      return e.startDate.isBefore(qEnd) && e.endDate.isAfter(qStart);
    }).toList();

    if (conflicts.isEmpty) {
      final timeStr = DateFormat('h:mm a').format(qStart);
      final dateStr = DateFormat('EEEE, MMM d').format(qStart);
      return 'You\'re free at $timeStr on $dateStr!';
    }

    final busyDescriptions = conflicts
        .map((e) {
          final s = DateFormat('h:mm a').format(e.startDate.toLocal());
          final en = DateFormat('h:mm a').format(e.endDate.toLocal());
          return '${e.title} ($s - $en)';
        })
        .join(', ');

    return 'You\'re busy with: $busyDescriptions';
  }

  void _startVoiceInput() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString('ai_base_url') ?? '';
    if (baseUrl.isEmpty) {
      if (!mounted) return;
      _showModernSnackBar(
        context,
        'AI server not configured. Please update settings.',
        icon: Icons.error_outline,
      );
      return;
    }

    if (!mounted) return;
    showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => const _VoiceInputDialog(),
    ).then((resultText) {
      if (resultText != null && resultText.trim().isNotEmpty) {
        _submitNlpEvent(resultText);
      }
    });
  }

  void _submitNlpEvent(String text) async {
    if (text.trim().isEmpty || _isLoading) return;

    setState(() => _isLoading = true);

    // Capture navigator/focus before async gap to avoid using BuildContext
    // across awaits.
    final navigator = Navigator.of(context);
    final focusScope = FocusScope.of(context);

    // Show thinking dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => const _ThinkingOverlay(),
    );

    try {
      final db = ref.read(databaseProvider);
      final events = await db.getEvents();

      final result = await NlpParser.parse(text);

      if (!mounted) return;

      // Dismiss thinking dialog
      navigator.pop();

      setState(() => _isLoading = false);

      _nlpController.clear();
      focusScope.unfocus();

    // For query intents, check the schedule programmatically instead of
    // relying on the small LLM (which hallucinates with context data).
    if (result.intent == NlpIntent.query) {
      final queryResponse = _checkAvailability(
        events,
        result.startDate,
        result.endDate,
      );
      _showModernSnackBar(
        context,
        queryResponse,
        icon: Icons.check_circle_outline,
        duration: const Duration(seconds: 4),
      );
      return;
    }

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
    } catch (e) {
      // Dismiss thinking dialog if still showing
      if (!mounted) return;
      if (navigator.canPop()) {
        navigator.pop();
      }
      setState(() => _isLoading = false);
      _showModernSnackBar(
        context,
        e.toString().replaceAll('Exception: ', ''),
        icon: Icons.error_outline,
        duration: const Duration(seconds: 4),
      );
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


              // Floating Radial Menu Button
              _RadialFabMenu(
                fabIcon: Icons.add,
                fabCloseIcon: Icons.close,
                fabColor: Theme.of(context).colorScheme.primary,
                bottomOffset: MediaQuery.of(context).padding.bottom + 80,
                items: [
                  _RadialMenuItem(
                    icon: Icons.text_fields,
                    label: 'Text',
                    color: Theme.of(context).colorScheme.secondary,
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) {
                          return Dialog(
                            backgroundColor: Colors.transparent,
                            child: SmartInputBar(
                              isLoading: _isLoading,
                              onSubmit: (text) {
                                _submitNlpEvent(text);
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                  _RadialMenuItem(
                    icon: Icons.mic,
                    label: 'Voice',
                    color: Theme.of(context).colorScheme.secondary,
                    onTap: _startVoiceInput,
                  ),
                  _RadialMenuItem(
                    icon: Icons.event_note,
                    label: 'Form',
                    color: Theme.of(context).colorScheme.secondary,
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (context) => const EventEditScreen(),
                      );
                    },
                  ),
                ],
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
    final calendarColor = parseColor(item.calendar?.color);
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
        _logger.fine('Timezone conversion failed for secondary display', e);
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
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        foregroundDecoration: isPast
            ? BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(16),
              )
            : null,
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
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                right: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
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
                Builder(
                  builder: (context) {
                    final meetingUrl = _extractMeetingUrl(event.description);
                    final hasLocation =
                        event.location != null && event.location!.isNotEmpty;

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
                                icon: const Icon(Icons.video_call, size: 18),
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
                                    color: Colors.white.withValues(alpha: 0.3),
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
    );
  }
}

// ── Voice Input Dialog ──────────────────────────────────────────────────────
class _VoiceInputDialog extends StatefulWidget {
  const _VoiceInputDialog();

  @override
  State<_VoiceInputDialog> createState() => _VoiceInputDialogState();
}

class _VoiceInputDialogState extends State<_VoiceInputDialog>
    with SingleTickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();
  late AnimationController _pulseController;
  bool _isRecording = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
      lowerBound: 0.9,
      upperBound: 1.2,
    )..repeat(reverse: true);
    _startRecording();
  }

  Future<String> _tempFilePath() async {
    final dir = await Directory.systemTemp.createTemp('voice');
    return '${dir.path}/recording.wav';
  }

  Future<void> _startRecording() async {
    try {
      final hasPerm = await _recorder.hasPermission();
      if (!hasPerm) {
        setState(() {
          _errorMessage = 'Microphone permission denied.';
        });
        return;
      }
      final path = await _tempFilePath();
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          bitRate: 128000,
          sampleRate: 16000,
        ),
        path: path,
      );
      setState(() {
        _isRecording = true;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Recording error: $e';
      });
    }
  }

  Future<void> _stopAndSend() async {
    final navigator = Navigator.of(context);
    try {
      final path = await _recorder.stop();
      setState(() {
        _isRecording = false;
      });
      if (path == null || path.isEmpty) {
        setState(() {
          _errorMessage = 'Failed to capture audio.';
        });
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final secure = SecureConfigService();
      final baseUrl = prefs.getString('stt_base_url') ?? '';
      if (baseUrl.isEmpty) {
        setState(() {
          _errorMessage = 'STT server not configured.';
        });
        return;
      }
      final apiKey = await secure.read('stt_api_key');
      final sttModel = prefs.getString('stt_model_name') ?? '';
      final uri = Uri.parse('$baseUrl/v1/audio/transcriptions');
      final request = http.MultipartRequest('POST', uri);
      if (apiKey.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $apiKey';
      }
      request.files.add(await http.MultipartFile.fromPath('file', path));
      if (sttModel.isNotEmpty) {
        request.fields['model'] = sttModel;
      }
      final streamed = await request.send();
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode >= 400) {
        setState(() {
          _errorMessage = 'STT server error ${resp.statusCode}';
        });
        return;
      }
      final data = jsonDecode(resp.body);
      final transcript = data['text']?.toString() ?? '';
      if (!mounted) return;
      navigator.pop(transcript);
    } catch (e) {
      setState(() {
        _errorMessage = 'STT failed: $e';
      });
    }
  }

  void _cancel() async {
    final navigator = Navigator.of(context);
    if (_isRecording) {
      await _recorder.stop();
    }
    navigator.pop();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_errorMessage != null) {
      return Dialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: Colors.red.withValues(alpha: 0.7)),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
    }

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pulsing mic icon
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseController.value,
                  child: child,
                );
              },
              child: CircleAvatar(
                radius: 44,
                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.3),
                  child: Icon(
                    Icons.mic,
                    size: 36,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              _isRecording ? 'Recording...' : 'Processing...',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _cancel,
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white54),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: _isRecording ? _stopAndSend : null,
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('Stop & Send'),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Radial Menu Data ────────────────────────────────────────────────────────
class _RadialMenuItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _RadialMenuItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

// ── Custom Radial FAB Menu ──────────────────────────────────────────────────
class _RadialFabMenu extends StatefulWidget {
  final IconData fabIcon;
  final IconData fabCloseIcon;
  final Color fabColor;
  final double bottomOffset;
  final List<_RadialMenuItem> items;

  const _RadialFabMenu({
    required this.fabIcon,
    required this.fabCloseIcon,
    required this.fabColor,
    required this.bottomOffset,
    required this.items,
  });

  @override
  State<_RadialFabMenu> createState() => _RadialFabMenuState();
}

class _RadialFabMenuState extends State<_RadialFabMenu>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _expandAnimation;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  void _close() {
    if (_isOpen) _toggle();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(bottom: widget.bottomOffset),
        child: SizedBox(
          width: 300,
          height: 200,
          child: Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
              // Scrim / overlay to catch taps when open (behind items)
              if (_isOpen)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: _close,
                    behavior: HitTestBehavior.translucent,
                  ),
                ),
              // Radial items (on top of scrim so they receive taps)
              ..._buildRadialItems(),
              // Central FAB
              _buildFab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFab() {
    return AnimatedBuilder(
      animation: _expandAnimation,
      builder: (context, child) {
        return Transform.rotate(
          angle: _expandAnimation.value * (math.pi * 0.25),
          child: child,
        );
      },
      child: FloatingActionButton(
        onPressed: _toggle,
        backgroundColor: widget.fabColor,
        elevation: 6,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: animation, child: child),
          child: Icon(
            _isOpen ? widget.fabCloseIcon : widget.fabIcon,
            key: ValueKey(_isOpen),
            color: Colors.white,
            size: 28,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildRadialItems() {
    final count = widget.items.length;
    // Spread items in a 120° arc above the FAB (from 210° to 330° in unit-circle terms)
    const startAngle = 210.0; // degrees
    const endAngle = 330.0;
    const radius = 110.0;

    return List.generate(count, (index) {
      final angle = count == 1
          ? 270.0 // straight up
          : startAngle + (endAngle - startAngle) * index / (count - 1);
      final radians = angle * (math.pi / 180.0);

      final item = widget.items[index];

      return AnimatedBuilder(
        animation: _expandAnimation,
        builder: (context, child) {
          final dx = math.cos(radians) * radius * _expandAnimation.value;
          final dy = math.sin(radians) * radius * _expandAnimation.value;
          return Transform.translate(
            offset: Offset(dx, dy),
            child: Opacity(
              opacity: _expandAnimation.value,
              child: child,
            ),
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () {
                _close();
                item.onTap();
              },
              child: CircleAvatar(
                radius: 26,
                backgroundColor: item.color,
                child: Icon(item.icon, color: Colors.white, size: 22),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ── Thinking Overlay ────────────────────────────────────────────────────────
class _ThinkingOverlay extends StatefulWidget {
  const _ThinkingOverlay();

  @override
  State<_ThinkingOverlay> createState() => _ThinkingOverlayState();
}

class _ThinkingOverlayState extends State<_ThinkingOverlay>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rotateController;
  late Animation<double> _pulseAnimation;

  static const _thinkingPhrases = [
    'Thinking...',
    'Reasoning through your request...',
    'Understanding your intent...',
    'Analyzing details...',
    'Almost there...',
  ];
  int _phraseIndex = 0;
  Timer? _phraseTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    // Cycle through thinking phrases
    _phraseTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() {
        _phraseIndex = (_phraseIndex + 1) % _thinkingPhrases.length;
      });
    });
  }

  @override
  void dispose() {
    _phraseTimer?.cancel();
    _pulseController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 220,
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.3),
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated icon
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseAnimation.value,
                      child: child,
                    );
                  },
                  child: AnimatedBuilder(
                    animation: _rotateController,
                    builder: (context, child) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          // Rotating ring
                          Transform.rotate(
                            angle: _rotateController.value * 2 * 3.14159,
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: 0.2),
                                  width: 2,
                                ),
                                gradient: SweepGradient(
                                  colors: [
                                    theme.colorScheme.primary
                                        .withValues(alpha: 0.0),
                                    theme.colorScheme.primary
                                        .withValues(alpha: 0.6),
                                    theme.colorScheme.primary
                                        .withValues(alpha: 0.0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Center icon
                          Icon(
                            Icons.auto_awesome,
                            size: 32,
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                // Animated text
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: Text(
                    _thinkingPhrases[_phraseIndex],
                    key: ValueKey(_phraseIndex),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 12),
                // Subtle progress dots
                SizedBox(
                  width: 40,
                  child: LinearProgressIndicator(
                    backgroundColor:
                        theme.colorScheme.primary.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation(
                      theme.colorScheme.primary.withValues(alpha: 0.5),
                    ),
                    minHeight: 2,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
