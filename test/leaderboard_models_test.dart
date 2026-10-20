import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/arms/domain/partnership_arm.dart';
import 'package:the_pillr/features/entries/domain/partnership_entry.dart';
import 'package:the_pillr/features/leaderboard/leaderboard_models.dart';

PartnershipEntry _entry({
  required String id,
  required String partnerId,
  required String name,
  required double amount,
  required String periodId,
  required String armId,
  String fellowship = '',
  String status = 'approved',
}) {
  return PartnershipEntry(
    id: id,
    churchId: 'demo-church',
    partnerId: partnerId,
    partnerSnapshot: {
      'fullName': name,
      if (fellowship.isNotEmpty) 'fellowship': fellowship,
    },
    partnershipArmId: armId,
    armSnapshot: const {'name': 'Arm'},
    partnershipPeriodId: periodId,
    periodSnapshot: const {'name': '2026'},
    amountCedis: amount,
    dateGiven: DateTime(2026, 3, 1),
    notes: null,
    status: status,
    createdBy: 'staff',
    createdBySnapshot: const {'fullName': 'Staff'},
    createdAt: DateTime(2026, 3, 1),
    updatedAt: DateTime(2026, 3, 1),
    reviewedBy: null,
    reviewedBySnapshot: null,
    reviewedAt: null,
    declineReason: null,
    editHistory: const [],
  );
}

