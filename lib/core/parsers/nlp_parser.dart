import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/secure_config_service.dart';

enum NlpIntent { create, edit, delete, query, unknown }

class NlpIntentResult {
  final NlpIntent intent;
  final String assistantResponse;

  // For Create/Edit
  final String? title;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? location;

  // For Delete/Edit targeting
  final String? targetEventTitle;

  NlpIntentResult({
    required this.intent,
    required this.assistantResponse,
    this.title,
    this.startDate,
    this.endDate,
    this.location,
    this.targetEventTitle,
  });

  @override
  String toString() {
    return 'NlpIntentResult(intent: $intent, response: $assistantResponse, title: $title, start: $startDate, end: $endDate, target: $targetEventTitle)';
  }
}

class NlpParser {
  static final _logger = Logger('NlpParser');

  /// Helper that loads AI server config from shared preferences
  /// and sensitive keys from secure storage.
  static Future<Map<String, String>> _loadConfig({SecureConfigService? secureConfig}) async {
    final prefs = await SharedPreferences.getInstance();
    final secure = secureConfig ?? SecureConfigService();
    await secure.ensureMigrated();
    return {
      'baseUrl': prefs.getString('ai_base_url') ?? '',
      'apiKey': await secure.read('ai_api_key'),
      'model': prefs.getString('ai_model_name') ?? '',
    };
  }

