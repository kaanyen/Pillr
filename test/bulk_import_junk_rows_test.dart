import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_columns.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_mapping.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_models.dart';

// Columns A-I, the shape of the real sheet.
const mapping = <BulkImportColumn, int>{
  BulkImportColumn.date: 0,
  BulkImportColumn.name: 1,
  BulkImportColumn.contact: 2,
  BulkImportColumn.fellowship: 3,
  BulkImportColumn.email: 4,
  BulkImportColumn.amount: 5,
  BulkImportColumn.category: 6,
};

List<String?> row({
  String date = '',
  String name = '',
  String phone = '',
  String fellowship = '',
  String email = '',
  String amount = '',
  String arm = '',
}) => [date, name, phone, fellowship, email, amount, arm];

const header = <String?>[
  'DATE', 'NAME', 'CONTACT', 'FELLOWSHIP', 'EMAIL', 'AMOUNT (GHC)', 'CATEGORY',
];

({List<BulkRawRow> rows, List<BulkImportIssue> fileIssues}) parse(
  List<List<String?>> data,
) => parseBulkImportGridWithMapping(
      [header, ...data],
      headerRowIndex: 0,
      mapping: mapping,
    );

List<String> names(List<BulkRawRow> rows) =>
    [for (final r in rows) r.valuesByColumn[BulkImportColumn.name] ?? ''];

void main() {
  final gift = row(
    date: '2026-08-03',
    name: 'Ama Boateng',
    phone: '0244000101',
    fellowship: 'Grace',
    email: 'ama@gmail.com',
    amount: '500',
    arm: 'Missions',
  );

  group('summary rows', () {
    test('a TOTAL line at the bottom is not a gift', () {
      final out = parse([gift, row(name: 'TOTAL', amount: '78,450')]);
      expect(names(out.rows), ['Ama Boateng']);
    });

    test('the wording varies from sheet to sheet', () {
      for (final word in ['Total', 'TOTALS', 'Grand Total', 'Sub Total', 'SUM']) {
        final out = parse([gift, row(name: word, amount: '1000')]);
        expect(names(out.rows), ['Ama Boateng'], reason: word);
      }
    });

    test('and it is skipped wherever it appears, not only at the end', () {
      final out = parse([gift, row(name: 'TOTAL', amount: '500'), gift]);
      expect(out.rows.length, 2);
    });

    test('a person is never dropped just because a cell says total', () {
      // Contrived, but the guard matters: anything that identifies a person
      // means the line is data.
      final out = parse([
        gift,
        row(name: 'Total', phone: '0244555000', amount: '900', date: '2026-08-04'),
      ]);
      expect(out.rows.length, 2);
    });
  });

  group('notes under the table', () {
    test('a trailing note is left out', () {
      final out = parse([gift, row(name: 'Prepared by Sis. Cindy')]);
      expect(names(out.rows), ['Ama Boateng']);
    });

    test('several trailing notes are all left out', () {
      final out = parse([
        gift,
        row(name: 'Prepared by Sis. Cindy'),
        row(name: 'Checked by Pastor'),
      ]);
      expect(names(out.rows), ['Ama Boateng']);
    });

    test('an incomplete row in the MIDDLE is kept, so the mistake shows', () {
      // Someone typed a name and stopped. That is a row to fix, not furniture.
      final out = parse([gift, row(name: 'Kofi Asare'), gift]);
      expect(names(out.rows), ['Ama Boateng', 'Kofi Asare', 'Ama Boateng']);
    });

    test('a trailing row with an amount is kept — it is a gift missing a date', () {
      final out = parse([gift, row(name: 'Kofi Asare', amount: '300')]);
      expect(names(out.rows), ['Ama Boateng', 'Kofi Asare']);
    });

    test('a trailing row with a phone is kept', () {
      final out = parse([gift, row(name: 'Kofi Asare', phone: '0244000102')]);
      expect(names(out.rows), ['Ama Boateng', 'Kofi Asare']);
    });
  });

  group('what the user is told', () {
    test('skipping is reported, never silent', () {
      final out = parse([
        gift,
        row(name: 'TOTAL', amount: '78,450'),
        row(name: 'Prepared by Sis. Cindy'),
      ]);
      expect(out.rows.length, 1);
      final issue = out.fileIssues.singleWhere(
        (i) => i.code == BulkImportIssueCode.ignoredNonDataRow,
      );
      expect(issue.severity, BulkImportSeverity.warning);
      // Sheet rows are 1-based and the header is row 1.
      expect(issue.message, contains('3, 4'));
    });

    test('a clean sheet says nothing', () {
      final out = parse([gift, gift]);
      expect(out.fileIssues, isEmpty);
    });
  });
}
