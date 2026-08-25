import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/entries/domain/partnership_entry.dart';
import 'package:the_pillr/features/entries/monthly_records_models.dart';

PartnershipEntry _entry({
  required String id,
  required String partnerId,
  required String name,
  required double amount,
  required DateTime dateGiven,
  String fellowship = 'Bethel',
  String status = 'approved',
}) {
  return PartnershipEntry(
    id: id,
    churchId: 'demo-church',
    partnerId: partnerId,
    partnerSnapshot: {
      'fullName': name,
      'fellowship': fellowship,
    },
    partnershipArmId: 'arm-a',
    armSnapshot: const {'name': 'Tithe'},
    partnershipPeriodId: 'period-1',
    periodSnapshot: const {'name': '2026'},
    amountCedis: amount,
    dateGiven: dateGiven,
    notes: null,
    status: status,
    createdBy: 'staff',
    createdBySnapshot: const {'fullName': 'Staff'},
    createdAt: dateGiven,
    updatedAt: dateGiven,
    reviewedBy: null,
    reviewedBySnapshot: null,
    reviewedAt: null,
    declineReason: null,
    editHistory: const [],
  );
}

void main() {
  test('monthsWithGiving returns unique months newest first', () {
    final entries = [
      _entry(
        id: 'e1',
        partnerId: 'p1',
        name: 'Ama',
        amount: 100,
        dateGiven: DateTime(2026, 1, 15),
      ),
      _entry(
        id: 'e2',
        partnerId: 'p2',
        name: 'Kofi',
        amount: 200,
        dateGiven: DateTime(2026, 3, 2),
      ),
      _entry(
        id: 'e3',
        partnerId: 'p3',
        name: 'Esi',
        amount: 50,
        dateGiven: DateTime(2026, 3, 20),
      ),
    ];

    final months = MonthlyRecords.monthsWithGiving(entries);

    expect(months, hasLength(2));
    expect(months[0].month, 3);
    expect(months[1].month, 1);
  });

  test('partnersInMonth and fellowshipsInMonth aggregate approved giving', () {
    final month = MonthBucket(year: 2026, month: 3);
    final entries = [
      _entry(
        id: 'e1',
        partnerId: 'p1',
        name: 'Ama',
        amount: 100,
        dateGiven: DateTime(2026, 3, 1),
        fellowship: 'Bethel',
      ),
      _entry(
        id: 'e2',
        partnerId: 'p1',
        name: 'Ama',
        amount: 50,
        dateGiven: DateTime(2026, 3, 10),
        fellowship: 'Bethel',
      ),
      _entry(
        id: 'e3',
        partnerId: 'p2',
        name: 'Kofi',
        amount: 200,
        dateGiven: DateTime(2026, 3, 5),
        fellowship: 'Zion',
      ),
      _entry(
        id: 'e4',
        partnerId: 'p3',
        name: 'Yaw',
        amount: 999,
        dateGiven: DateTime(2026, 2, 28),
        fellowship: 'Grace',
        status: 'pending',
      ),
    ];

    final partners = MonthlyRecords.partnersInMonth(entries, month);
    final fellowships = MonthlyRecords.fellowshipsInMonth(entries, month);

    expect(partners, hasLength(2));
    expect(partners.first.partnerName, 'Kofi');
    expect(partners.first.totalCedis, 200);
    expect(partners[1].partnerName, 'Ama');
    expect(partners[1].totalCedis, 150);
    expect(fellowships.first.fellowshipName, 'Zion');
    expect(fellowships.first.totalCedis, 200);
    expect(fellowships[1].fellowshipName, 'Bethel');
    expect(fellowships[1].totalCedis, 150);
  });

  test('partnersInMonthForFellowship filters to one fellowship', () {
    final month = MonthBucket(year: 2026, month: 3);
    final entries = [
      _entry(
        id: 'e1',
        partnerId: 'p1',
        name: 'Ama',
        amount: 100,
        dateGiven: DateTime(2026, 3, 1),
        fellowship: 'Bethel',
      ),
      _entry(
        id: 'e2',
        partnerId: 'p2',
        name: 'Kofi',
        amount: 200,
        dateGiven: DateTime(2026, 3, 5),
        fellowship: 'Zion',
      ),
    ];

    final bethel = MonthlyRecords.partnersInMonthForFellowship(
      entries,
      month,
      'bethel',
    );

    expect(bethel, hasLength(1));
    expect(bethel.first.partnerName, 'Ama');
    expect(bethel.first.totalCedis, 100);
  });

  test('adjacentMonthWithGiving steps through months that have data', () {
    final entries = [
      _entry(
        id: 'e1',
        partnerId: 'p1',
        name: 'Ama',
        amount: 100,
        dateGiven: DateTime(2026, 1, 1),
      ),
      _entry(
        id: 'e2',
        partnerId: 'p2',
        name: 'Kofi',
        amount: 100,
        dateGiven: DateTime(2026, 3, 1),
      ),
    ];
    final march = MonthBucket(year: 2026, month: 3);

    expect(
      MonthlyRecords.adjacentMonthWithGiving(entries, march, forward: false)
          ?.month,
      1,
    );
    expect(
      MonthlyRecords.adjacentMonthWithGiving(entries, march, forward: true),
      isNull,
    );
  });
}
