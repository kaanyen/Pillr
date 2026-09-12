import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/entries/bulk_import/batch_edit_model.dart';
import 'package:the_pillr/features/entries/domain/partnership_entry.dart';

PartnershipEntry row({
  String id = 'e1',
  String partnerId = 'yaw',
  String partnerName = 'Yaw Darko',
  double amount = 100,
  String status = 'approved',
  String armId = 'a1',
  String armName = 'Missions',
  DateTime? date,
}) {
  final d = date ?? DateTime(2026, 3, 12);
  return PartnershipEntry(
    id: id,
    churchId: 'c1',
    partnerId: partnerId,
    partnerSnapshot: {'fullName': partnerName},
    partnershipArmId: armId,
    armSnapshot: {'name': armName},
    partnershipPeriodId: 'p1',
    periodSnapshot: const {'name': '2026'},
    amountCedis: amount,
    dateGiven: d,
    status: status,
    createdBy: 'u1',
    createdBySnapshot: const {'fullName': 'Ama'},
    createdAt: d,
    updatedAt: d,
    importBatchId: 'batch-1',
  );
}

void main() {
  group('a row knows whether it was actually edited', () {
    test('an untouched row has no changes', () {
      final d = BatchRowDraft.from(row());
      expect(d.hasChanges, isFalse);
      expect(d.pesewasDelta, 0);
      expect(d.changes, isEmpty);
    });

    test('a change smaller than a pesewa is not a change', () {
      final d = BatchRowDraft.from(row(amount: 100))..amountCedis = 100.001;
      expect(d.hasChanges, isFalse, reason: 'rounds to the same pesewa');
    });

    test('a corrected amount reports the difference, not the new figure', () {
      final d = BatchRowDraft.from(row(amount: 1000000))..amountCedis = 1000;
      expect(d.amountChanged, isTrue);
      expect(d.pesewasDelta, -99900000);
      expect(d.changes.single, contains('1000000.00 → 1000.00'));
    });

    test('the same day at a different hour is not a date change', () {
      final d = BatchRowDraft.from(row(date: DateTime(2026, 3, 12, 9)))
        ..dateGiven = DateTime(2026, 3, 12, 17, 30);
      expect(d.dateChanged, isFalse);
    });

    test('moving a gift to another partner moves no money overall', () {
      final d = BatchRowDraft.from(row())
        ..partnerId = 'ama'
        ..partnerName = 'Ama Serwaa';
      expect(d.hasChanges, isTrue);
      expect(d.pesewasDelta, 0, reason: 'the church total is unchanged');
      expect(d.changes.single, 'partner: Yaw Darko → Ama Serwaa');
    });

    test('a voided row is settled and cannot be edited', () {
      final d = BatchRowDraft.from(row(status: 'voided'))..amountCedis = 5;
      expect(d.isLocked, isTrue);
      expect(d.hasChanges, isFalse, reason: 'its money is already back out');
    });

    test('reset puts a row back the way it was', () {
      final d = BatchRowDraft.from(row())
        ..amountCedis = 7
        ..dateGiven = DateTime(2020, 1, 1);
      d.reset();
      expect(d.hasChanges, isFalse);
    });
  });

  group('what the whole batch comes to', () {
    test('only approved rows count toward the total', () {
      final s = summariseBatchEdits([
        BatchRowDraft.from(row(id: 'a', amount: 100)),
        BatchRowDraft.from(row(id: 'b', amount: 250, status: 'pending')),
        BatchRowDraft.from(row(id: 'c', amount: 900, status: 'voided')),
      ]);
      expect(s.total, 100);
      expect(s.lockedRows, 1);
      expect(s.hasChanges, isFalse);
    });

    test('the total reflects the edits, not what is stored', () {
      final drafts = [
        BatchRowDraft.from(row(id: 'a', amount: 1000000)),
        BatchRowDraft.from(row(id: 'b', amount: 100)),
      ];
      drafts[0].amountCedis = 1000;

      final s = summariseBatchEdits(drafts);
      expect(s.changedRows, 1);
      expect(s.total, 1100);
      expect(s.amountDelta, -999000);
    });

    test('odd amounts still add up to the pesewa', () {
      final s = summariseBatchEdits([
        for (final a in [33.33, 33.33, 33.34])
          BatchRowDraft.from(row(id: 'r$a', amount: a)),
      ]);
      expect(s.total, 100.0);
    });
  });
}
