import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/entries/domain/partnership_entry.dart';
import 'package:the_pillr/features/entries/providers/record_filters.dart';

final now = DateTime(2026, 8, 20, 14, 30);

PartnershipEntry entry({
  String id = 'e',
  double amount = 500,
  DateTime? dateGiven,
  String fellowship = 'Online',
  String armId = 'arm-1',
  String createdBy = 'uid-1',
}) {
  return PartnershipEntry(
    id: id,
    churchId: 'c',
    partnerId: 'p',
    partnerSnapshot: {'fullName': 'Ama Boateng', 'fellowship': fellowship},
    partnershipArmId: armId,
    armSnapshot: const {},
    partnershipPeriodId: 'period-1',
    periodSnapshot: const {},
    amountCedis: amount,
    dateGiven: dateGiven ?? now,
    status: 'approved',
    createdBy: createdBy,
    createdBySnapshot: const {},
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('slot limit', () {
    test('two filters fit', () {
      final f = RecordFilters.empty
          .withArm('arm-1')
          .withAmount(RecordAmountBand.over1000);
      expect(f.activeCount, 2);
      expect(f.isFull, isTrue);
    });

    test('a third is refused rather than silently dropping one', () {
      final f = RecordFilters.empty
          .withArm('arm-1')
          .withAmount(RecordAmountBand.over1000)
          .withFellowship('Online');
      expect(f.activeCount, 2);
      expect(f.fellowship, isNull);
      expect(f.armId, 'arm-1');
    });

    test('an already-on filter can still be changed when full', () {
      final f = RecordFilters.empty
          .withArm('arm-1')
          .withAmount(RecordAmountBand.over1000)
          .withArm('arm-2');
      expect(f.armId, 'arm-2');
      expect(f.activeCount, 2);
    });

    test('clearing frees the slot', () {
      final f = RecordFilters.empty
          .withArm('arm-1')
          .withAmount(RecordAmountBand.over1000)
          .withArm(null)
          .withFellowship('Online');
      expect(f.armId, isNull);
      expect(f.fellowship, 'Online');
      expect(f.activeCount, 2);
    });
  });

  group('date windows', () {
    test('this month starts on the first', () {
      expect(recordRangeStart(RecordDateRange.thisMonth, now), DateTime(2026, 8));
    });

    test('last month is a closed window', () {
      expect(recordRangeStart(RecordDateRange.lastMonth, now), DateTime(2026, 7));
      expect(recordRangeEnd(RecordDateRange.lastMonth, now), DateTime(2026, 8));
    });

    test('last 7 days includes today', () {
      expect(recordRangeStart(RecordDateRange.last7, now), DateTime(2026, 8, 14));
      // An entry recorded later today must not fall outside the window.
      expect(recordRangeEnd(RecordDateRange.last7, now), DateTime(2026, 8, 21));
    });
  });

  group('applyRecordFilters', () {
    final rows = [
      entry(id: 'a', dateGiven: DateTime(2026, 8, 19), amount: 50),
      entry(id: 'b', dateGiven: DateTime(2026, 7, 15), amount: 2000, fellowship: 'Campus B'),
      entry(id: 'c', dateGiven: DateTime(2026, 8, 1), armId: 'arm-2', createdBy: 'uid-2'),
    ];

    List<String> ids(List<PartnershipEntry> e) => [for (final x in e) x.id];

    test('no filters means no filtering', () {
      expect(applyRecordFilters(rows, RecordFilters.empty, now: now), same(rows));
    });

    test('date window', () {
      final out = applyRecordFilters(
        rows, RecordFilters.empty.withDateRange(RecordDateRange.thisMonth), now: now);
      expect(ids(out), ['a', 'c']);
    });

    test('last month excludes this month', () {
      final out = applyRecordFilters(
        rows, RecordFilters.empty.withDateRange(RecordDateRange.lastMonth), now: now);
      expect(ids(out), ['b']);
    });

    test('fellowship ignores casing', () {
      final out = applyRecordFilters(
        rows, RecordFilters.empty.withFellowship('campus b'), now: now);
      expect(ids(out), ['b']);
    });

    test('arm', () {
      final out = applyRecordFilters(
        rows, RecordFilters.empty.withArm('arm-2'), now: now);
      expect(ids(out), ['c']);
    });

    test('amount band excludes its upper bound', () {
      final out = applyRecordFilters(
        rows, RecordFilters.empty.withAmount(RecordAmountBand.under100), now: now);
      expect(ids(out), ['a']);
      final mid = applyRecordFilters(
        rows, RecordFilters.empty.withAmount(RecordAmountBand.from100to500), now: now);
      // 500 belongs to the 500–1,000 band, not this one.
      expect(ids(mid), isEmpty);
    });

    test('recorded by', () {
      final out = applyRecordFilters(
        rows, RecordFilters.empty.withRecordedBy('uid-2'), now: now);
      expect(ids(out), ['c']);
    });

    test('two filters are an AND', () {
      final out = applyRecordFilters(
        rows,
        RecordFilters.empty
            .withDateRange(RecordDateRange.thisMonth)
            .withAmount(RecordAmountBand.under100),
        now: now,
      );
      expect(ids(out), ['a']);
    });
  });
}
