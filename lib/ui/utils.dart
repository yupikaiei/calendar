import 'package:flutter/material.dart';

/// Parses a hex color string (e.g. '#FF4CAF50' or '#4CAF50') into a [Color].
/// Returns [Colors.blue] if the string is null, empty, or unparsable.
Color parseColor(String? colorStr) {
  if (colorStr == null || colorStr.isEmpty) return Colors.blue;
  try {
    var hex = colorStr.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length == 8) {
      return Color(int.parse(hex, radix: 16));
    }
    return Colors.blue;
  } catch (e) {
    return Colors.blue;
  }
}
