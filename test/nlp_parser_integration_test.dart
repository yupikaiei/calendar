import 'package:flutter_test/flutter_test.dart';
import 'package:frelsi_cal/core/parsers/nlp_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'Integration test against configured AI server',
    (WidgetTester tester) async {
      // this test will only run when an AI server URL is provided via
      // SharedPreferences or environment. It remains skipped in CI.
      final prefs = await SharedPreferences.getInstance();
      prefs.setString('ai_base_url', 'https://localhost:8000');

      final result = await NlpParser.parse(
        'Lunch with Sarah tomorrow at 1pm at the cafe',
      );
      expect(result.intent, isNotNull);
      expect(result.assistantResponse, isNotNull);
    },
    skip: true, // integration only; requires reachable AI server
  );
}
