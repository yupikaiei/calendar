import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frelsi_cal/core/parsers/nlp_parser.dart';
import 'package:frelsi_cal/core/services/secure_config_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// In-memory fake for FlutterSecureStorage (same as in secure_config_service_test).
class FakeSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _store.remove(key);
  }
}

/// Helper to build a successful AI response body.
String _aiResponse(Map<String, dynamic> content) {
  return jsonEncode({
    'choices': [
      {
        'message': {'content': jsonEncode(content)}
      }
    ]
  });
}

MockClient _mockClient(int statusCode, String body) {
  return MockClient((request) async {
    return http.Response(body, statusCode);
  });
}

void _setupConfig({String baseUrl = 'http://localhost:8000'}) {
  SharedPreferences.setMockInitialValues({
    'ai_base_url': baseUrl,
    'ai_model_name': 'test-model',
    '_credentials_migrated': true,
  });
}

void main() {
  late SecureConfigService secureConfig;

  setUp(() {
    secureConfig = SecureConfigService(storage: FakeSecureStorage());
  });

  group('NlpParser.parse', () {
    test('empty input returns NlpIntent.unknown', () async {
      _setupConfig();
      final result = await NlpParser.parse('');
      expect(result.intent, NlpIntent.unknown);
      expect(result.assistantResponse, contains("didn't catch that"));
    });

    test('whitespace-only input returns NlpIntent.unknown', () async {
      _setupConfig();
      final result = await NlpParser.parse('   ');
      expect(result.intent, NlpIntent.unknown);
    });

    test('missing AI server config throws exception', () async {
      SharedPreferences.setMockInitialValues({
        '_credentials_migrated': true,
      });

      expect(
        () => NlpParser.parse('create an event', secureConfig: secureConfig),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('not configured'),
          ),
        ),
      );
    });

    test('successful create response returns correct result', () async {
      _setupConfig();
      final responseBody = _aiResponse({
        'intent': 'create',
        'assistant_response': 'Meeting created.',
        'title': 'Team Standup',
        'start_date': '2024-03-15T10:00:00.000',
        'end_date': '2024-03-15T11:00:00.000',
        'location': 'Room 42',
        'target_title': null,
      });
      final client = _mockClient(200, responseBody);
      final result = await NlpParser.parse('Team Standup tomorrow at 10am',
          client: client, secureConfig: secureConfig);

      expect(result.intent, NlpIntent.create);
      expect(result.assistantResponse, 'Meeting created.');
      expect(result.title, 'Team Standup');
      expect(result.location, 'Room 42');
    });

    test('strips <think> tags from response', () async {
      _setupConfig();
      final json = jsonEncode({
        'intent': 'create',
        'assistant_response': 'Done.',
        'title': 'Lunch',
        'start_date': '2024-03-15T12:00:00.000',
        'end_date': '2024-03-15T13:00:00.000',
        'location': null,
        'target_title': null,
      });
      final body = jsonEncode({
        'choices': [
          {
            'message': {
              'content': '<think>reasoning here</think>$json',
            }
          }
        ]
      });
      final client = _mockClient(200, body);
      final result = await NlpParser.parse('lunch at noon',
          client: client, secureConfig: secureConfig);

      expect(result.intent, NlpIntent.create);
      expect(result.title, 'Lunch');
    });

    test('server 4xx throws exception', () async {
      _setupConfig();
      final client = _mockClient(400, 'Bad Request');

      expect(
        () => NlpParser.parse('create event',
            client: client, secureConfig: secureConfig),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Smart Input failed'),
          ),
        ),
      );
    });

    test('malformed JSON in response throws exception', () async {
      _setupConfig();
      final body = jsonEncode({
        'choices': [
          {
            'message': {'content': 'this is not json at all'}
          }
        ]
      });
      final client = _mockClient(200, body);

      expect(
        () => NlpParser.parse('create event',
            client: client, secureConfig: secureConfig),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Smart Input failed'),
          ),
        ),
      );
    });

    test('parses all intent types correctly', () async {
      _setupConfig();
      for (final intentStr in ['create', 'edit', 'delete', 'query']) {
        final responseBody = _aiResponse({
          'intent': intentStr,
          'assistant_response': 'ok',
          'title': 'Test',
          'start_date': '2024-03-15T10:00:00.000',
          'end_date': '2024-03-15T11:00:00.000',
          'location': null,
          'target_title': null,
        });
        final client = _mockClient(200, responseBody);
        final result = await NlpParser.parse('test input',
            client: client, secureConfig: secureConfig);
        expect(result.intent, NlpIntent.values.firstWhere((e) => e.name == intentStr));
      }
    });
  });
}
