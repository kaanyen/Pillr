import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/entries/domain/partnership_entry.dart';
import 'package:the_pillr/core/utils/giving_ledger_report_models.dart';

PartnershipEntry _entry({
  required String id,
  required String partnerName,
  required String arm,
  required double amount,
  required DateTime dateGiven,
  String periodName = 'Ministry Year 2026',
  String status = 'approved',
  String fellowship = 'Bethel',
}) {
  return PartnershipEntry(
    id: id,
    churchId: 'demo-church',
    partnerId: 'p-$id',
    partnerSnapshot: {
      'fullName': partnerName,
      'fellowship': fellowship,
    },
    partnershipArmId: 'arm-$arm',
    armSnapshot: {'name': arm},
    partnershipPeriodId: 'period-1',
    periodSnapshot: {'name': periodName},
    amountCedis: amount,
    dateGiven: dateGiven,
    notes: null,
    status: status,
    createdBy: 'staff',
    createdBySnapshot: const {'fullName': 'Staff User'},
    createdAt: dateGiven,
    updatedAt: dateGiven,
    reviewedBy: 'pastor',
    reviewedBySnapshot: const {'fullName': 'Demo Pastor'},
    reviewedAt: dateGiven,
    declineReason: null,
    editHistory: const [],
  );
}

void main() {
  test('fromEntries builds arm summaries and dynamic scope', () {
    final data = GivingLedgerReportBuilder.fromEntries(
      entries: [
        _entry(
          id: '1',
          partnerName: 'Ama',
          arm: 'Missions',
          amount: 100,
          dateGiven: DateTime(2026, 3, 1),
        ),
        _entry(
          id: '2',
          partnerName: 'Kofi',
          arm: 'Tithe',
          amount: 200,
          dateGiven: DateTime(2026, 3, 5),
        ),
        _entry(
          id: '3',
          partnerName: 'Esi',
          arm: 'Missions',
          amount: 50,
          dateGiven: DateTime(2026, 3, 10),
        ),
      ],
      organizationName: 'Demo Community Church',
      filterDescription: 'Approved · Missions',
      periodScope: 'Ministry Year 2026',
      generatedAtFormatted: 'Aug 24, 2026 21:16',
      exporterName: 'Demo Pastor',
      verificationSeed: DateTime(2026, 8, 24, 21, 16),
    );

    expect(data.totalGivingsAmount, 350);
    expect(data.scopeHighlight, 'Ministry Year 2026');
    expect(data.scopeLine, contains('Approved'));
    expect(data.scopeLine, contains('giving'));
    expect(data.scopeLine, isNot(contains('ledger')));
    expect(data.armSummaries, hasLength(2));
    expect(data.armSummaries.first.armCategory, 'Tithe');
    expect(data.records, hasLength(3));
    expect(data.verificationId, startsWith('PLR-2026-'));
  });

  test('buildScopeLine hides default all-statuses filter', () {
    final line = GivingLedgerReportBuilder.buildScopeLine(
      entries: [
        _entry(
          id: '1',
          partnerName: 'Ama',
          arm: 'Tithe',
          amount: 100,
          dateGiven: DateTime(2026, 8, 1),
        ),
      ],
      periodScope: 'Ministry Year 2026',
      filterDescription: 'All statuses · Tithe — 12 entries',
    );

    expect(line, isNot(contains('All statuses')));
    expect(line, contains('Ministry Year 2026'));
    expect(line, contains('Tithe arm'));
  });

  test('buildScopeLine strips entry counts and avoids ledger wording', () {
    final line = GivingLedgerReportBuilder.buildScopeLine(
      entries: [
        _entry(
          id: '1',
          partnerName: 'Ama',
          arm: 'Missions',
          amount: 100,
          dateGiven: DateTime(2026, 8, 1),
        ),
      ],
      periodScope: 'Ministry Year 2026',
      filterDescription: 'Approved — 12 entries',
    );

    expect(line, contains('Approved giving'));
    expect(line, contains('Ministry Year 2026'));
    expect(line, isNot(contains('entries')));
  });

  test('verificationId is stable for the same seed time', () {
    final at = DateTime(2026, 8, 24, 21, 16);
    expect(
      GivingLedgerReportBuilder.verificationId(at),
      GivingLedgerReportBuilder.verificationId(at),
    );
  });
}
