import 'dart:convert';
import 'package:fllama/fllama.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:io';
import 'package:path_provider/path_provider.dart';

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
  static double? _contextId;

  /// Initializes FLlama to bind with the local LLM.
  static Future<void> init() async {
    if (_isInit) return;
    try {
      // Extract the .gguf asset to a local file path so fllama can read it natively
      final byteData = await rootBundle.load(
        'assets/models/qwen2.5-0.5b-instruct.gguf',
      );
      final targetDirectory = await getApplicationDocumentsDirectory();
      final modelFile = File(
        '${targetDirectory.path}/qwen2.5-0.5b-instruct.gguf',
      );
      if (!await modelFile.exists()) {
        await modelFile.writeAsBytes(
          byteData.buffer.asUint8List(
            byteData.offsetInBytes,
            byteData.lengthInBytes,
          ),
        );
      }

      final contextRes = await Fllama.instance()?.initContext(
        modelFile.path,
        emitLoadProgress: false,
        useMlock: false,
      );
      final cIdString = contextRes?["contextId"]?.toString();
      if (cIdString != null && cIdString.isNotEmpty) {
        _contextId = double.tryParse(cIdString);
      }

      _isInit = true;
    } catch (e) {
      print('nlp_parser error: Failed to initialize fllama: $e');
    }
  }

  /// Parses a natural language string into a structured intent result using Qwen2.5.
  static Future<NlpIntentResult> parse(
    String input, {
    String? contextEvents,
  }) async {
    if (input.trim().isEmpty) {
      return NlpIntentResult(
        intent: NlpIntent.unknown,
        assistantResponse: "I didn't catch that. Could you repeat?",
      );
    }

    if (!_isInit || _contextId == null) {
      await init();
    }

    if (_contextId == null) {
      throw Exception('LLM Engine not initialized properly.');
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
      final systemPrompt =
          '''
<|im_start|>system
You are a calendar assistant. Extract the intent and details from the user's text.
Output MUST be strictly valid JSON without markdown wrapping.
Never include markdown like ```json.
Keys MUST be exactly: 
- "intent": "create", "edit", "delete", "query", or "unknown"
- "assistant_response": A short, friendly phrase acknowledging the action or answering the query.
- "title": (string) Only for create/edit
- "start_date": (ISO8601) Only for create/edit
- "end_date": (ISO8601) Only for create/edit
- "location": (string) Only for create/edit
- "target_title": (string) Only for edit/delete to identify which event to modify

When the intent is "query" (e.g. asking about availability), you MUST look at the Context (User's Schedule). If an event overlaps with the requested time, tell the user they are busy with that event. If clear, tell them they are free.

Today's Date and Time: ${now.toIso8601String()}

Context (User's Schedule):
${contextEvents ?? "None"}

Example Input:
"Am I free tomorrow at 1pm?"
Example Output:
{"intent": "query", "assistant_response": "Yes, you have no events scheduled for tomorrow at 1 PM.", "title": null, "start_date": null, "end_date": null, "location": null, "target_title": null}

Example Input:
"Am I free tonight at 8pm?"
Example Output:
{"intent": "query", "assistant_response": "No, you are busy with Dinner with Martina from 8 PM to 10 PM.", "title": null, "start_date": null, "end_date": null, "location": null, "target_title": null}

Example Input:
"Lunch with Sarah tomorrow at 1pm at Joe's Cafe"
Example Output:
{"intent": "create", "assistant_response": "I've set up Lunch with Sarah for 1 PM tomorrow.", "title": "Lunch with Sarah", "start_date": "$tomorrow1pm", "end_date": "$tomorrow2pm", "location": "Joe's Cafe", "target_title": null}
<|im_end|>
<|im_start|>user
Text: "$input"<|im_end|>
<|im_start|>assistant
{''';

      final res = await Fllama.instance()?.completion(
        _contextId!,
        prompt: systemPrompt,
        temperature: 0.1,
        nPredict: 256,
        stop: ["}", "<|im_end|>", "```"],
        penaltyRepeat: 1.18,
        emitRealtimeCompletion: false,
      );

      String response =
          '{'; // Assuming the JSON brackets are cut off from the template inject
      if (res != null) {
        if (res['text'] != null) {
          response += res['text'].toString();
        } else {
          response += res.toString(); // Fallback to raw map for debugging
        }
      }

      if (!response.trim().endsWith('}')) {
        response = response.trim() + '}';
      }

      print('nlp_parser debug: LLM Response -> $response');

      // Attempt to clean JSON markdown if the LLM hallucinated it
      response = response.trim();
      if (response.startsWith('```json')) response = response.substring(7);
      if (response.endsWith('```'))
        response = response.substring(0, response.length - 3);
      response = response.trim();

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
      print('nlp_parser error: LLM Parsing Failed (\$e)');
      throw Exception(
        'Smart Input failed to understand the request. Please try again.',
      );
    }
  }
}