PartnershipArm _arm({
  required String id,
  required String name,
  required int sortOrder,
}) {
  final now = DateTime(2026, 1, 1);
  return PartnershipArm(
    id: id,
    churchId: 'demo-church',
    name: name,
    isActive: true,
    sortOrder: sortOrder,
    createdBy: 'pastor',
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  const periodId = 'period-1';

  test('LeaderboardRow ranks approved giving within one arm', () {
    final entries = [
      _entry(
        id: 'e1',
        partnerId: 'p1',
        name: 'Ama',
        amount: 200,
        periodId: periodId,
        armId: 'arm-a',
      ),
      _entry(
        id: 'e2',
        partnerId: 'p2',
        name: 'Kofi',
        amount: 500,
        periodId: periodId,
        armId: 'arm-a',
      ),
      _entry(
        id: 'e3',
        partnerId: 'p1',
        name: 'Ama',
        amount: 100,
        periodId: periodId,
        armId: 'arm-a',
      ),
      _entry(
        id: 'e4',
        partnerId: 'p3',
        name: 'Esi',
        amount: 900,
        periodId: periodId,
        armId: 'arm-b',
      ),
    ];

    final rows = LeaderboardRow.fromEntries(
      entries,
      periodId: periodId,
      armId: 'arm-a',
    );

    expect(rows, hasLength(2));
    expect(rows[0].partnerName, 'Kofi');
    expect(rows[0].rank, 1);
    expect(rows[0].totalCedis, 500);
    expect(rows[1].partnerName, 'Ama');
    expect(rows[1].totalCedis, 300);
  });

  test('ArmLeaderboard groups rankings per arm in sort order', () {
    final entries = [
      _entry(
        id: 'e1',
        partnerId: 'p1',
        name: 'Ama',
        amount: 100,
        periodId: periodId,
        armId: 'arm-b',
      ),
      _entry(
        id: 'e2',
        partnerId: 'p2',
        name: 'Kofi',
        amount: 250,
        periodId: periodId,
        armId: 'arm-a',
      ),
      _entry(
        id: 'e3',
        partnerId: 'p3',
        name: 'Esi',
        amount: 50,
        periodId: periodId,
        armId: 'arm-c',
      ),
    ];

    final sections = ArmLeaderboard.fromEntriesAndArms(
      entries,
      [
        _arm(id: 'arm-c', name: 'Building', sortOrder: 2),
        _arm(id: 'arm-a', name: 'Tithe', sortOrder: 0),
        _arm(id: 'arm-b', name: 'Missions', sortOrder: 1),
      ],
      periodId: periodId,
    );

    expect(sections.map((s) => s.armName).toList(), [
      'Tithe',
      'Missions',
      'Building',
    ]);
    expect(sections[0].rows.single.partnerName, 'Kofi');
    expect(sections[1].rows.single.totalCedis, 100);
    expect(sections[2].rows.single.partnerName, 'Esi');
    expect(sections[2].totalCedis, 50);
  });

  test('ArmLeaderboard ignores pending entries and other periods', () {
    final entries = [
      _entry(
        id: 'e1',
        partnerId: 'p1',
        name: 'Ama',
        amount: 100,
        periodId: periodId,
        armId: 'arm-a',
        status: 'pending',
      ),
      _entry(
        id: 'e2',
        partnerId: 'p2',
        name: 'Kofi',
        amount: 250,
        periodId: 'other-period',
        armId: 'arm-a',
      ),
    ];

    final sections = ArmLeaderboard.fromEntriesAndArms(
      entries,
      [_arm(id: 'arm-a', name: 'Tithe', sortOrder: 0)],
      periodId: periodId,
    );

    expect(sections.single.rows, isEmpty);
    expect(sections.single.totalCedis, 0);
  });

  test('FellowshipLeaderboard groups rankings per fellowship alphabetically', () {
    final entries = [
      _entry(
        id: 'e1',
        partnerId: 'p1',
        name: 'Ama',
        amount: 300,
        periodId: periodId,
        armId: 'arm-a',
        fellowship: 'Zion',
      ),
      _entry(
        id: 'e2',
        partnerId: 'p2',
        name: 'Kofi',
        amount: 500,
        periodId: periodId,
        armId: 'arm-a',
        fellowship: 'Bethel',
      ),
      _entry(
        id: 'e3',
        partnerId: 'p3',
        name: 'Esi',
        amount: 100,
        periodId: periodId,
        armId: 'arm-b',
        fellowship: 'Bethel',
      ),
      _entry(
        id: 'e4',
        partnerId: 'p4',
        name: 'Yaw',
        amount: 50,
        periodId: periodId,
        armId: 'arm-b',
        fellowship: 'Grace',
      ),
    ];

    final sections = FellowshipLeaderboard.fromEntries(
      entries,
      periodId: periodId,
    );

    expect(sections.map((s) => s.fellowshipName).toList(), [
      'Bethel',
      'Grace',
      'Zion',
    ]);
    expect(sections[0].rows[0].partnerName, 'Kofi');
    expect(sections[0].rows[0].totalCedis, 500);
    expect(sections[0].rows[1].partnerName, 'Esi');
    expect(sections[2].rows.single.partnerName, 'Ama');
  });

  test('LeaderboardRow filters by fellowship key case-insensitively', () {
    final entries = [
      _entry(
        id: 'e1',
        partnerId: 'p1',
        name: 'Ama',
        amount: 200,
        periodId: periodId,
        armId: 'arm-a',
        fellowship: 'BETHEL',
      ),
      _entry(
        id: 'e2',
        partnerId: 'p2',
        name: 'Kofi',
        amount: 100,
        periodId: periodId,
        armId: 'arm-a',
        fellowship: 'Zion',
      ),
    ];

    final rows = LeaderboardRow.fromEntries(
      entries,
      periodId: periodId,
      fellowshipKey: 'bethel',
    );

    expect(rows, hasLength(1));
    expect(rows.single.partnerName, 'Ama');
  });

  test('FellowshipRankRow ranks fellowships by total approved giving', () {
    final entries = [
      _entry(
        id: 'e1',
        partnerId: 'p1',
        name: 'Ama',
        amount: 300,
        periodId: periodId,
        armId: 'arm-a',
        fellowship: 'Zion',
      ),
      _entry(
        id: 'e2',
        partnerId: 'p2',
        name: 'Kofi',
        amount: 500,
        periodId: periodId,
        armId: 'arm-a',
        fellowship: 'Bethel',
      ),
      _entry(
        id: 'e3',
        partnerId: 'p3',
        name: 'Esi',
        amount: 100,
        periodId: periodId,
        armId: 'arm-b',
        fellowship: 'Bethel',
      ),
    ];

    final rows = FellowshipRankRow.fromEntries(entries, periodId: periodId);

    expect(rows, hasLength(2));
    expect(rows[0].fellowshipName, 'Bethel');
    expect(rows[0].totalCedis, 600);
    expect(rows[0].partnerCount, 2);
    expect(rows[1].fellowshipName, 'Zion');
  });

  test('FellowshipDirectoryRow lists fellowships from partners with period totals', () {
    final entries = [
      _entry(
        id: 'e1',
        partnerId: 'p1',
        name: 'Ama',
        amount: 200,
        periodId: periodId,
        armId: 'arm-a',
        fellowship: 'Bethel',
      ),
    ];

    final rows = FellowshipDirectoryRow.fromPartnersAndEntries(
      ['Bethel', 'Grace', ''],
      entries,
      periodId: periodId,
    );

    expect(rows.map((r) => r.fellowshipName).toList(), [
      'Bethel',
      'Grace',
      'No fellowship',
    ]);
    expect(rows[0].partnerCount, 1);
    expect(rows[0].periodTotalCedis, 200);
    expect(rows[1].periodTotalCedis, 0);
  });

  test('directory stays up when giving has no snapshot fellowship', () {
    final entries = [
      _entry(
        id: 'e1',
        partnerId: 'p1',
        name: 'Ama',
        amount: 200,
        periodId: periodId,
        armId: 'arm-a',
      ),
    ];

    final rows = FellowshipDirectoryRow.fromPartnersAndEntries(
      ['Bethel', 'Grace'],
      entries,
      periodId: periodId,
      fellowshipByPartnerId: const {'p1': 'Bethel'},
    );

    expect(rows.map((r) => r.fellowshipName).toList(), ['Bethel', 'Grace']);
    expect(rows[0].periodTotalCedis, 200);
    expect(rows[1].periodTotalCedis, 0);
  });

  test('directory does not crash when an entry fellowship is not on any partner', () {
    final entries = [
      _entry(
        id: 'e1',
        partnerId: 'p1',
        name: 'Ama',
        amount: 200,
        periodId: periodId,
        armId: 'arm-a',
        fellowship: 'Youth',
      ),
    ];

    final rows = FellowshipDirectoryRow.fromPartnersAndEntries(
      ['Bethel', 'Grace'],
      entries,
      periodId: periodId,
    );

    expect(rows.map((r) => r.fellowshipName).toList(), [
      'Bethel',
      'Grace',
      'Youth',
    ]);
    expect(rows.last.periodTotalCedis, 200);
    expect(rows.last.partnerCount, 0);
  });

  test('ranked fellowships use the partner group when the snapshot is blank', () {
    final entries = [
      _entry(
        id: 'e1',
        partnerId: 'p1',
        name: 'Ama',
        amount: 300,
        periodId: periodId,
        armId: 'arm-a',
      ),
      _entry(
        id: 'e2',
        partnerId: 'p2',
        name: 'Kofi',
        amount: 100,
        periodId: periodId,
        armId: 'arm-a',
      ),
    ];

    final rows = FellowshipRankRow.fromEntries(
      entries,
      periodId: periodId,
      fellowshipByPartnerId: const {'p1': 'Bethel', 'p2': 'Zion'},
    );

    expect(rows.map((r) => r.fellowshipName).toList(), ['Bethel', 'Zion']);
    expect(rows[0].totalCedis, 300);
  });
}
