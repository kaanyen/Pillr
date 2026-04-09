/// Consistent display/storage formatting: each word title-cased (first letter
/// uppercase, rest lowercase). Hyphenated and apostrophe names are split per segment.
///
/// Short all-caps words (2–4 letters, letters only) are kept uppercase so common
/// fellowship codes like `FC` stay `FC` while `QADASH` becomes `Qadash`.
abstract final class TextCaseUtils {
  static String toTitleCase(String? input) {
    if (input == null) return '';
    final s = input.trim();
    if (s.isEmpty) return '';
    return s.split(RegExp(r'\s+')).map(_titleCaseWord).join(' ');
  }

  static String _titleCaseWord(String word) {
    if (word.isEmpty) return '';
    if (word.contains('-')) {
      return word.split('-').map(_titleCaseSegment).join('-');
    }
    if (word.contains("'")) {
      return word.split("'").map(_titleCaseSegment).join("'");
    }
    // Whole token only: short all-caps codes (FC, USA). Not hyphenated parts.
    final onlyLetters = RegExp(r'^[A-Za-z]+$').hasMatch(word);
    if (onlyLetters &&
        word.length >= 2 &&
        word.length <= 4 &&
        word == word.toUpperCase()) {
      return word.toUpperCase();
    }
    return _titleCaseSegment(word);
  }

  static String _titleCaseSegment(String segment) {
    if (segment.isEmpty) return '';
    if (RegExp(r'^\d').hasMatch(segment)) {
      return segment;
    }
    if (segment.length == 1) {
      return segment.toUpperCase();
    }
    return segment[0].toUpperCase() + segment.substring(1).toLowerCase();
  }

  /// Normalizes partner denormalized fields on entries and in-memory snapshots.
  static Map<String, dynamic> normalizePartnerSnapshot(Map<String, dynamic> snap) {
    final out = Map<String, dynamic>.from(snap);
    if (out['fullName'] is String) {
      out['fullName'] = toTitleCase(out['fullName'] as String);
    }
    if (out['fellowship'] is String) {
      out['fellowship'] = toTitleCase(out['fellowship'] as String);
    }
    return out;
  }

  /// Arm / period snapshot `name` field.
  static Map<String, dynamic> normalizeNamedSnapshot(Map<String, dynamic> snap) {
    final out = Map<String, dynamic>.from(snap);
    if (out['name'] is String) {
      out['name'] = toTitleCase(out['name'] as String);
    }
    return out;
  }

  /// Staff / pastor snapshot `fullName` (and optional `role` unchanged).
  static Map<String, dynamic> normalizePersonSnapshot(Map<String, dynamic> snap) {
    final out = Map<String, dynamic>.from(snap);
    if (out['fullName'] is String) {
      out['fullName'] = toTitleCase(out['fullName'] as String);
    }
    return out;
  }

  /// Activity logs / mixed entity payloads: title-case common string keys when present.
  static Map<String, dynamic> normalizeLooseEntitySnapshot(Map<String, dynamic> snap) {
    final out = Map<String, dynamic>.from(snap);
    if (out['fullName'] is String) {
      out['fullName'] = toTitleCase(out['fullName'] as String);
    }
    if (out['fellowship'] is String) {
      out['fellowship'] = toTitleCase(out['fellowship'] as String);
    }
    if (out['name'] is String) {
      out['name'] = toTitleCase(out['name'] as String);
    }
    return out;
  }
}
