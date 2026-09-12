/// Consistent display/storage formatting: each word title-cased (first letter
/// uppercase, rest lowercase). Hyphenated and apostrophe names are split per segment.
///
/// A value that is *entirely* one short all-caps token (2–4 letters) is left
/// alone, so a fellowship recorded as `FC` or `USA` keeps its capitals while
/// `QADASH` becomes `Qadash`.
///
/// That rule deliberately does not apply inside a multi-word value. It used to,
/// and it mangled names: Ghanaian day-names are three and four letters, so an
/// all-caps spreadsheet — which is most of them — turned `YAW DARKO` into
/// `YAW Darko`, `KOFI MENSAH` into `KOFI Mensah`, and `JOHN MENSAH` into
/// `JOHN Mensah`, while `KWAME NKRUMAH` came out right because it is five
/// letters. A person's name is never an acronym; a bare fellowship code often
/// is. Being one word is what tells them apart.
abstract final class TextCaseUtils {
  // Hoisted out of the methods below. These run once per word, per field, per
  // document, on every Firestore snapshot — building them inline compiled tens
  // of thousands of identical patterns per refresh of a large entry list.
  static final RegExp _whitespace = RegExp(r'\s+');
  static final RegExp _onlyLetters = RegExp(r'^[A-Za-z]+$');
  static final RegExp _leadingDigit = RegExp(r'^\d');

  static String toTitleCase(String? input) {
    if (input == null) return '';
    final s = input.trim();
    if (s.isEmpty) return '';
    final words = s.split(_whitespace);
    // The acronym exemption is for a value that *is* a code, not for a short
    // word that happens to sit inside a name.
    if (words.length == 1 && _looksLikeCode(words.first)) return words.first;
    return words.map(_titleCaseSegmentedWord).join(' ');
  }

  /// A bare 2–4 letter all-caps token: `FC`, `USA`.
  static bool _looksLikeCode(String word) =>
      word.length >= 2 &&
      word.length <= 4 &&
      word == word.toUpperCase() &&
      _onlyLetters.hasMatch(word);

  static String _titleCaseSegmentedWord(String word) {
    if (word.isEmpty) return '';
    if (word.contains('-')) {
      return word.split('-').map(_titleCaseSegment).join('-');
    }
    if (word.contains("'")) {
      return word.split("'").map(_titleCaseSegment).join("'");
    }
    return _titleCaseSegment(word);
  }

  static String _titleCaseSegment(String segment) {
    if (segment.isEmpty) return '';
    if (_leadingDigit.hasMatch(segment)) {
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
