import '../../arms/domain/partnership_arm.dart';

/// Lowercase, trim, collapse whitespace — for loose comparison.
String normalizeArmExcelText(String s) =>
    s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

/// Finds a partnership arm from an Excel cell that may include extra wording
/// (e.g. "Church service, Programs, notes" vs configured arm "Church service").
///
/// Order: exact (case-insensitive) → segment match (comma/semicolon/slash) →
/// substring match (Excel contains arm name, or arm name contains Excel when Excel is short).
/// If several arms match, the **longest** arm name wins (most specific).
PartnershipArm? findArmMatchFromExcelCell(String raw, List<PartnershipArm> arms) {
  final active = arms.where((a) => a.isActive).toList();
  if (active.isEmpty) return null;
  final excel = normalizeArmExcelText(raw);
  if (excel.isEmpty) return null;

  for (final a in active) {
    if (normalizeArmExcelText(a.name) == excel) return a;
  }

  final segments = excel.split(RegExp(r'[,;/|]')).map(normalizeArmExcelText).where((s) => s.length >= 2);
  for (final piece in segments) {
    for (final a in active) {
      if (normalizeArmExcelText(a.name) == piece) return a;
    }
  }

  // First word vs full arm name (e.g. Excel "Rhapsody of realities" → arm "Rhapsody").
  final words = excel.split(RegExp(r'\s+')).where((w) => w.length >= 3).toList();
  if (words.isNotEmpty) {
    final first = words.first;
    for (final a in active) {
      final an = normalizeArmExcelText(a.name);
      if (an.length >= 3 && an == first) return a;
    }
  }

  // Any word equals full arm name (e.g. "SUNDAY SERVICE" → arm "Service").
  final wordTokens = excel.split(RegExp(r'\s+')).where((w) => w.length >= 2).toList();
  final wordExact = <PartnershipArm>[];
  for (final w in wordTokens) {
    for (final a in active) {
      final an = normalizeArmExcelText(a.name);
      if (an.length >= 2 && an == w) wordExact.add(a);
    }
  }
  if (wordExact.isNotEmpty) {
    final byId = <String, PartnershipArm>{};
    for (final a in wordExact) {
      byId[a.id] = a;
    }
    final unique = byId.values.toList();
    if (unique.length == 1) return unique.first;
    unique.sort((a, b) => normalizeArmExcelText(b.name).length.compareTo(normalizeArmExcelText(a.name).length));
    return unique.first;
  }

  const minSub = 3;
  final candidates = <PartnershipArm>[];
  for (final a in active) {
    final an = normalizeArmExcelText(a.name);
    if (an.length < minSub) continue;
    if (excel.contains(an)) {
      candidates.add(a);
      continue;
    }
    if (excel.length >= minSub && an.length >= excel.length && an.contains(excel)) {
      candidates.add(a);
    }
  }
  if (candidates.isEmpty) return null;
  if (candidates.length == 1) return candidates.first;

  candidates.sort((a, b) => normalizeArmExcelText(b.name).length.compareTo(normalizeArmExcelText(a.name).length));
  return candidates.first;
}
