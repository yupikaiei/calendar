import 'package:google_mlkit_entity_extraction/google_mlkit_entity_extraction.dart';

class NlpParserResult {
  final String title;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? location;

  NlpParserResult({
    required this.title,
    this.startDate,
    this.endDate,
    this.location,
  });

  @override
  String toString() {
    return 'NlpParserResult(title: $title, start: $startDate, end: $endDate, loc: $location)';
  }
}

class NlpParser {
  static EntityExtractor? _extractor;

  /// Initializes the ML Kit Extractor and downloads the English model if missing.
  static Future<void> init() async {
    final modelManager = EntityExtractorModelManager();
    final isDownloaded = await modelManager.isModelDownloaded(
      EntityExtractorLanguage.english.name,
    );
    if (!isDownloaded) {
      await modelManager.downloadModel(EntityExtractorLanguage.english.name);
    }
    _extractor = EntityExtractor(language: EntityExtractorLanguage.english);
  }

  /// Parses a natural language string into a structured event result using Google ML Kit.
  static Future<NlpParserResult> parse(String input) async {
    if (input.trim().isEmpty) {
      return NlpParserResult(title: '');
    }

    if (_extractor == null) {
      await init();
    }

    DateTime? parsedStartDate;
    DateTime? parsedEndDate;
    String? parsedLocation;

    final annotations = await _extractor!.annotateText(input);

    print('nlp_parser debug: parsing input -> "$input"');
    print('nlp_parser debug: found ${annotations.length} annotations');

    // Track which parts of the string were extracted so we can remove them from the title
    List<List<int>> removeRanges = [];

    for (final annotation in annotations) {
      bool isMatch = false;
      print(
        'nlp_parser debug: Annotation "${annotation.text}" (start: ${annotation.start}, end: ${annotation.end})',
      );
      for (final entity in annotation.entities) {
        print('nlp_parser debug:   - Entity type: ${entity.runtimeType}');
        if (entity is DateTimeEntity) {
          // ML Kit DateTimeEntity contains timestamp in milliseconds
          parsedStartDate ??= DateTime.fromMillisecondsSinceEpoch(
            entity.timestamp,
          );
          isMatch = true;
        } else if (entity is AddressEntity) {
          parsedLocation ??= annotation.text;
          isMatch = true;
        }
      }
      if (isMatch) {
        removeRanges.add([annotation.start, annotation.end]);
      }
    }

    // Default duration is 1 hour
    if (parsedStartDate != null) {
      parsedEndDate = parsedStartDate.add(const Duration(hours: 1));
    }

    // Remove extracted entities from the title
    String remainingTitle = input;
    // Sort descending by start index to safely replace without shifting
    removeRanges.sort((a, b) => b[0].compareTo(a[0]));
    for (final range in removeRanges) {
      remainingTitle = remainingTitle.replaceRange(range[0], range[1], ' ');
    }

    // 3. Fallback Location Extract (if ML Kit missed it)
    if (parsedLocation == null) {
      final locMatch = RegExp(
        r'\bat\s+(.+)$',
        caseSensitive: false,
      ).firstMatch(remainingTitle.trimRight());
      if (locMatch != null) {
        final maybeLoc = locMatch.group(1)?.trim();
        if (maybeLoc != null &&
            maybeLoc.isNotEmpty &&
            !maybeLoc.toLowerCase().contains(
              RegExp(r'\d{1,2}(:\d{2})?\s*(am|pm)'),
            )) {
          parsedLocation = maybeLoc;
          remainingTitle = remainingTitle.replaceRange(
            locMatch.start,
            locMatch.end,
            ' ',
          );
        }
      }
    }

    // Clean up title
    remainingTitle = remainingTitle.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Remove lingering prepositions like "at" or "on"
    remainingTitle = remainingTitle.replaceAll(
      RegExp(r'^(at|on|in)\s+', caseSensitive: false),
      '',
    );
    remainingTitle = remainingTitle.replaceAll(
      RegExp(r'\s+(at|on|in)$', caseSensitive: false),
      '',
    );
    remainingTitle = remainingTitle.trim();

    if (remainingTitle.isNotEmpty) {
      remainingTitle =
          remainingTitle[0].toUpperCase() + remainingTitle.substring(1);
    } else {
      remainingTitle = "New Event";
    }

    final finalResult = NlpParserResult(
      title: remainingTitle,
      startDate: parsedStartDate,
      endDate: parsedEndDate,
      location: parsedLocation,
    );

    print('nlp_parser debug: RESULT -> $finalResult');

    return finalResult;
  }
}