  /// Parses a natural language string into a structured intent result
  /// by sending the request to a remote OpenAI‑compatible server.
  static Future<NlpIntentResult> parse(String input, {http.Client? client, SecureConfigService? secureConfig}) async {
    if (input.trim().isEmpty) {
      return NlpIntentResult(
        intent: NlpIntent.unknown,
        assistantResponse: "I didn't catch that. Could you repeat?",
      );
    }

    // fetch configuration
    final cfg = await _loadConfig(secureConfig: secureConfig);
    final baseUrl = cfg['baseUrl']!;
    if (baseUrl.isEmpty) {
      throw Exception(
          'AI server is not configured. Please set it in Settings.');
    }
    final apiKey = cfg['apiKey']!;
    final modelName = cfg['model']!;

    try {
      final now = DateTime.now();
      final todayDate = DateTime(now.year, now.month, now.day);
      final tomorrow = now.add(const Duration(days: 1));

      // Pre-computed example timestamps
      final todayStr = todayDate.toIso8601String().split('T')[0];
      final tomorrowStr = DateTime(tomorrow.year, tomorrow.month, tomorrow.day)
          .toIso8601String()
          .split('T')[0];
      final today2pm = '${todayStr}T14:00:00.000';
      final today3pm = '${todayStr}T15:00:00.000';
      final tomorrow1pm = '${tomorrowStr}T13:00:00.000';
      final tomorrow2pm = '${tomorrowStr}T14:00:00.000';

      final systemPrompt = '''
You are a calendar API data parser. Extract event details from user text directly into a raw JSON object.
CRITICAL RULES:
- "today" means $todayStr. "tomorrow" means $tomorrowStr.
- Map times EXACTLY: "1pm"=13:00, "2pm"=14:00, "3pm"=15:00, "4pm"=16:00, "9am"=09:00, "10am"=10:00, "noon"=12:00.
- If no end time given, default to 1 hour after start.
- THE OUTPUT MUST BE PERFECT JSON ONLY. DO NOT PROVIDE ANY REASONING OR TEXT.

Current date/time: ${now.toIso8601String()}

JSON keys:
"intent": (string) "create"|"edit"|"delete"|"query"|"unknown"
"assistant_response": (string) short friendly acknowledgment
"title": (string or null) the subject of the event (e.g., "Meeting with Sam")
"start_date": (string) ISO8601 datetime
"end_date": (string) ISO8601 datetime
"location": (string or null)
"target_title": (string or null) for edit/delete only

Example 1:
Input: "Am I free tomorrow at 1pm?"
Output: {"intent":"query","assistant_response":"Checking schedule...","title":null,"start_date":"$tomorrow1pm","end_date":"$tomorrow2pm","location":null,"target_title":null}

Example 2:
Input: "Lunch with Sarah tomorrow at 1pm at Joe's Cafe"
Output: {"intent":"create","assistant_response":"Lunch with Sarah set for 1 PM tomorrow.","title":"Lunch with Sarah","start_date":"$tomorrow1pm","end_date":"$tomorrow2pm","location":"Joe's Cafe","target_title":null}

Example 3:
Input: "Meet Alex today at 2pm in Central Park"
Output: {"intent":"create","assistant_response":"Meet Alex set for 2 PM today.","title":"Meet Alex","start_date":"$today2pm","end_date":"$today3pm","location":"Central Park","target_title":null}

Example 4:
Input: "Meeting with Magno tomorrow at 3 PM for 45 minutes at the cafe."
Output: {"intent":"create","assistant_response":"Meeting set with Magno.","title":"Meeting with Magno","start_date":"${tomorrowStr}T15:00:00.000","end_date":"${tomorrowStr}T15:45:00.000","location":"the cafe","target_title":null}
''';


      // prepare HTTP request
      final uri = Uri.parse('$baseUrl/v1/chat/completions');
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (apiKey.isNotEmpty) {
        headers['Authorization'] = 'Bearer $apiKey';
      }
      final body = <String, dynamic>{
        'model': modelName.isNotEmpty ? modelName : 'gpt-3.5-turbo',
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': input},
        ],
        'temperature': 0.1,
        'max_tokens': 2048,
      };

      final c = client ?? http.Client();
      final resp = await c.post(uri, headers: headers, body: jsonEncode(body));
      if (resp.statusCode >= 400) {
        throw Exception('AI server error ${resp.statusCode}: ${resp.body}');
      }

      final data = jsonDecode(resp.body);
      _logger.fine('Full API Response: ${resp.body}');
      
      String responseText =
          data['choices']?[0]?['message']?['content']?.toString() ?? '';

      _logger.fine('Server response: $responseText');

      // Strip <think> tags if present
      String response = responseText.trim();
      final thinkEnd = response.indexOf('</think>');
      if (thinkEnd != -1) {
        response = response.substring(thinkEnd + 8).trim();
      }

      // Find JSON block start and end robustly
      final jsonStart = response.indexOf('{');
      final jsonEnd = response.lastIndexOf('}');
      
      if (jsonStart != -1 && jsonEnd != -1 && jsonEnd > jsonStart) {
        response = response.substring(jsonStart, jsonEnd + 1);
      }

      final Map<String, dynamic> decoded = jsonDecode(response);

      DateTime? sDate;
      if (decoded['start_date'] != null) {
        sDate = DateTime.tryParse(decoded['start_date'].toString());
      }
      DateTime? eDate;
      if (decoded['end_date'] != null) {
        eDate = DateTime.tryParse(decoded['end_date'].toString());
      }

      // post-processing remains unchanged
      final extractedTime = extractTime(input);
      final extractedDate = extractDate(input, now);

      if (extractedTime != null && sDate != null) {
        final baseDate = extractedDate ??
            DateTime(sDate.year, sDate.month, sDate.day);
        sDate = DateTime(baseDate.year, baseDate.month, baseDate.day,
            extractedTime['hour']!, extractedTime['minute']!);
        eDate = eDate != null
            ? DateTime(baseDate.year, baseDate.month, baseDate.day,
                extractedTime['hour']! + 1, extractedTime['minute']!)
            : sDate.add(const Duration(hours: 1));
      } else if (extractedDate != null && sDate != null) {
        sDate = DateTime(extractedDate.year, extractedDate.month,
            extractedDate.day, sDate.hour, sDate.minute);
        if (eDate != null) {
          eDate = DateTime(extractedDate.year, extractedDate.month,
              extractedDate.day, eDate.hour, eDate.minute);
        }
      }

      NlpIntent parsedIntent = NlpIntent.unknown;
      switch (decoded['intent']?.toString().toLowerCase()) {
        case 'create':
          parsedIntent = NlpIntent.create;
          break;
        case 'edit':
          parsedIntent = NlpIntent.edit;
          break;
        case 'delete':
          parsedIntent = NlpIntent.delete;
          break;
        case 'query':
          parsedIntent = NlpIntent.query;
          break;
      }

      return NlpIntentResult(
        intent: parsedIntent,
        assistantResponse:
            decoded['assistant_response']?.toString() ?? "Okay.",
        title: decoded['title']?.toString(),
        startDate: sDate,
        endDate: eDate ?? sDate?.add(const Duration(hours: 1)),
        location: decoded['location']?.toString(),
        targetEventTitle: decoded['target_title']?.toString(),
      );
    } catch (e) {
      _logger.warning('Parsing failed: $e');
      throw Exception(
        'Smart Input failed to understand the request. Please try again.',
      );
    }
  }

  /// Extracts time (hour, minute) from natural language input using regex.
  /// Returns null if no time found.
  @visibleForTesting
  static Map<String, int>? extractTime(String input) {
    final lower = input.toLowerCase().trim();

    // Match "noon" / "midnight"
    if (RegExp(r'\bnoon\b').hasMatch(lower)) {
      return {'hour': 12, 'minute': 0};
    }
    if (RegExp(r'\bmidnight\b').hasMatch(lower)) {
      return {'hour': 0, 'minute': 0};
    }

    // Match patterns like: 2pm, 2 pm, 2:30pm, 2:30 pm, 2 p.m., 14:00
    final timeRegex = RegExp(
      r'\b(\d{1,2})(?::(\d{2}))?\s*([ap]\.?m\.?)\b',
      caseSensitive: false,
    );
    final match = timeRegex.firstMatch(lower);
    if (match != null) {
      var hour = int.parse(match.group(1)!);
      final minute = match.group(2) != null ? int.parse(match.group(2)!) : 0;
      final ampm = match.group(3)!.replaceAll('.', '').toLowerCase();

      if (ampm == 'pm' && hour != 12) hour += 12;
      if (ampm == 'am' && hour == 12) hour = 0;

      return {'hour': hour, 'minute': minute};
    }

    // Match 24-hour format like "14:00" or "09:30"
    final time24Regex = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b');
    final match24 = time24Regex.firstMatch(lower);
    if (match24 != null) {
      return {
        'hour': int.parse(match24.group(1)!),
        'minute': int.parse(match24.group(2)!),
      };
    }

    return null;
  }

  /// Extracts a date from relative words like "today", "tomorrow", day names.
  /// Returns null if no recognizable date reference found.
  @visibleForTesting
  static DateTime? extractDate(String input, DateTime now) {
    final lower = input.toLowerCase().trim();
    final today = DateTime(now.year, now.month, now.day);

    if (RegExp(r'\btoday\b').hasMatch(lower)) {
      return today;
    }
    if (RegExp(r'\btomorrow\b').hasMatch(lower)) {
      return today.add(const Duration(days: 1));
    }
    if (RegExp(r'\byesterday\b').hasMatch(lower)) {
      return today.subtract(const Duration(days: 1));
    }

    // Day names: "next Monday", "on Friday", "this Wednesday", etc.
    final dayNames = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    for (int i = 0; i < dayNames.length; i++) {
      if (RegExp('\\b${dayNames[i]}\\b').hasMatch(lower)) {
        // DateTime weekday: 1=Monday, 7=Sunday
        final targetWeekday = i + 1;
        var daysAhead = targetWeekday - now.weekday;
        if (daysAhead <= 0) daysAhead += 7; // next occurrence
        return today.add(Duration(days: daysAhead));
      }
    }

    return null;
  }
}
