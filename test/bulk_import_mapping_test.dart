import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_columns.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_mapping.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_sources.dart';

void main() {
  group('detectBulkImportHeaders', () {
    test('finds a clean header row and maps the obvious fields', () {
      final grid = parseCsvGrid(
        'DATE,NAME,AMOUNT,CATEGORY\n2026-03-04,Ama,500,Missions',
      );
      final d = detectBulkImportHeaders(grid);
      expect(d.headerRowIndex, 0);
      expect(d.mapping[BulkImportColumn.date], 0);
      expect(d.mapping[BulkImportColumn.name], 1);
      expect(d.mapping[BulkImportColumn.amount], 2);
      expect(d.missingRequired, isEmpty);
    });

    test('skips a title block above the headers', () {
      final grid = parseCsvGrid(
        'PARTNERSHIP RECORD,,,\n2026 Q1,,,\n\nDATE,NAME,AMOUNT\n2026-03-04,Ama,500',
      );
      final d = detectBulkImportHeaders(grid);
      expect(d.labels.first, 'DATE');
      expect(d.mapping[BulkImportColumn.name], 1);
    });

    test('an unrecognised header is reported as missing, not silently dropped',
        () {
      // This is the bug the mapping step exists for: "Amount Given" is not a
      // spelling the app knows, so amount must surface as needing attention.
      final grid = parseCsvGrid('DATE,NAME,Amount Given\n2026-03-04,Ama,500');
      final d = detectBulkImportHeaders(grid);
      expect(d.mapping.containsKey(BulkImportColumn.amount), isFalse);
      expect(d.missingRequired, contains(BulkImportColumn.amount));
      // The column is still offered to the user to map by hand.
      expect(d.labels, contains('Amount Given'));
    });

    test('still returns a header row when nothing at all is recognised', () {
      final grid = parseCsvGrid('Col A,Col B,Col C\n1,2,3');
      final d = detectBulkImportHeaders(grid);
      expect(d.found, isTrue, reason: 'user must still reach the mapping step');
      expect(d.mapping, isEmpty);
      expect(d.missingRequired.length, 3);
    });

    test('picks the row that identifies the most fields', () {
      final grid = parseCsvGrid('NAME,notes\nDATE,NAME,AMOUNT\n2026-03-04,Ama,500');
      final d = detectBulkImportHeaders(grid);
      expect(d.headerRowIndex, 1);
    });
  });

  group('parseBulkImportGridWithMapping', () {
    test('builds rows from an explicit mapping', () {
      final grid = parseCsvGrid('DATE,NAME,Amount Given\n2026-03-04,Ama,500');
      final res = parseBulkImportGridWithMapping(
        grid,
        headerRowIndex: 0,
        mapping: const {
          BulkImportColumn.date: 0,
          BulkImportColumn.name: 1,
          BulkImportColumn.amount: 2, // corrected by the user
        },
      );
      expect(res.rows.length, 1);
      expect(res.rows.first.valuesByColumn[BulkImportColumn.amount], '500');
      expect(res.rows.first.sheetRowNumber, 2);
    });

    test('ignores blank rows', () {
      final grid = parseCsvGrid('DATE,NAME\n2026-03-04,Ama\n,\n2026-03-05,Kweku');
      final res = parseBulkImportGridWithMapping(
        grid,
        headerRowIndex: 0,
        mapping: const {BulkImportColumn.date: 0, BulkImportColumn.name: 1},
      );
      expect(res.rows.length, 2);
    });

    test('a mapping pointing past the end of a short row is skipped safely', () {
      final grid = parseCsvGrid('DATE,NAME,AMOUNT\n2026-03-04,Ama');
      final res = parseBulkImportGridWithMapping(
        grid,
        headerRowIndex: 0,
        mapping: const {
          BulkImportColumn.date: 0,
          BulkImportColumn.name: 1,
          BulkImportColumn.amount: 2,
        },
      );
      expect(res.rows.length, 1);
      expect(res.rows.first.valuesByColumn.containsKey(BulkImportColumn.amount),
          isFalse);
    });
  });
}
