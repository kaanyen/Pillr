import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/leaderboard/fellowship_rhythm.dart';

void main() {
  test('the church row adds the fellowships up, month by month', () {
    final rows = fellowshipRhythmFromCounts(
      fellowships: const [
        RhythmCounts(key: 'youth', name: 'Youth', partners: 10, gave: {100: 8, 101: 4}),
        RhythmCounts(key: 'men', name: 'Men', partners: 5, gave: {100: 5, 101: 5}),
      ],
      months: const [100, 101, 102],
      openMonth: 102,
    );
    expect(rows.map((r) => r.name), ['Youth', 'Men', 'All']);
    expect(rows.last.partners, 15);
    expect(rows.last.gave, {100: 13, 101: 9});
    expect(rows.first.average, closeTo((8 + 4) / 20, 1e-9));
    expect(rows.first.counted, [100, 101], reason: 'the open month does not count');
  });

  test('more givers than on the book widens the fellowship, not past 100%', () {
    final r = fellowshipRhythmFromCounts(
      fellowships: const [RhythmCounts(key: 'a', name: 'A', partners: 2, gave: {100: 3})],
      months: const [100],
      openMonth: 101,
    ).first;
    expect(r.partners, 3);
    expect(r.shareIn(100), 1);
  });
}
