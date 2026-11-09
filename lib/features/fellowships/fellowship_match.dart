import '../../core/utils/text_case_utils.dart';

/// Distinct fellowship names, title-cased, A–Z, unnamed last.
List<String> mergeKnownFellowships(
  Iterable<String> catalog,
  Iterable<String> fromPartners,
) {
  final byKey = <String, String>{};
  void add(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    final label = TextCaseUtils.toTitleCase(trimmed);
    byKey.putIfAbsent(label.toLowerCase(), () => label);
  }

  for (final n in catalog) {
    add(n);
  }
  for (final n in fromPartners) {
    add(n);
  }
  final keys = byKey.keys.toList()
    ..sort((a, b) {
      if (a.isEmpty) return 1;
      if (b.isEmpty) return -1;
      return (byKey[a] ?? a).compareTo(byKey[b] ?? b);
    });
  return [for (final k in keys) byKey[k]!];
}

bool fellowshipNamesMatch(String a, String b) =>
    a.trim().toLowerCase() == b.trim().toLowerCase();

/// Closest known group for a sheet spelling, or null if nothing is close.
String? suggestSimilarFellowship(String raw, Iterable<String> known) {
  final q = raw.trim().toLowerCase();
  if (q.isEmpty) return null;

  String? exact;
  final contained = <String>[];
  var best = (score: 0.0, name: '');

  for (final name in known) {
    final t = name.trim();
    if (t.isEmpty) continue;
    final k = t.toLowerCase();
    if (k == q) {
      exact = t;
      break;
    }
    if (k.contains(q) || q.contains(k)) contained.add(t);
    final score = _similarity(q, k);
    if (score > best.score) best = (score: score, name: t);
  }
  if (exact != null) return exact;
  if (contained.length == 1) return contained.first;
  if (best.score >= 0.55) return best.name;
  return null;
}

double _similarity(String a, String b) {
  if (a == b) return 1;
  if (a.isEmpty || b.isEmpty) return 0;
  final dist = _levenshtein(a, b);
  final maxLen = a.length > b.length ? a.length : b.length;
  final edit = 1 - (dist / maxLen);
  final ta = _tokens(a);
  final tb = _tokens(b);
  if (ta.isEmpty || tb.isEmpty) return edit;
  final overlap = ta.intersection(tb).length;
  final union = ta.union(tb).length;
  final jaccard = overlap / union;
  return edit * 0.45 + jaccard * 0.55;
}

Set<String> _tokens(String s) => s
    .split(RegExp(r'[^a-z0-9]+'))
    .where((t) => t.length >= 2)
    .toSet();

int _levenshtein(String a, String b) {
  final m = a.length;
  final n = b.length;
  final prev = List<int>.generate(n + 1, (j) => j);
  final cur = List<int>.filled(n + 1, 0);
  for (var i = 1; i <= m; i++) {
    cur[0] = i;
    for (var j = 1; j <= n; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      final del = prev[j] + 1;
      final ins = cur[j - 1] + 1;
      final sub = prev[j - 1] + cost;
      cur[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
    }
    for (var j = 0; j <= n; j++) {
      prev[j] = cur[j];
    }
  }
  return prev[n];
}
