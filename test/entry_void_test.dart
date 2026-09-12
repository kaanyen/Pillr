import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/design/seline.dart';
import 'package:the_pillr/features/entries/data/entries_repository.dart';
import 'package:the_pillr/features/entries/domain/partnership_entry.dart';
import 'package:the_pillr/features/leaderboard/leaderboard_models.dart';
import 'package:the_pillr/features/entries/monthly_records_index.dart';
import 'package:the_pillr/features/arms/domain/partnership_arm.dart';

/// Voiding is how an import gets taken back without erasing what it recorded.
/// The whole design rests on one property: every money calculation in the app
/// keys on `status == 'approved'`, so a voided row falls out of all of them
/// without any of them being taught what voiding is. These pin that down.
PartnershipEntry entry({
  required String id,
  required String partnerId,
  required String status,
  double amount = 100,
  String periodId = 'p1',
  String armId = 'a1',
  String? batchId,
  DateTime? date,
}) {
  final d = date ?? DateTime(2026, 3, 12);
  // The display name has to track the partner id, or a ranking test cannot
  // tell two partners apart.
  const names = {
    'yaw': 'Yaw Darko',
    'ama': 'Ama Serwaa',
    'kofi': 'Kofi Mensah',
  };
  return PartnershipEntry(
    id: id,
    churchId: 'c1',
    partnerId: partnerId,
    partnerSnapshot: {
      'fullName': names[partnerId] ?? partnerId,
      'fellowship': 'Bethel',
    },
    partnershipArmId: armId,
    armSnapshot: const {'name': 'Missions'},
    partnershipPeriodId: periodId,
    periodSnapshot: const {'name': 'Ministry Year 2026'},
    amountCedis: amount,
    dateGiven: d,
    status: status,
    createdBy: 'u1',
    createdBySnapshot: const {'fullName': 'Ama Serwaa'},
    createdAt: d,
    updatedAt: d,
    importBatchId: batchId,
  );
}

void main() {
  group('a voided entry counts toward nothing', () {
    test('it is excluded from partner rankings', () {
      final rows = LeaderboardRow.fromEntries([
        entry(id: 'e1', partnerId: 'yaw', status: 'approved', amount: 500),
        entry(id: 'e2', partnerId: 'yaw', status: 'voided', amount: 900),
        entry(id: 'e3', partnerId: 'ama', status: 'approved', amount: 700),
      ], periodId: 'p1');

      // If the voided 900 leaked in, Yaw would lead with 1400.
      expect(rows.first.partnerName, 'Ama Serwaa');
      expect(rows.first.totalCedis, 700);
      expect(rows[1].totalCedis, 500);
    });

    test('it is excluded from monthly records', () {
      final index = MonthlyRecordsIndex.build([
        entry(id: 'e1', partnerId: 'yaw', status: 'approved', amount: 300),
        entry(id: 'e2', partnerId: 'yaw', status: 'voided', amount: 2000),
      ]);

      expect(index.summaries.single.approvedTotal, 300);
      expect(index.summaries.single.entryCount, 1);
    });

    test('it is excluded from arm rankings', () {
      final sections = ArmLeaderboard.fromEntriesAndArms(
        [
          entry(id: 'e1', partnerId: 'yaw', status: 'approved', amount: 400),
          entry(id: 'e2', partnerId: 'ama', status: 'voided', amount: 5000),
        ],
        [_arm('a1', 'Missions')],
        periodId: 'p1',
      );

      expect(sections.single.totalCedis, 400);
      expect(sections.single.rows.length, 1);
    });

    test('a declined entry was already excluded, and still is', () {
      final rows = LeaderboardRow.fromEntries([
        entry(id: 'e1', partnerId: 'yaw', status: 'approved', amount: 100),
        entry(id: 'e2', partnerId: 'ama', status: 'declined', amount: 999),
        entry(id: 'e3', partnerId: 'kofi', status: 'pending', amount: 999),
      ], periodId: 'p1');

      expect(rows.length, 1);
      expect(rows.single.totalCedis, 100);
    });
  });

  group('the entry model', () {
    test('reports voided state and whether it moves money', () {
      final voided = entry(id: 'e1', partnerId: 'yaw', status: 'voided');
      final approved = entry(id: 'e2', partnerId: 'yaw', status: 'approved');
      final pending = entry(id: 'e3', partnerId: 'yaw', status: 'pending');

      expect(voided.isVoided, isTrue);
      expect(voided.countsTowardTotals, isFalse);
      expect(approved.isVoided, isFalse);
      expect(approved.countsTowardTotals, isTrue);
      // Pending money has not been counted either.
      expect(pending.countsTowardTotals, isFalse);
    });

    test('restore reads the status from the void history, not always approved', () {
      final d = DateTime(2026, 3, 12);
      final pending = PartnershipEntry(
        id: 'e1',
        churchId: 'c1',
        partnerId: 'yaw',
        partnerSnapshot: const {'fullName': 'Yaw Darko', 'fellowship': 'Bethel'},
        partnershipArmId: 'a1',
        armSnapshot: const {'name': 'Missions'},
        partnershipPeriodId: 'p1',
        periodSnapshot: const {'name': 'Ministry Year 2026'},
        amountCedis: 100,
        dateGiven: d,
        status: 'voided',
        createdBy: 'u1',
        createdBySnapshot: const {'fullName': 'Ama Serwaa'},
        createdAt: d,
        updatedAt: d,
        editHistory: const [
          {
            'changeDescription': 'Entry voided: typed twice',
            'previousValues': {'status': 'pending'},
          },
        ],
      );
      expect(statusBeforeVoid(pending), 'pending');
      expect(statusBeforeVoid(entry(id: 'e2', partnerId: 'yaw', status: 'voided')), 'approved');
    });

    test('carries the import that created it', () {
      expect(
        entry(id: 'e1', partnerId: 'yaw', status: 'approved', batchId: 'b7')
            .importBatchId,
        'b7',
      );
      expect(
        entry(id: 'e2', partnerId: 'yaw', status: 'approved').importBatchId,
        isNull,
      );
    });
  });

  group('the status system knows what voided looks like', () {
    test('it parses, and is neither approved nor declined', () {
      expect(SelStatusStyle.parse('voided'), SelStatus.voided);
      expect(SelStatusStyle.parse('void'), SelStatus.voided);
      expect(SelStatusStyle.parse('VOIDED'), SelStatus.voided);
    });

    test('it does not read as a rejection', () {
      // Voiding is a correction someone chose to make, not a fault, so it must
      // not borrow the danger colour that declined and blocked use.
      expect(SelStatus.voided.color, isNot(SelStatus.declined.color));
      expect(SelStatus.voided.color, isNot(SelStatus.blocked.color));
      expect(SelStatus.voided.color, isNot(SelStatus.approved.color));
    });

    test('an unknown status still falls back to pending', () {
      expect(SelStatusStyle.parse('nonsense'), SelStatus.pending);
      expect(SelStatusStyle.parse(null), SelStatus.pending);
    });
  });
}

PartnershipArm _arm(String id, String name) => PartnershipArm(
      id: id,
      churchId: 'c1',
      name: name,
      isActive: true,
      sortOrder: 0,
      createdBy: 'u1',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
