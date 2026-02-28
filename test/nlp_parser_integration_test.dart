import 'package:flutter_test/flutter_test.dart';
import 'package:frelsi_cal/core/parsers/nlp_parser.dart';

void main() {
  testWidgets(
    'Integration test ML Kit',
    (WidgetTester tester) async {
      await NlpParser.init();
      final result = await NlpParser.parse(
        'Lunch with Sarah tomorrow at 1pm at the cafe',
      );
      expect(result.intent, isNotNull);
      expect(result.assistantResponse, isNotNull);
    },
    skip: true, // Requires large model file (.gguf) not available in CI
  );
}
