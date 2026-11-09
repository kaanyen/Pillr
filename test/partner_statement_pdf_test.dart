import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/core/utils/partner_statement_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('receipt numbers are short and stable', () {
    expect(receiptNumberFor('8f2kxa61qa'), 'R-8F2K-61QA');
    expect(receiptNumberFor('8f2kxa61qa'), receiptNumberFor('8f2kxa61qa'));
    expect(receiptNumberFor('ab'), 'R-AB00-0000');
  });

  test('a statement renders, with and without giving', () async {
    PartnerStatementData data(List<StatementLine> lines) => PartnerStatementData(
      churchName: 'Demo Community Church',
      partnerName: 'Ama Boateng',
      memberId: 'DCC100009',
      fellowship: 'Bethel',
      periodName: '2026 partnership year',
      periodStart: DateTime(2026),
      periodEnd: DateTime(2026, 12, 31),
      lines: lines,
      pastorName: 'Demo Pastor',
      madeBy: 'Demo Pastor',
      madeAt: DateTime(2026, 11, 8),
      checkCode: 'PLR-2026-4417',
    );
    final some = await buildPartnerStatementPdfBytes(data([
      StatementLine(date: DateTime(2026, 10, 3), arm: 'Tithe', amount: 800),
      StatementLine(date: DateTime(2026, 9, 7), arm: 'Building', amount: 630),
    ]));
    expect(String.fromCharCodes(some.take(4)), '%PDF');
    expect(data(const []).total, 0);
    final none = await buildPartnerStatementPdfBytes(data(const []));
    expect(String.fromCharCodes(none.take(4)), '%PDF');
  });

  test('a receipt renders', () async {
    final bytes = await buildEntryReceiptPdfBytes(EntryReceiptData(
      churchName: 'Demo Community Church',
      partnerName: 'Ama Boateng',
      memberId: 'DCC100009',
      fellowship: 'Bethel',
      amount: 1250,
      arm: 'Tithe',
      dateGiven: DateTime(2026, 10, 3),
      periodName: '2026 partnership year',
      approvedAt: DateTime(2026, 10, 4),
      approvedBy: 'Demo Pastor',
      recordedBy: 'Demo Staff',
      receiptNumber: receiptNumberFor('8f2kxa61qa'),
      pastorName: 'Demo Pastor',
      madeAt: DateTime(2026, 11, 8),
    ));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
