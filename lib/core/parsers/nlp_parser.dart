import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'mlc_engine.dart';

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
  static const _modelFileName = 'params_shard_0.bin';
  static const _modelDownloadUrl =
      'https://huggingface.co/mlc-ai/Llama-3.2-1B-Instruct-q4f16_1-MLC/resolve/main/params_shard_0.bin';
  static const Map<String, dynamic> _jsonSchema = {
    'type': 'object',
    'properties': {
      'intent': {
        'type': 'string',
        'enum': ['query', 'create', 'delete', 'update']
      },
      'title': {
        'anyOf': [
          {'type': 'string'},
          {'type': 'null'}
        ]
      },
      'start_date': {
        'anyOf': [
          {'type': 'string'},
          {'type': 'null'}
        ]
      },
      'end_date': {
        'anyOf': [
          {'type': 'string'},
          {'type': 'null'}
        ]
      },
      'location': {
        'anyOf': [
          {'type': 'string'},
          {'type': 'null'}
        ]
      },
      'assistant_response': {'type': 'string'},
      'target_title': {
        'anyOf': [
          {'type': 'string'},
          {'type': 'null'}
        ]
      },
    },
    'required': ['intent', 'assistant_response']
  };
  static bool _isInit = false;
  static bool _engineReady = false;

  /// Initializes MLC LLM runtime and ensures model weights exist locally.
  static Future<void> init() async {
    if (_isInit) return;
    try {
      final modelFile = await _ensureModelFile();
      await MlcEngine.instance.initialize(modelPath: modelFile.path);
      _engineReady = true;
      _isInit = true;
    } catch (e) {
      developer.log(
        'Failed to initialize MLC LLM: $e',
        name: 'NlpParser',
        level: 1000,
      );
    }
  }

  /// Parses a natural language string into a structured intent result using Llama 3.2 1B.
  static Future<NlpIntentResult> parse(String input) async {
    if (input.trim().isEmpty) {
      return NlpIntentResult(
        intent: NlpIntent.unknown,
        assistantResponse: "I didn't catch that. Could you repeat?",
      );
    }

    if (!_isInit || !_engineReady) {
      await init();
    }

    if (!_engineReady) {
      throw Exception('LLM Engine not initialized properly.');
    }

    try {
      final now = DateTime.now();
      final systemPrompt = _buildSystemPrompt(input, now);
      var response = await MlcEngine.instance.complete(
        prompt: systemPrompt,
        jsonSchema: _jsonSchema,
      );

      developer.log('LLM response: $response', name: 'NlpParser');

      // Attempt to clean JSON markdown if the LLM hallucinated it
      response = response.trim();
      if (response.startsWith('```json')) {
        response = response.substring(7);
      }
      if (response.endsWith('```')) {
        response = response.substring(0, response.length - 3);
      }
      response = response.trim();

      final decoded = jsonDecode(response);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected JSON object.');
      }
      return fromJsonMap(decoded);
    } catch (e) {
      developer.log('LLM parsing failed: $e', name: 'NlpParser', level: 1000);
      throw Exception(
        'Smart Input failed to understand the request. Please try again.',
      );
    } finally {
      // Release the LLM context to free memory and prevent app slowdown
      await _releaseModel();
    }
  }

  /// Releases the LLM context to free memory.
  static Future<void> _releaseModel() async {
    if (_engineReady) {
      await MlcEngine.instance.release();
      _engineReady = false;
    }
    _isInit = false;
  }

  static Future<File> _ensureModelFile() async {
    final targetDirectory = await getApplicationDocumentsDirectory();
    final modelFile = File('${targetDirectory.path}/$_modelFileName');
    if (await modelFile.exists()) return modelFile;

    final response = await http.get(Uri.parse(_modelDownloadUrl));
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to download MLC model: ${response.statusCode} ${response.reasonPhrase ?? ''}',
      );
    }
    await modelFile.writeAsBytes(response.bodyBytes, flush: true);
    return modelFile;
  }

  @visibleForTesting
  static NlpIntentResult fromJsonMap(Map<String, dynamic> decoded) {
    DateTime? sDate;
    if (decoded['start_date'] != null) {
      sDate = DateTime.tryParse(decoded['start_date'].toString());
    }
    DateTime? eDate;
    if (decoded['end_date'] != null) {
      eDate = DateTime.tryParse(decoded['end_date'].toString());
    }

    NlpIntent parsedIntent = NlpIntent.unknown;
    switch (decoded['intent']?.toString().toLowerCase()) {
      case 'create':
        parsedIntent = NlpIntent.create;
        break;
      case 'update':
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
      assistantResponse: decoded['assistant_response']?.toString() ?? 'Okay.',
      title: decoded['title']?.toString(),
      startDate: sDate,
      endDate: eDate ?? sDate?.add(const Duration(hours: 1)),
      location: decoded['location']?.toString(),
      targetEventTitle: decoded['target_title']?.toString(),
    );
  }

  static String _buildSystemPrompt(String input, DateTime now) {
    return '''
You are a calendar assistant that extracts structured event intent from user text.
Return only valid JSON (no markdown).
Use this exact JSON schema:
${jsonEncode(_jsonSchema)}
Rules:
- intent must be one of: query, create, delete, update.
- Convert relative dates like "tomorrow" from this datetime: ${now.toIso8601String()}.
- Always include assistant_response as a short friendly sentence.
- Use ISO8601 for start_date and end_date.
- Use null when a value is unknown.
User text: "$input"
''';
  }
}
