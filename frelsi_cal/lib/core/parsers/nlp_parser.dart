import 'package:intl/intl.dart';

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
  /// Parses a natural language string into a structured event result.
  /// Example: "Lunch with Sarah tomorrow at 1pm at the cafe"
  static NlpParserResult parse(String input) {
    if (input.trim().isEmpty) {
      return NlpParserResult(title: '');
    }

    String remainingTitle = input;
    DateTime? parsedStartDate;
    DateTime? parsedEndDate;
    String? parsedLocation;

    final now = DateTime.now();

    // 1. Extract Location ("at [Location]")
    // Look for " at " followed by some text at the end of the string
    final locationMatch = RegExp(
      r'\s+at\s+([^0-9Mamp]+\s*)$',
      caseSensitive: false,
    ).firstMatch(remainingTitle);
    if (locationMatch != null) {
      parsedLocation = locationMatch.group(1)?.trim();
      remainingTitle = remainingTitle.replaceAll(locationMatch.group(0)!, '');
    }

    // 2. Extract Time
    // Match patterns like "at 1pm", "at 13:00", "1:30 pm"
    final timeMatch = RegExp(
      r'(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?',
      caseSensitive: false,
    ).firstMatch(remainingTitle);
    int? hour;
    int? minute;

    if (timeMatch != null) {
      final hourStr = timeMatch.group(1);
      final minStr = timeMatch.group(2);
      final ampm = timeMatch.group(3)?.toLowerCase();

      if (hourStr != null) {
        hour = int.tryParse(hourStr);
        if (hour != null) {
          if (ampm == 'pm' && hour < 12) hour += 12;
          if (ampm == 'am' && hour == 12) hour = 0;
        }
      }

      if (minStr != null) {
        minute = int.tryParse(minStr);
      } else {
        minute = 0;
      }

      remainingTitle = remainingTitle.replaceAll(timeMatch.group(0)!, '');
    }

    // 3. Extract Date ("tomorrow", "today", "next tuesday", "on Oct 12")
    final lowerInput = remainingTitle.toLowerCase();
    DateTime targetDate = DateTime(
      now.year,
      now.month,
      now.day,
    ); // Default today
    bool dateFound = false;

    if (lowerInput.contains('tomorrow')) {
      targetDate = targetDate.add(const Duration(days: 1));
      remainingTitle = remainingTitle.replaceAll(
        RegExp(r'\btomorrow\b', caseSensitive: false),
        '',
      );
      dateFound = true;
    } else if (lowerInput.contains('today')) {
      // already targetDate
      remainingTitle = remainingTitle.replaceAll(
        RegExp(r'\btoday\b', caseSensitive: false),
        '',
      );
      dateFound = true;
    } else {
      // Basic weekday detection (e.g. "on Monday" or "next Monday")
      final weekdays = {
        'monday': DateTime.monday,
        'tuesday': DateTime.tuesday,
        'wednesday': DateTime.wednesday,
        'thursday': DateTime.thursday,
        'friday': DateTime.friday,
        'saturday': DateTime.saturday,
        'sunday': DateTime.sunday,
      };

      for (var entry in weekdays.entries) {
        if (lowerInput.contains(entry.key)) {
          // Calculate next occurrence of this weekday
          int daysToAdd = (entry.value - targetDate.weekday + 7) % 7;
          if (daysToAdd == 0)
            daysToAdd = 7; // if today is monday, "monday" means next monday

          targetDate = targetDate.add(Duration(days: daysToAdd));
          remainingTitle = remainingTitle.replaceAll(
            RegExp(
              r'\b(on\s+|next\s+)?' + entry.key + r'\b',
              caseSensitive: false,
            ),
            '',
          );
          dateFound = true;
          break;
        }
      }
    }

    // Assemble Date and Time
    if (hour != null) {
      parsedStartDate = DateTime(
        targetDate.year,
        targetDate.month,
        targetDate.day,
        hour,
        minute ?? 0,
      );
      // Default 1 hour duration
      parsedEndDate = parsedStartDate.add(const Duration(hours: 1));
    } else if (dateFound) {
      // All day event or just date specified without time
      parsedStartDate = targetDate;
      parsedEndDate = targetDate.add(const Duration(hours: 1));
    }

    // Clean up title
    remainingTitle = remainingTitle.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Capitalize first letter
    if (remainingTitle.isNotEmpty) {
      remainingTitle =
          remainingTitle[0].toUpperCase() + remainingTitle.substring(1);
    } else {
      remainingTitle = "New Event";
    }

    return NlpParserResult(
      title: remainingTitle,
      startDate: parsedStartDate,
      endDate: parsedEndDate,
      location: parsedLocation,
    );
  }
}
