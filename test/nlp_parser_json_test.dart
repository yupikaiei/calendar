import 'package:flutter_test/flutter_test.dart';
import 'package:frelsi_cal/core/parsers/nlp_parser.dart';

void main() {
  group('NlpParser.fromJsonMap', () {
    test('maps update intent to edit flow and parses ISO dates', () {
      final result = NlpParser.fromJsonMap({
        'intent': 'update',
        'assistant_response': 'Updating your event.',
        'title': 'Lunch',
        'start_date': '2026-03-02T13:00:00.000',
        'end_date': '2026-03-02T14:00:00.000',
        'location': 'Cafe',
        'target_title': 'Lunch',
      });

      expect(result.intent, NlpIntent.edit);
      expect(result.title, 'Lunch');
      expect(result.startDate, isNotNull);
      expect(result.endDate, isNotNull);
      expect(result.location, 'Cafe');
      expect(result.targetEventTitle, 'Lunch');
    });

    test('defaults end date to one hour after start date when omitted', () {
      final result = NlpParser.fromJsonMap({
        'intent': 'create',
        'assistant_response': 'Done.',
        'title': 'Focus block',
        'start_date': '2026-03-02T09:00:00.000',
        'end_date': null,
        'location': null,
        'target_title': null,
      });

      expect(result.intent, NlpIntent.create);
      expect(result.startDate, isNotNull);
      expect(
        result.endDate,
        result.startDate?.add(const Duration(hours: 1)),
      );
    });
  });
}
