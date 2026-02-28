import 'lib/core/sync/ical_parser.dart';

void main() {
  final icsStr = '''BEGIN:VCALENDAR
PRODID:-//Google Inc//Google Calendar 70.9054//EN
VERSION:2.0
CALSCALE:GREGORIAN
METHOD:PUBLISH
X-WR-CALNAME:my_calendar
X-WR-TIMEZONE:Europe/Berlin
BEGIN:VEVENT
DTSTART;VALUE=DATE:20230101
DTEND;VALUE=DATE:20230102
DTSTAMP:20230101T090000Z
UID:allday@google.com
CREATED:20230101T090000Z
DESCRIPTION:All-day Event
LAST-MODIFIED:20230101T090000Z
LOCATION:
SEQUENCE:0
STATUS:CONFIRMED
SUMMARY:All Day Test
TRANSP:OPAQUE
END:VEVENT
END:VCALENDAR''';

  final events = ICalParser.parseEvents(icsStr);
  // ignore: avoid_print
  print('Parsed events count: ${events.length}');
  for (var e in events) {
    // ignore: avoid_print
    print(e.title.value);
    // ignore: avoid_print
    print(e.startDate.value);
  }
}
