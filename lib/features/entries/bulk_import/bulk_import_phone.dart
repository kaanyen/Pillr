/// Digits-only normalization for partner phone matching.
String normalizePhoneDigits(String? raw) {
  if (raw == null) return '';
  return raw.replaceAll(RegExp(r'\D'), '');
}
