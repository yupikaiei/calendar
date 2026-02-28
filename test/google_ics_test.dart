import 'package:flutter_test/flutter_test.dart';
import 'package:frelsi_cal/core/sync/ical_parser.dart';

void main() {
  test('Parses Google Calendar ICS', () {
    final icsStr = '''BEGIN:VCALENDAR
PRODID:-//Google Inc//Google Calendar 70.9054//EN
VERSION:2.0
CALSCALE:GREGORIAN
METHOD:PUBLISH
X-WR-CALNAME:my_calendar
X-WR-TIMEZONE:Europe/Lisbon
BEGIN:VEVENT
DTSTART;TZID=Europe/Lisbon:20240212T130000
DTEND;TZID=Europe/Lisbon:20240212T133000
DTSTAMP:20250225T215243Z
UID:xxxxxx@google.com
CREATED:20240210T120000Z
DESCRIPTION:
LAST-MODIFIED:20240210T121000Z
LOCATION:
SEQUENCE:0
STATUS:CONFIRMED
SUMMARY:Dinner with Mom
TRANSP:OPAQUE
BEGIN:VALARM
ACTION:DISPLAY
DESCRIPTION:This is an event reminder
TRIGGER:-P0DT0H30M0S
END:VALARM
END:VEVENT
END:VCALENDAR''';

    final events = ICalParser.parseEvents(icsStr);
    expect(events.length, 1);
    expect(events.first.title.value, 'Dinner with Mom');
    expect(events.first.startDate.value, isA<DateTime>());
  });
}
