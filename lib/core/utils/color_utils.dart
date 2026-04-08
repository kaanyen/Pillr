import 'package:flutter/material.dart';

/// Parses `#RRGGBB` or `RRGGBB` (and optional AARRGGBB) from Firestore.
Color? parseHexColor(String? hex) {
  if (hex == null || hex.trim().isEmpty) return null;
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 6) {
    return Color(int.parse(h, radix: 16) + 0xFF000000);
  }
  if (h.length == 8) {
    return Color(int.parse(h, radix: 16));
  }
  return null;
}
