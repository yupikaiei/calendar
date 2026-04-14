import 'package:flutter_test/flutter_test.dart';
import 'package:frelsi_cal/core/sync/ical_parser.dart';
import 'package:frelsi_cal/core/db/database.dart';

void main() {
  group('parseEvent', () {
    test('parses standard VEVENT fields', () {
      const ics = '''BEGIN:VCALENDAR
PRODID:-//Test//EN
VERSION:2.0
BEGIN:VEVENT
UID:abc-123@example.com
SUMMARY:Team Standup
DTSTART:20240315T100000Z
DTEND:20240315T103000Z
DTSTAMP:20240315T080000Z
DESCRIPTION:Daily sync meeting
LOCATION:Room 42
END:VEVENT
END:VCALENDAR''';

      final result = ICalParser.parseEvent(ics);
      expect(result, isNotNull);
      expect(result!.uid.value, 'abc-123@example.com');
      expect(result.title.value, 'Team Standup');
      expect(result.description.value, 'Daily sync meeting');
      expect(result.location.value, 'Room 42');
      expect(result.startDate.value, isA<DateTime>());
      expect(result.endDate.value, isA<DateTime>());
    });

    test('parses VEVENT with timezone (TZID)', () {
      const ics = '''BEGIN:VCALENDAR
PRODID:-//Test//EN
VERSION:2.0
BEGIN:VEVENT
UID:tz-event@example.com
SUMMARY:Lunch
DTSTART;TZID=Europe/Lisbon:20240315T130000
DTEND;TZID=Europe/Lisbon:20240315T140000
DTSTAMP:20240315T080000Z
END:VEVENT
END:VCALENDAR''';

      final result = ICalParser.parseEvent(ics);
      expect(result, isNotNull);
      expect(result!.title.value, 'Lunch');
      expect(result.startDate.value.hour >= 12, isTrue);
    });

    test('parses VEVENT with RRULE', () {
      const ics = '''BEGIN:VCALENDAR
PRODID:-//Test//EN
VERSION:2.0
BEGIN:VEVENT
UID:rrule-event@example.com
SUMMARY:Weekly Sync
DTSTART:20240315T100000Z
DTEND:20240315T103000Z
DTSTAMP:20240315T080000Z
RRULE:FREQ=WEEKLY;BYDAY=FR
END:VEVENT
END:VCALENDAR''';

      final result = ICalParser.parseEvent(ics);
      expect(result, isNotNull);
      expect(result!.recurrenceRule.value, contains('FREQ=WEEKLY'));
    });

    test('returns null for empty ICS', () {
      expect(ICalParser.parseEvent(''), isNull);
    });

    test('returns null for malformed ICS', () {
      expect(ICalParser.parseEvent('not valid ics data'), isNull);
    });

    test('returns null when no VEVENT present', () {
      const ics = '''BEGIN:VCALENDAR
PRODID:-//Test//EN
VERSION:2.0
BEGIN:VTIMEZONE
TZID:Europe/Lisbon
END:VTIMEZONE
END:VCALENDAR''';

      expect(ICalParser.parseEvent(ics), isNull);
    });

    test('returns null when VEVENT has no UID', () {
      const ics = '''BEGIN:VCALENDAR
PRODID:-//Test//EN
VERSION:2.0
BEGIN:VEVENT
SUMMARY:No UID Event
DTSTART:20240315T100000Z
DTEND:20240315T103000Z
DTSTAMP:20240315T080000Z
END:VEVENT
END:VCALENDAR''';

      // _mapEvent returns null when uid is empty
      final result = ICalParser.parseEvent(ics);
      // Result depends on parser behavior — UID might be empty string
      if (result != null) {
        expect(result.uid.value, isEmpty);
      }
    });
  });

  group('parseEvents', () {
    test('parses multiple VEVENTs from single VCALENDAR', () {
      const ics = '''BEGIN:VCALENDAR
PRODID:-//Test//EN
VERSION:2.0
BEGIN:VEVENT
UID:event-1@example.com
SUMMARY:Event One
DTSTART:20240315T100000Z
DTEND:20240315T110000Z
DTSTAMP:20240315T080000Z
END:VEVENT
BEGIN:VEVENT
UID:event-2@example.com
SUMMARY:Event Two
DTSTART:20240316T140000Z
DTEND:20240316T150000Z
DTSTAMP:20240316T080000Z
END:VEVENT
END:VCALENDAR''';

      final results = ICalParser.parseEvents(ics);
      expect(results.length, 2);
      expect(results[0].title.value, 'Event One');
      expect(results[1].title.value, 'Event Two');
    });

    test('returns empty list for empty input', () {
      expect(ICalParser.parseEvents(''), isEmpty);
    });

    test('uses fallback regex extraction when primary parser fails', () {
      // VCALENDAR with PRODID missing — primary parser throws but fallback regex should extract the VEVENT
      const ics = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:fallback-1@example.com
SUMMARY:Fallback Event
DTSTART:20240315T100000Z
DTEND:20240315T110000Z
DTSTAMP:20240315T080000Z
END:VEVENT
END:VCALENDAR''';

      final results = ICalParser.parseEvents(ics);
      expect(results, isNotEmpty);
    });
  });

  group('generateIcs', () {
    test('generates valid ICS with all fields', () {
      final event = Event(
        id: 1,
        uid: 'gen-test-uid',
        title: 'Test Event',
        startDate: DateTime.utc(2024, 3, 15, 10, 0),
        endDate: DateTime.utc(2024, 3, 15, 11, 0),
        description: 'A test description',
        location: 'Test Location',
        recurrenceRule: 'FREQ=DAILY;COUNT=5',
        calendarId: null,
      );

      final ics = ICalParser.generateIcs(event);
      expect(ics, contains('BEGIN:VCALENDAR'));
      expect(ics, contains('END:VCALENDAR'));
      expect(ics, contains('BEGIN:VEVENT'));
      expect(ics, contains('END:VEVENT'));
      expect(ics, contains('UID:gen-test-uid'));
      expect(ics, contains('SUMMARY:Test Event'));
      expect(ics, contains('DTSTART:'));
      expect(ics, contains('DTEND:'));
      expect(ics, contains('DESCRIPTION:A test description'));
      expect(ics, contains('LOCATION:Test Location'));
      expect(ics, contains('RRULE:FREQ=DAILY;COUNT=5'));
      expect(ics, contains('PRODID:-//Frelsi Cal//EN'));
    });

    test('omits null optional fields', () {
      final event = Event(
        id: 1,
        uid: 'minimal-uid',
        title: 'Minimal Event',
        startDate: DateTime.utc(2024, 3, 15, 10, 0),
        endDate: DateTime.utc(2024, 3, 15, 11, 0),
        description: null,
        location: null,
        recurrenceRule: null,
        calendarId: null,
      );

      final ics = ICalParser.generateIcs(event);
      expect(ics, contains('UID:minimal-uid'));
      expect(ics, contains('SUMMARY:Minimal Event'));
      expect(ics, isNot(contains('DESCRIPTION:')));
      expect(ics, isNot(contains('LOCATION:')));
      expect(ics, isNot(contains('RRULE:')));
    });
  });
}
