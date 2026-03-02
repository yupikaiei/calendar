import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_gemma/flutter_gemma.dart';

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
  static bool _isInit = false;
  static dynamic _model;

    static const _modelName = 'gemma3-270m-it-q8.task';
    static const _modelUrl =
      'https://huggingface.co/litert-community/gemma-3-270m-it/resolve/main/gemma3-270m-it-q8.task';

  /// Ensures the Gemma model is installed and ready to use.
  static Future<void> init() async {
    if (_isInit) return;
    try {
      final installed = await FlutterGemma.isModelInstalled(_modelName);
      if (!installed) {
        debugPrint('[NlpParser] Installing Gemma model from network...');
        await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
            .fromNetwork(_modelUrl)
            .install();
        debugPrint('[NlpParser] Model installation complete');
      }

      _model = await FlutterGemma.getActiveModel(
        maxTokens: 2048,
        preferredBackend: PreferredBackend.cpu,
      );
      _isInit = true;
      debugPrint('[NlpParser] Gemma initialized successfully');
    } catch (e, stack) {
      debugPrint('[NlpParser] Failed to initialize Gemma: $e\n$stack');
      _model = null;
      _isInit = false;
    }
  }

  /// Releases the Gemma model to free memory.
  static Future<void> _releaseModel() async {
    if (_model != null) {
      try {
        await _model.close();
      } catch (e) {
        debugPrint('[NlpParser] Failed to release model: $e');
      }
      _model = null;
      _isInit = false;
    }
  }

  /// Parses a natural language string into a structured intent result using Gemma.
  static Future<NlpIntentResult> parse(String input) async {
    if (input.trim().isEmpty) {
      return NlpIntentResult(
        intent: NlpIntent.unknown,
        assistantResponse: "I didn't catch that. Could you repeat?",
      );
    }

    if (!_isInit || _model == null) {
      await init();
    }

    if (_model == null) {
      throw Exception('Model not initialized properly.');
    }

    try {
      final now = DateTime.now();
      final tomorrow = now.add(const Duration(days: 1));
      final tomorrow1pm = DateTime(
        tomorrow.year,
        tomorrow.month,
        tomorrow.day,
        13,
      ).toIso8601String();
      final tomorrow2pm = DateTime(
        tomorrow.year,
        tomorrow.month,
        tomorrow.day,
        14,
      ).toIso8601String();

      final systemPrompt = '''
Act as the best calendar personal assistant. You are an expert understanding the user intent and extraction event details from natural language text. 
Your goal is to extract the intent and details from the user's natural language text.
Output MUST be strictly valid JSON without markdown wrapping.
Never include markdown like ```json.
Keys MUST be exactly: 
- "intent": "create", "edit", "delete", "query", or "unknown"
- "assistant_response": A short, friendly phrase acknowledging the action.
- "title": (string) Only for create/edit
- "start_date": (ISO8601) Only for create/edit/query
- "end_date": (ISO8601) Only for create/edit/query
- "location": (string) Only for create/edit
- "target_title": (string) Only for edit/delete to identify which event to modify

For "query" intents (e.g. asking about availability), set start_date and end_date to the time range being asked about and set assistant_response to "Checking schedule...".
For "create" intents, always proceed. Never refuse or say an event already exists.

Today's Date and Time: ${now.toIso8601String()}

Example Input:
"Am I free tomorrow at 1pm?"
Example Output:
{"intent": "query", "assistant_response": "Checking schedule...", "title": null, "start_date": "$tomorrow1pm", "end_date": "$tomorrow2pm", "location": null, "target_title": null}

Example Input:
"Lunch with Sarah tomorrow at 1pm at Joe's Cafe"
Example Output:
{"intent": "create", "assistant_response": "I've set up Lunch with Sarah for 1 PM tomorrow.", "title": "Lunch with Sarah", "start_date": "$tomorrow1pm", "end_date": "$tomorrow2pm", "location": "Joe's Cafe", "target_title": null}

Example Input:
"Delete my dentist appointment"
Example Output:
{"intent": "delete", "assistant_response": "Removing dentist appointment.", "title": null, "start_date": null, "end_date": null, "location": null, "target_title": "dentist appointment"}
''';

      // create a chat session and add messages
      final chat = await _model.createChat(temperature: 0.1);
      await chat.addQueryChunk(Message.systemInfo(text: systemPrompt));
      await chat.addQueryChunk(Message.text(text: input, isUser: true));

      String responseText = '';
      final resp = await chat.generateChatResponse();
      if (resp is TextResponse) {
        responseText = resp.token;
      } else {
        responseText = resp.toString();
      }

      // No chat.close() needed for InferenceChat in flutter_gemma

      String response = responseText.trim();
      if (response.startsWith('```json')) {
        response = response.substring(7);
      }
      if (response.endsWith('```')) {
        response = response.substring(0, response.length - 3);
      }
      response = response.trim();

      debugPrint('[NlpParser] LLM response: $response');

      final decoded = jsonDecode(response);

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
        assistantResponse: decoded['assistant_response']?.toString() ?? "Okay.",
        title: decoded['title']?.toString(),
        startDate: sDate,
        endDate: eDate ?? sDate?.add(const Duration(hours: 1)),
        location: decoded['location']?.toString(),
        targetEventTitle: decoded['target_title']?.toString(),
      );
    } catch (e) {
      debugPrint('[NlpParser] LLM parsing failed: $e');
      throw Exception(
        'Smart Input failed to understand the request. Please try again.',
      );
    } finally {
      // Release the model to free memory and prevent app slowdown
      await _releaseModel();
    }
  }
}

