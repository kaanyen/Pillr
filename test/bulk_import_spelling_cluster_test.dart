import 'package:flutter_test/flutter_test.dart';

/// Mirrors the containment rule used by the bulk-import issue groups to decide
/// which unmatched spellings are the same concept.
///
/// The interesting cases are the ones it must *not* merge: sharing a word is
/// not enough, or "Super Sunday" would be swallowed by "SUNDAY SERVICE" and
/// applying a fix would silently retag rows the reader never looked at.
List<List<String>> clusterSpellings(List<String> values) {
  Set<String> tokensOf(String v) => v
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((t) => t.length >= 3)
      .toSet();

  final sorted = [...values]..sort((a, b) => a.length.compareTo(b.length));
  final out = <List<String>>[];
  for (final v in sorted) {
    final mine = tokensOf(v);
    List<String>? home;
    for (final c in out) {
      final theirs = tokensOf(c.first);
      if (mine.isEmpty || theirs.isEmpty) continue;
      if (mine.containsAll(theirs) || theirs.containsAll(mine)) {
        home = c;
        break;
      }
    }
    if (home == null) {
      out.add([v]);
    } else {
      home.add(v);
    }
  }
  return out;
}

void main() {
  test('groups a spelling that contains another', () {
    final c = clusterSpellings(['SUNDAY SERVICE', 'Service']);
    expect(c.length, 1);
    expect(c.first.first, 'Service', reason: 'tersest spelling is the label');
    expect(c.first, containsAll(['Service', 'SUNDAY SERVICE']));
  });

  test('does not group on a merely shared word', () {
    // "Super Sunday" and "SUNDAY SERVICE" share only "sunday"; neither
    // contains the other, so merging them would be wrong.
    final c = clusterSpellings(['Super Sunday', 'SUNDAY SERVICE']);
    expect(c.length, 2);
  });

  test('the real sample sheet yields two concepts, not three', () {
    final c = clusterSpellings(['Super Sunday', 'Service', 'SUNDAY SERVICE']);
    expect(c.length, 2);
    final serviceGroup = c.firstWhere((g) => g.first == 'Service');
    expect(serviceGroup, containsAll(['Service', 'SUNDAY SERVICE']));
    expect(c.any((g) => g.first == 'Super Sunday' && g.length == 1), isTrue);
  });

  test('is case and punctuation insensitive', () {
    final c = clusterSpellings(['church service', 'CHURCH  SERVICE!']);
    expect(c.length, 1);
  });

  test('keeps unrelated values apart', () {
    final c = clusterSpellings(['Missions', 'Media', 'Church Building']);
    expect(c.length, 3);
  });

  test('short tokens are ignored so noise words do not merge concepts', () {
    // "of" is below the 3-character floor, so these stay distinct.
    final c = clusterSpellings(['Rhapsody of Realities', 'Media']);
    expect(c.length, 2);
  });
}
