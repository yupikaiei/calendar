import 'package:rrule/rrule.dart';

void main() {
  final rrule = RecurrenceRule.fromString('RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR');
  final start = DateTime.utc(2023, 1, 1, 10, 0); // local or utc
  final instances = rrule.getInstances(
    start: start,
    after: DateTime.utc(2023, 1, 10),
    before: DateTime.utc(2023, 1, 20),
  );
  print(instances.toList());
}
