/// Derives a short prefix from a church display name (e.g. "First Baptist Church" → "FBC").
String churchInitialsFromName(String? churchName) {
  if (churchName == null || churchName.trim().isEmpty) {
    return 'CH';
  }
  const skip = {'the', 'a', 'an', 'of', 'and', 'or', 'to', 'in', 'at'};
  final words = churchName
      .replaceAll(RegExp(r'[^a-zA-Z\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && !skip.contains(w.toLowerCase()))
      .toList();
  if (words.isEmpty) {
    final alnum = churchName.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (alnum.length >= 2) {
      return alnum.substring(0, alnum.length >= 4 ? 4 : 2).toUpperCase();
    }
    return 'CH';
  }
  final buf = StringBuffer();
  for (final w in words) {
    if (buf.length >= 4) break;
    buf.write(w[0].toUpperCase());
  }
  var s = buf.toString();
  if (s.length == 1 && words.first.length > 1) {
    s = '${words.first[0]}${words.first[1]}'.toUpperCase();
  }
  return s.isEmpty ? 'CH' : s;
}
