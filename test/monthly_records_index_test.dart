import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/entries/domain/partnership_entry.dart';
import 'package:the_pillr/features/entries/monthly_records_index.dart';
import 'package:the_pillr/features/entries/monthly_records_models.dart';

PartnershipEntry _entry({
  required String id,
  required double amount,
  required DateTime date,
  String status = 'approved',
  String partnerId = 'p1',
  String name = 'Jane Doe',
  String fellowship = 'Youth',
}) {
  return PartnershipEntry(
    id: id,
    churchId: 'c1',
    partnerId: partnerId,
    partnerSnapshot: {'fullName': name, 'fellowship': fellowship},
    partnershipArmId: 'arm1',
    armSnapshot: {'name': 'Missions'},
    partnershipPeriodId: 'period1',
    periodSnapshot: {'name': '2026'},
    amountCedis: amount,
    dateGiven: date,
    status: status,
    createdBy: 'u1',
    createdBySnapshot: {'fullName': 'Staff'},
    createdAt: date,
    updatedAt: date,
  );
}

void main() {
  test('MonthlyRecordsIndex builds summaries in one pass', () {
    final index = MonthlyRecordsIndex.build([
      _entry(id: '1', amount: 100, date: DateTime(2026, 3, 5)),
      _entry(id: '2', amount: 50, date: DateTime(2026, 3, 8), partnerId: 'p2'),
      _entry(id: '3', amount: 200, date: DateTime(2026, 2, 1)),
      _entry(id: '4', amount: 999, date: DateTime(2026, 1, 1), status: 'pending'),
    ]);

    expect(index.summaries.length, 2);
    expect(index.summaries.first.month, MonthBucket(year: 2026, month: 3));
    expect(index.summaryFor(MonthBucket(year: 2026, month: 3))?.approvedTotal, 150);
    expect(index.partnersInMonth(MonthBucket(year: 2026, month: 3)).length, 2);
    expect(
      index.adjacentMonth(MonthBucket(year: 2026, month: 3), forward: false),
      MonthBucket(year: 2026, month: 2),
    );
  });
}
