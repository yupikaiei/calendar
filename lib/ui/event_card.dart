import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:timezone/standalone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import '../core/db/database.dart';
import '../core/providers/providers.dart';
import 'event_edit_screen.dart';
import 'utils.dart';

class EventCard extends ConsumerWidget {
  static final _logger = Logger('EventCard');

  final EventWithCalendar item;

  const EventCard({super.key, required this.item});

  String? _extractMeetingUrl(String? description) {
    if (description == null || description.isEmpty) return null;
    final regex = RegExp(
      r'(https?:\/\/(?:www\.)?(?:zoom\.us|meet\.google\.com|teams\.microsoft\.com|webex\.com)[^\s]+)',
    );
    final match = regex.firstMatch(description);
    return match?.group(0);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final secondaryTz = ref.watch(secondaryTimezoneProvider);
    final event = item.event;
    final calendarColor = parseColor(item.calendar?.color);
    final isPast = event.endDate.toLocal().isBefore(DateTime.now());

    String? secondaryTimeString;
    if (secondaryTz != null) {
      try {
        final location = tz.getLocation(secondaryTz);
        final startInTz = tz.TZDateTime.from(event.startDate, location);
        final endInTz = tz.TZDateTime.from(event.endDate, location);
        final shortName = startInTz.timeZoneName;
        secondaryTimeString =
            '[$shortName] ${DateFormat('HH:mm').format(startInTz)} - ${DateFormat('HH:mm').format(endInTz)}';
      } catch (e) {
        _logger.fine('Timezone conversion failed for secondary display', e);
      }
    }

    final localStart = event.startDate.toLocal();
    final localEnd = event.endDate.toLocal();
    final isAllDay =
        localStart.hour == 0 &&
        localStart.minute == 0 &&
        localEnd.hour == 0 &&
        localEnd.minute == 0 &&
        localEnd.difference(localStart).inDays >= 1;

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
                left: BorderSide(color: calendarColor, width: 4),
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
