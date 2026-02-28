import 'package:frelsi_cal/core/sync/ical_parser.dart';

void main() {
  final icsStr = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
DTSTART:20240212T130000Z
DTEND:20240212T140000Z
UID:xxxxxx@google.com
SUMMARY:Dinner with Mom
END:VEVENT
END:VCALENDAR''';

  final events = ICalParser.parseEvents(icsStr);
  // ignore: avoid_print
  print('Parsed events: ${events.length}');
  for (var e in events) {
    // ignore: avoid_print
    print('Event start: ${e.startDate.value}');
  }
}
