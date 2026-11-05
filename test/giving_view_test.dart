import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/arms/domain/arm_tree.dart';
import 'package:the_pillr/features/arms/domain/partnership_arm.dart';
import 'package:the_pillr/features/entries/domain/partnership_entry.dart';
import 'package:the_pillr/features/leaderboard/giving_view.dart';
import 'package:the_pillr/features/partners/domain/partner.dart';
import 'package:the_pillr/features/periods/domain/partnership_period.dart';

final _t = DateTime(2026);

PartnershipArm arm(String id, int order, {String? parent}) => PartnershipArm(
  id: id,
  churchId: 'c',
  name: id[0].toUpperCase() + id.substring(1),
  isActive: true,
  sortOrder: order,
  parentArmId: parent,
  createdBy: 'u',
  createdAt: _t,
  updatedAt: _t,
);

Partner partner(String id, String fellowship) => Partner(
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

PartnershipEntry entry(
  String partnerId,
  String armId,
  double amount,
  DateTime given, {
  String period = 'p26',
}) => PartnershipEntry(
  id: '$partnerId-$armId-${given.millisecondsSinceEpoch}',
  churchId: 'c',
  partnerId: partnerId,
  partnerSnapshot: {'fullName': 'Partner $partnerId'},
  partnershipArmId: armId,
  armSnapshot: const {},
  partnershipPeriodId: period,
  periodSnapshot: const {},
  amountCedis: amount,
  dateGiven: given,
  status: 'approved',
  createdBy: 'u',
  createdBySnapshot: const {},
  createdAt: given,
  updatedAt: given,
);

void main() {
  final tree = ArmTree([
    arm('tithe', 0),
    arm('building', 1),
    arm('roof', 2, parent: 'building'),
  ]);
  final period = PartnershipPeriod(
    id: 'p26',
    churchId: 'c',
    name: '2026',
    startDate: DateTime(2026, 1, 1),
    endDate: DateTime(2026, 12, 31),
    isActive: true,
    totalApprovedAmount: 0,
    entryCount: 0,
    createdBy: 'u',
    createdAt: _t,
    updatedAt: _t,
  );
  final roster = [
    partner('a', 'Bethel'),
    partner('b', 'bethel'),
    partner('c', 'Zion'),
    partner('d', 'Zion'),
  ];
  final view = GivingView.build(
    entries: [
      entry('a', 'tithe', 500, DateTime(2026, 1, 5)),
      entry('a', 'roof', 200, DateTime(2026, 1, 9)),
      entry('b', 'building', 300, DateTime(2026, 3, 1)),
      entry('c', 'tithe', 1200, DateTime(2026, 3, 2)),
      // Another period: never counted.
      entry('d', 'tithe', 9999, DateTime(2025, 6, 1), period: 'p25'),
    ],
    roster: roster,
    tree: tree,
    period: period,
  );

  test('a sub-arm counts toward its main arm, and only main arms show', () {
    expect(view.arms.map((a) => a.id), ['tithe', 'building']);
    expect(view.armTotal('building'), 500);
    expect(view.armTotal('tithe'), 1700);
    expect(view.total, 2200);
    expect(view.entryCount, 4);
  });

  test('every month of the period is a row, empty or not', () {
    expect(view.months.length, 12);
    expect(view.monthTotal(GivingView.monthKey(DateTime(2026, 2))), 0);
  });

  test('arm by month adds up to the arm and the month', () {
    final jan = GivingView.monthKey(DateTime(2026, 1));
    final mar = GivingView.monthKey(DateTime(2026, 3));
    expect(view.armByMonth[jan]!['building'], 200);
    expect(view.armByMonth[mar]!['tithe'], 1200);
    final bethel = view.fellowship('bethel')!;
    final perArm = view.partners
        .where((p) => p.fellowshipKey == 'bethel')
        .fold<double>(0, (s, p) => s + (p.byArmMonth[jan]?['building'] ?? 0));
    expect(perArm, 200);
    expect(bethel.byMonth[jan], 700);
  });

  test('fellowships group regardless of casing and count their roster', () {
    final bethel = view.fellowship('bethel')!;
    expect(bethel.partners, 2);
    expect(bethel.gave, {'a', 'b'});
    expect(bethel.total, 1000);
    final zion = view.fellowship('zion')!;
    expect(zion.partners, 2);
    expect(zion.gave, {'c'});
  });

  test('places rank fellowships overall and per arm', () {
    expect(view.placeOf('zion'), 1);
    expect(view.placeOf('bethel'), 2);
    expect(view.placeOf('bethel', armId: 'building'), 1);
  });

  test('partners are biggest first, with first and last dates', () {
    expect(view.partners.map((p) => p.partnerId), ['c', 'a', 'b']);
    final a = view.partners.firstWhere((p) => p.partnerId == 'a');
    expect(a.firstGave, DateTime(2026, 1, 5));
    expect(a.lastGave, DateTime(2026, 1, 9));
  });
}
