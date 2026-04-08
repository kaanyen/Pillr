import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_columns.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_parser.dart';

void main() {
  test('parseBulkImportGrid finds header row and data', () {
    final grid = <List<String?>>[
      ['Title', null],
      [
        'DATE',
        'NAME',
        'CONTACT',
        'FELLOWSHIP',
        'EMAIL',
        'AMOUNT (GHC)',
        'CATEGORY (x)',
        'NOTES',
        'CURRENTLY WITH PASTOR (YES OR NO)',
      ],
      ['2024-01-15', 'Jane Doe', '233241234567', 'First', '', '100', 'Church service', '', 'NO'],
    ];
    final parsed = parseBulkImportGrid(grid);
    expect(parsed.fileIssues, isEmpty);
    expect(parsed.rows.length, 1);
    final row = parsed.rows.single;
    expect(row.sheetRowNumber, 3);
    expect(row.valuesByColumn[BulkImportColumn.name], 'Jane Doe');
    expect(row.valuesByColumn[BulkImportColumn.amount], '100');
  });

  test('interpretRawValues parses amount and pastor flag', () {
    final row = parseBulkImportGrid(<List<String?>>[
      [
        'DATE',
        'NAME',
        'FELLOWSHIP',
        'AMOUNT (GHC)',
        'CATEGORY',
        'CURRENTLY WITH PASTOR (YES OR NO)',
      ],
      ['2024-06-01', 'A', 'F', '50.5', 'Arm', 'YES'],
    ]).rows.single;

    final interp = interpretRawValues(row);
    expect(interp.amount, 50.5);
    expect(interp.pastorYes, isTrue);
    expect(interp.issues, isEmpty);
  });
}
