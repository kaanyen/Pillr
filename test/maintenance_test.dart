import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/entries/domain/partnership_entry.dart';
import 'package:the_pillr/features/partners/domain/partner.dart';
import 'package:the_pillr/features/maintenance/domain/data_health.dart';
import 'package:the_pillr/features/maintenance/domain/totals_audit.dart';

PartnershipEntry _entry({
  required String id,
  required String partnerId,
  String status = 'approved',
  double amount = 100,
  String periodId = 'p1',
  String armId = 'a1',
  DateTime? given,
  DateTime? created,
}) {
  final g = given ?? DateTime(2026, 3, 12);
  return PartnershipEntry(
    id: id,
    churchId: 'c1',
    partnerId: partnerId,
    partnerSnapshot: const {'fullName': 'Yaw Darko'},
    partnershipArmId: armId,
    armSnapshot: const {'name': 'Missions'},
    partnershipPeriodId: periodId,
    periodSnapshot: const {'name': '2026'},
    amountCedis: amount,
    dateGiven: g,
    status: status,
    createdBy: 'u1',
    createdBySnapshot: const {'fullName': 'Ama'},
    createdAt: created ?? g,
    updatedAt: created ?? g,
  );
}

Partner _partner({
  required String id,
  String memberId = '',
  String fullName = 'Yaw Darko',
  String fellowship = 'Bethel',
  String? phone,
  double total = 0,
  int count = 0,
  bool isActive = true,
}) {
  return Partner(
    id: id,
    churchId: 'c1',
    memberId: memberId,
    fullName: fullName,
    fellowship: fellowship,
    phone: phone,
    isActive: isActive,
    totalApprovedAmount: total,
    entryCount: count,
    createdBy: 'u1',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

void main() {
  group('totals audit', () {
    test('a total that matches its entries is not reported', () {
      final expected = expectedTotalsBy(
        [
          _entry(id: 'e1', partnerId: 'yaw', amount: 300),
          _entry(id: 'e2', partnerId: 'yaw', amount: 200),
        ],
        (e) => e.partnerId,
      );

      final drift = findTotalsDrift(
        kind: TotalsDriftKind.partner,
        stored: [_partnerTotal('yaw', 500, 2)],
        expected: expected,
      );

      expect(drift, isEmpty);
    });

    test('it catches a total the trigger never updated', () {
      final expected = expectedTotalsBy(
        [_entry(id: 'e1', partnerId: 'yaw', amount: 500)],
        (e) => e.partnerId,
      );

      final drift = findTotalsDrift(
        kind: TotalsDriftKind.partner,
        stored: [_partnerTotal('yaw', 0, 0)],
        expected: expected,
      );

      expect(drift.single.amountDelta, 500);
      expect(drift.single.countDelta, 1);
    });

    test('a total that should now be zero is still reported', () {
      // The case a naive recompute misses: everything was voided, so there are
      // no entries left to walk, but the stored figure is still sitting there.
      final expected = expectedTotalsBy(
        [_entry(id: 'e1', partnerId: 'yaw', status: 'voided', amount: 800)],
        (e) => e.partnerId,
      );

      final drift = findTotalsDrift(
        kind: TotalsDriftKind.partner,
        stored: [_partnerTotal('yaw', 800, 1)],
        expected: expected,
      );

      expect(drift.single.expected, 0);
      expect(drift.single.amountDelta, -800);
    });

    test('only approved money counts', () {
      final expected = expectedTotalsBy(
        [
          _entry(id: 'e1', partnerId: 'yaw', amount: 100),
          _entry(id: 'e2', partnerId: 'yaw', status: 'pending', amount: 50),
          _entry(id: 'e3', partnerId: 'yaw', status: 'declined', amount: 50),
          _entry(id: 'e4', partnerId: 'yaw', status: 'voided', amount: 50),
        ],
        (e) => e.partnerId,
      );

      expect(expected.amountFor('yaw'), 100);
      expect(expected.countFor('yaw'), 1);
    });

    test('entries pointing at a record that no longer exists are surfaced', () {
      final expected = expectedTotalsBy(
        [_entry(id: 'e1', partnerId: 'ghost', amount: 250)],
        (e) => e.partnerId,
      );

      final drift = findTotalsDrift(
        kind: TotalsDriftKind.partner,
        stored: const [],
        expected: expected,
      );

      expect(drift.single.name, '(missing record)');
      expect(drift.single.expected, 250);
    });

    test('rounding noise is not treated as drift', () {
      final expected = expectedTotalsBy(
        [_entry(id: 'e1', partnerId: 'yaw', amount: 100.001)],
        (e) => e.partnerId,
      );
      final drift = findTotalsDrift(
        kind: TotalsDriftKind.partner,
        stored: [_partnerTotal('yaw', 100, 1)],
        expected: expected,
      );
      expect(drift, isEmpty);
    });
  });

  group('duplicate partners', () {
    test('the same member ID is the strongest signal', () {
      final pairs = findDuplicatePartners([
        _partner(id: 'a', memberId: 'ACC001', fullName: 'Yaw Darko'),
        _partner(id: 'b', memberId: 'acc001', fullName: 'Y. Darko'),
      ]);

      expect(pairs.single.confidence, 1.0);
      expect(pairs.single.reason, contains('member ID'));
    });

    test('the same name alone is reported, but not as certain', () {
      final pairs = findDuplicatePartners([
        _partner(id: 'a', memberId: 'A1', fullName: 'Kwame Mensah'),
        _partner(id: 'b', memberId: 'B2', fullName: 'kwame  mensah'),
      ]);

      expect(pairs.single.confidence, lessThan(1.0));
      expect(pairs.single.reason, 'Same name');
    });

    test('a short or partial phone number does not pair people', () {
      final pairs = findDuplicatePartners([
        _partner(id: 'a', memberId: 'A1', fullName: 'One', phone: '024'),
        _partner(id: 'b', memberId: 'B2', fullName: 'Two', phone: '024'),
      ]);
      expect(pairs, isEmpty);
    });

    test('two distinct people are left alone', () {
      final pairs = findDuplicatePartners([
        _partner(id: 'a', memberId: 'A1', fullName: 'Yaw Darko'),
        _partner(id: 'b', memberId: 'B2', fullName: 'Ama Serwaa'),
      ]);
      expect(pairs, isEmpty);
    });

    test('a pair is reported once, not twice', () {
      // Same member ID *and* same name — two signals, one pair.
      final pairs = findDuplicatePartners([
        _partner(id: 'a', memberId: 'A1', fullName: 'Yaw Darko'),
        _partner(id: 'b', memberId: 'A1', fullName: 'Yaw Darko'),
      ]);
      expect(pairs.length, 1);
    });
  });

  group('merge plan', () {
    test('it recomputes the total instead of adding two stored figures', () {
      // Both stored totals are wrong; the merge must not preserve the error.
      final keep = _partner(id: 'keep', memberId: 'A1', total: 999, count: 9);
      final absorb = _partner(id: 'absorb', memberId: 'A1', total: 555, count: 5);

      final plan = planPartnerMerge(
        keep: keep,
        absorb: absorb,
        allEntries: [
          _entry(id: 'e1', partnerId: 'keep', amount: 100),
          _entry(id: 'e2', partnerId: 'absorb', amount: 250),
          _entry(id: 'e3', partnerId: 'absorb', status: 'voided', amount: 900),
        ],
      );

      expect(plan.resultingTotal, 350);
      expect(plan.resultingCount, 2);
      expect(plan.entriesToMove.map((e) => e.id), ['e2', 'e3']);
    });
  });

  group('duplicate entries', () {
    test('the same gift recorded twice is found, oldest kept', () {
      final pairs = findDuplicateEntries([
        _entry(id: 'first', partnerId: 'yaw', created: DateTime(2026, 3, 1)),
        _entry(id: 'second', partnerId: 'yaw', created: DateTime(2026, 3, 5)),
      ]);

      expect(pairs.single.original.id, 'first');
      expect(pairs.single.duplicate.id, 'second');
    });

    test('a different amount is a different gift', () {
      final pairs = findDuplicateEntries([
        _entry(id: 'a', partnerId: 'yaw', amount: 100),
        _entry(id: 'b', partnerId: 'yaw', amount: 101),
      ]);
      expect(pairs, isEmpty);
    });

    test('the same amount on a different day is a different gift', () {
      final pairs = findDuplicateEntries([
        _entry(id: 'a', partnerId: 'yaw', given: DateTime(2026, 3, 1)),
        _entry(id: 'b', partnerId: 'yaw', given: DateTime(2026, 3, 2)),
      ]);
      expect(pairs, isEmpty);
    });

    test('an already-voided row is not offered again', () {
      final pairs = findDuplicateEntries([
        _entry(id: 'a', partnerId: 'yaw'),
        _entry(id: 'b', partnerId: 'yaw', status: 'voided'),
      ]);
      expect(pairs, isEmpty);
    });

    test('three copies produce two duplicates against one original', () {
      final pairs = findDuplicateEntries([
        _entry(id: 'a', partnerId: 'yaw', created: DateTime(2026, 3, 1)),
        _entry(id: 'b', partnerId: 'yaw', created: DateTime(2026, 3, 2)),
        _entry(id: 'c', partnerId: 'yaw', created: DateTime(2026, 3, 3)),
      ]);

      expect(pairs.length, 2);
      expect(pairs.every((p) => p.original.id == 'a'), isTrue);
    });
  });

  group('partner data issues', () {
    test('bad casing is found and a fix is proposed', () {
      final issues = findPartnerDataIssues([
        _partner(id: 'a', memberId: 'A1', fullName: 'YAW DARKO'),
      ]);

      final casing = issues.firstWhere(
        (i) => i.kind == PartnerIssueKind.casing,
      );
      expect(casing.suggestedFullName, 'Yaw Darko');
      expect(casing.isAutoFixable, isTrue);
    });

    test('a missing member ID is reported but not auto-fixable', () {
      final issues = findPartnerDataIssues([
        _partner(id: 'a', memberId: '', fullName: 'Yaw Darko'),
      ]);

      final missing = issues.firstWhere(
        (i) => i.kind == PartnerIssueKind.missingMemberId,
      );
      expect(missing.isAutoFixable, isFalse);
    });

    test('a missing fellowship explains the consequence', () {
      final issues = findPartnerDataIssues([
        _partner(id: 'a', memberId: 'A1', fellowship: ''),
      ]);

      final missing = issues.firstWhere(
        (i) => i.kind == PartnerIssueKind.missingFellowship,
      );
      expect(missing.detail, contains('fellowship rankings'));
    });

    test('a member ID used twice is flagged on both partners', () {
      final issues = findPartnerDataIssues([
        _partner(id: 'a', memberId: 'DUP', fullName: 'Yaw Darko'),
        _partner(id: 'b', memberId: 'dup', fullName: 'Ama Serwaa'),
      ]);

      final dupes =
          issues.where((i) => i.kind == PartnerIssueKind.duplicateMemberId);
      expect(dupes.length, 2);
    });

    test('a clean partner produces nothing', () {
      final issues = findPartnerDataIssues([
        _partner(id: 'a', memberId: 'A1', fullName: 'Yaw Darko', fellowship: 'Bethel'),
      ]);
      expect(issues, isEmpty);
    });

    test('a short all-caps fellowship code is left alone', () {
      // TextCaseUtils deliberately keeps FC as FC; the audit must agree with it
      // or it would report a fix that changes nothing, forever.
      final issues = findPartnerDataIssues([
        _partner(id: 'a', memberId: 'A1', fullName: 'Yaw Darko', fellowship: 'FC'),
      ]);
      expect(issues, isEmpty);
    });
  });
}

StoredTotal _partnerTotal(String id, double total, int count) => StoredTotal(
      id: id,
      name: id,
      totalApprovedAmount: total,
      entryCount: count,
    );
