import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/arms/domain/arm_tree.dart';
import 'package:the_pillr/features/arms/domain/partnership_arm.dart';
import 'package:the_pillr/features/entries/domain/partnership_entry.dart';
import 'package:the_pillr/features/leaderboard/fellowship_rhythm.dart';
import 'package:the_pillr/features/leaderboard/giving_view.dart';
import 'package:the_pillr/features/partners/domain/partner.dart';

final _t = DateTime(2026);

final _tithe = PartnershipArm(
  id: 'tithe',
  churchId: 'c',
  name: 'Tithe',
  isActive: true,
  sortOrder: 0,
  createdBy: 'u',
  createdAt: _t,
  updatedAt: _t,
);

Partner _p(String id, String fellowship) => Partner(
  id: id,
  churchId: 'c',
  memberId: id.toUpperCase(),
  fullName: 'Partner $id',
  fellowship: fellowship,
  isActive: true,
  totalApprovedAmount: 0,
  entryCount: 0,
  createdBy: 'u',
  createdAt: _t,
  updatedAt: _t,
);

PartnershipEntry _e(String partnerId, int month) => PartnershipEntry(
  id: '$partnerId-$month',
  churchId: 'c',
  partnerId: partnerId,
  partnerSnapshot: {'fullName': 'Partner $partnerId'},
  partnershipArmId: 'tithe',
  armSnapshot: const {},
  partnershipPeriodId: 'p26',
  periodSnapshot: const {},
  amountCedis: 100,
  dateGiven: DateTime(2026, month, 5),
  status: 'approved',
  createdBy: 'u',
  createdBySnapshot: const {},
  createdAt: _t,
  updatedAt: _t,
);

void main() {
  // Bethel: four partners, all give every month. Shiloh: four partners, all
  // give January to April, then only one in May to July.
  final roster = [
    for (final id in ['b1', 'b2', 'b3', 'b4']) _p(id, 'Bethel'),
    for (final id in ['s1', 's2', 's3', 's4']) _p(id, 'Shiloh'),
  ];
  final entries = [
    for (var m = 1; m <= 7; m++) ...[
      for (final id in ['b1', 'b2', 'b3', 'b4']) _e(id, m),
      if (m <= 4) for (final id in ['s1', 's2', 's3', 's4']) _e(id, m) else _e('s1', m),
    ],
  ];
  final view = GivingView.build(entries: entries, roster: roster, tree: ArmTree([_tithe]));
  final months = [for (var m = 1; m <= 8; m++) GivingView.monthKey(DateTime(2026, m))];
  final open = GivingView.monthKey(DateTime(2026, 8));
  final rows = fellowshipRhythm(view: view, months: months, openMonth: open);
  FellowshipRhythmRow row(String name) => rows.firstWhere((r) => r.name == name);

  test('counts who gave each month, out of the fellowship', () {
    expect(row('Bethel').partners, 4);
    expect(row('Bethel').gave[months[0]], 4);
    expect(row('Shiloh').gave[months[5]], 1);
    expect(row('Shiloh').gave[open], isNull, reason: 'nobody yet in the open month');
  });

  test('averages and trends use closed months only', () {
    expect(row('Bethel').average, 1.0);
    expect(row('Bethel').trend, RhythmTrend.steady);
    expect(row('Shiloh').trend, RhythmTrend.slipping);
    expect(row('Shiloh').average, closeTo((4 * 4 + 3 * 1) / (7 * 4), 1e-9));
  });

  test('adds an All row last', () {
    expect(rows.last.name, 'All');
    expect(rows.last.partners, 8);
    expect(rows.last.gave[months[4]], 5);
  });

  test('bands are wide so one person does not flip the colour', () {
    expect(rhythmBand(18 / 20), 3);
    expect(rhythmBand(16 / 20), 3);
    expect(rhythmBand(5 / 8), 2);
    expect(rhythmBand(3 / 8), 1);
    expect(rhythmBand(0), 0);
  });

  test('names the fellowship that dipped, and when', () {
    final dip = biggestDip(rows);
    expect(dip?.row.name, 'Shiloh');
    expect(dip?.months, months.sublist(4, 7));
  });

  test('a month with nothing recorded church-wide is not counted', () {
    // Same church, but August is closed and has no giving at all yet.
    final later = GivingView.monthKey(DateTime(2026, 9));
    final rows = fellowshipRhythm(view: view, months: months, openMonth: later);
    final bethel = rows.firstWhere((r) => r.name == 'Bethel');
    expect(bethel.isRecorded(months[7]), isFalse);
    expect(bethel.average, 1.0, reason: 'August does not drag the average down');
    expect(bethel.trend, RhythmTrend.steady);
    expect(biggestDip(rows)?.months, months.sublist(4, 7));
  });

  test('says nothing when the whole church dipped together', () {
    final roster2 = [for (final id in ['b1', 'b2', 'b3', 'b4']) _p(id, 'Bethel'), for (final id in ['s1', 's2', 's3', 's4']) _p(id, 'Shiloh')];
    final entries2 = [
      for (var m = 1; m <= 7; m++)
        for (final id in ['b1', 'b2', 'b3', 'b4', 's1', 's2', 's3', 's4'])
          if (m < 6 || id.endsWith('1')) _e(id, m),
    ];
    final v = GivingView.build(entries: entries2, roster: roster2, tree: ArmTree([_tithe]));
    expect(biggestDip(fellowshipRhythm(view: v, months: months, openMonth: open)), isNull);
  });
}
