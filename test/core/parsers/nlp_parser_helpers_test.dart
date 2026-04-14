import 'package:flutter_test/flutter_test.dart';
import 'package:frelsi_cal/core/parsers/nlp_parser.dart';

void main() {
  group('extractTime', () {
    test('"2pm" → {hour: 14, minute: 0}', () {
      final result = NlpParser.extractTime('meeting at 2pm');
      expect(result, {'hour': 14, 'minute': 0});
    });

    test('"2:30pm" → {hour: 14, minute: 30}', () {
      final result = NlpParser.extractTime('call at 2:30pm');
      expect(result, {'hour': 14, 'minute': 30});
    });

    test('"noon" → {hour: 12, minute: 0}', () {
      final result = NlpParser.extractTime('lunch at noon');
      expect(result, {'hour': 12, 'minute': 0});
    });

    test('"midnight" → {hour: 0, minute: 0}', () {
      final result = NlpParser.extractTime('deadline at midnight');
      expect(result, {'hour': 0, 'minute': 0});
    });

    test('"2 p.m." → {hour: 14, minute: 0}', () {
      final result = NlpParser.extractTime('event at 2 p.m.');
      expect(result, {'hour': 14, 'minute': 0});
    });

    test('"14:00" (24h) → {hour: 14, minute: 0}', () {
      final result = NlpParser.extractTime('meeting at 14:00');
      expect(result, {'hour': 14, 'minute': 0});
    });

    test('"9am" → {hour: 9, minute: 0}', () {
      final result = NlpParser.extractTime('breakfast at 9am');
      expect(result, {'hour': 9, 'minute': 0});
    });

    test('"12am" → {hour: 0, minute: 0}', () {
      final result = NlpParser.extractTime('event at 12am');
      expect(result, {'hour': 0, 'minute': 0});
    });

    test('"12pm" → {hour: 12, minute: 0}', () {
      final result = NlpParser.extractTime('event at 12pm');
      expect(result, {'hour': 12, 'minute': 0});
    });

    test('"09:30" (24h) → {hour: 9, minute: 30}', () {
      final result = NlpParser.extractTime('standup at 09:30');
      expect(result, {'hour': 9, 'minute': 30});
    });

    test('no time → null', () {
      expect(NlpParser.extractTime('meeting tomorrow'), isNull);
    });

    test('no time in empty string → null', () {
      expect(NlpParser.extractTime(''), isNull);
    });
  });

  group('extractDate', () {
    final now = DateTime(2024, 3, 15, 10, 30); // Friday

    test('"today" → today', () {
      final result = NlpParser.extractDate('meeting today', now);
      expect(result, DateTime(2024, 3, 15));
    });

    test('"tomorrow" → today + 1', () {
      final result = NlpParser.extractDate('lunch tomorrow', now);
      expect(result, DateTime(2024, 3, 16));
    });

    test('"yesterday" → today - 1', () {
      final result = NlpParser.extractDate('what happened yesterday', now);
      expect(result, DateTime(2024, 3, 14));
    });

    test('"Monday" → next Monday', () {
      // March 15 2024 is Friday, next Monday is March 18
      final result = NlpParser.extractDate('meeting on Monday', now);
      expect(result, DateTime(2024, 3, 18));
    });

    test('"Friday" → next Friday (not today)', () {
      // March 15 2024 is Friday, so "Friday" should go to next week
      final result = NlpParser.extractDate('event on Friday', now);
      expect(result, DateTime(2024, 3, 22));
    });

    test('"Wednesday" → next Wednesday', () {
      // March 15 is Friday, next Wednesday is March 20
      final result = NlpParser.extractDate('call on Wednesday', now);
      expect(result, DateTime(2024, 3, 20));
    });

    test('no date keyword → null', () {
      expect(NlpParser.extractDate('meeting at 2pm', now), isNull);
    });

    test('empty string → null', () {
      expect(NlpParser.extractDate('', now), isNull);
    });
  });
}
