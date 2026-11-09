import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/core/utils/giving_ledger_pdf.dart';
import 'package:the_pillr/core/utils/giving_ledger_report_models.dart';

GivingLedgerReportData _sampleData({required int recordCount}) {
  final records = List.generate(
    recordCount,
    (i) => PartnerGivingRecord(
      partnerName: 'Partner ${i + 1}',
      armCategory: i.isEven ? 'Tithe' : 'Missions',
      status: 'approved',
      dateGiven:
          '2026-${(i % 8 + 1).toString().padLeft(2, '0')}-${(i % 28 + 1).toString().padLeft(2, '0')}',
      amount: 1000 + i * 50,
    ),
  );

  return GivingLedgerReportData(
    organizationName: 'Demo Community Church',
    scopeLine: 'Approved giving · Ministry Year 2026',
    scopeHighlight: 'Ministry Year 2026',
    totalGivingsAmount: records.fold<double>(0, (sum, r) => sum + r.amount),
    armSummaries: const [
      ArmSummary(armCategory: 'Tithe', subtotalAmount: 500000),
      ArmSummary(armCategory: 'Missions', subtotalAmount: 250000),
      ArmSummary(armCategory: 'Building', subtotalAmount: 100000),
    ],
    records: records,
    generatedAtFormatted: 'Aug 24, 2026 22:00',
    exporterName: 'Demo Pastor',
    verificationId: 'PLR-2026-8849',
    currencySymbol: 'GHS',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('buildGivingLedgerPdfBytes renders empty giving report', () async {
    final bytes = await buildGivingLedgerPdfBytes(_sampleData(recordCount: 0));
    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('buildGivingLedgerPdfBytes renders small giving report', () async {
    final bytes = await buildGivingLedgerPdfBytes(_sampleData(recordCount: 12));
    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('buildGivingLedgerPdfBytes paginates large realistic export', () async {
    final bytes = await buildGivingLedgerPdfBytes(_sampleData(recordCount: 444));
    expect(bytes.length, greaterThan(50000));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
