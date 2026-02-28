import 'dart:developer' as developer;
import 'package:icalendar_parser/icalendar_parser.dart';
import '../db/database.dart';
import 'package:drift/drift.dart';

class ICalParser {
  /// Parses an ICS string into Drift Event objects
  static EventsCompanion? parseEvent(String icsData) {
    try {
      final iCalendar = ICalendar.fromString(icsData);
      if (iCalendar.data.isEmpty) return null;

      final vEvent = iCalendar.data.firstWhere(
        (element) => element['type'] == 'VEVENT',
        orElse: () => {},
      );

      return _mapEvent(vEvent);
    } catch (e) {
      developer.log('Error parsing ICS: $e', name: 'ICalParser', level: 1000);
      return null;
    }
  }

  static List<EventsCompanion> parseEvents(String icsData) {
    final parsedEvents = <EventsCompanion>[];
    try {
      final iCalendar = ICalendar.fromString(icsData);
      if (iCalendar.data.isNotEmpty) {
        for (final element in iCalendar.data) {
          if (element['type'] == 'VEVENT') {
            final mapped = _mapEvent(element);
            if (mapped != null) {
              parsedEvents.add(mapped);
            }
          }
        }
      }
    } catch (e) {
      developer.log(
        'Error parsing multiple ICS elements: $e',
        name: 'ICalParser',
        level: 1000,
      );
    }

    // If parsing failed or yielded no events (perhaps due to VTIMEZONE or other components crashing the parser),
    // fallback to extracting and parsing VEVENT blocks individually.
    if (parsedEvents.isEmpty) {
      try {
        final regex = RegExp(
          r'BEGIN:VEVENT\r?\n(.*?)\r?\nEND:VEVENT',
          dotAll: true,
        );
        final matches = regex.allMatches(icsData);
        for (final match in matches) {
          final block =
              'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\n${match.group(1)}\r\nEND:VEVENT\r\nEND:VCALENDAR';
          try {
            final iCal = ICalendar.fromString(block);
            for (final element in iCal.data) {
              if (element['type'] == 'VEVENT') {
                final mapped = _mapEvent(element);
                if (mapped != null) {
                  parsedEvents.add(mapped);
                }
              }
            }
          } catch (_) {
            // Ignore single event parse failures during fallback
          }
        }
      } catch (e) {
        developer.log(
          'Error during fallback regex extraction: $e',
          name: 'ICalParser',
          level: 1000,
        );
      }
    }

    return parsedEvents;
  }

  static EventsCompanion? _mapEvent(Map<String, dynamic> vEvent) {
    if (vEvent.isEmpty) return null;

    final uid = vEvent['uid']?.toString() ?? '';
    if (uid.isEmpty) return null;

    return EventsCompanion(
      uid: Value(uid),
      title: Value(vEvent['summary']?.toString() ?? 'Untitled'),
      startDate: Value(_parseDate(vEvent['dtstart'])),
      endDate: Value(_parseDate(vEvent['dtend'])),
      description: Value(vEvent['description']?.toString()),
      location: Value(vEvent['location']?.toString()),
      recurrenceRule: Value(vEvent['rrule']?.toString()),
    );
  }

  static DateTime _parseDate(dynamic dtField) {
    if (dtField == null) return DateTime.now();
    try {
      if (dtField is IcsDateTime) {
        return dtField.toDateTime() ?? DateTime.now();
      }
      return DateTime.parse(dtField.toString());
    } catch (_) {
      return DateTime.now();
    }
  }

  /// Generates an ICS string from a Drift Event
  static String generateIcs(Event event) {
    final buffer = StringBuffer();
    buffer.writeln('BEGIN:VCALENDAR');
    buffer.writeln('VERSION:2.0');
    buffer.writeln('PRODID:-//Frelsi Cal//EN');
    buffer.writeln('BEGIN:VEVENT');
    buffer.writeln('UID:${event.uid}');
    buffer.writeln('SUMMARY:${event.title}');

    String format(DateTime d) =>
        '${d.toUtc().toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first}Z';

    buffer.writeln('DTSTART:${format(event.startDate)}');
    buffer.writeln('DTEND:${format(event.endDate)}');

    if (event.description != null) {
      buffer.writeln('DESCRIPTION:${event.description}');
    }
    if (event.location != null) {
      buffer.writeln('LOCATION:${event.location}');
    }
    if (event.recurrenceRule != null) {
      buffer.writeln('RRULE:${event.recurrenceRule}');
    }

    buffer.writeln('END:VEVENT');
    buffer.writeln('END:VCALENDAR');
    return buffer.toString();
  }
}
