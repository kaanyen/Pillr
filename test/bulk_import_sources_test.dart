import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_sources.dart';

void main() {
  group('parseCsvGrid', () {
    test('splits plain rows and columns', () {
      final g = parseCsvGrid('Date,Name,Amount\n2026-03-04,Ama Boateng,500');
      expect(g.length, 2);
      expect(g[1], ['2026-03-04', 'Ama Boateng', '500']);
    });

    test('keeps commas inside quoted fields', () {
      final g = parseCsvGrid('Name,Notes\n"Attah, Kweku","Gave twice, in cash"');
      expect(g[1], ['Attah, Kweku', 'Gave twice, in cash']);
    });

    test('unescapes doubled quotes', () {
      final g = parseCsvGrid('Name\n"She said ""yes"""');
      expect(g[1].first, 'She said "yes"');
    });

    test('handles newlines inside quoted fields', () {
      final g = parseCsvGrid('Name,Notes\nAma,"line one\nline two"');
      expect(g.length, 2);
      expect(g[1][1], 'line one\nline two');
    });

    test('handles CRLF line endings', () {
      final g = parseCsvGrid('a,b\r\nc,d\r\n');
      expect(g, [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });

    test('drops trailing empty rows spreadsheets add', () {
      final g = parseCsvGrid('a,b\nc,d\n,\n,\n');
      expect(g.length, 2);
    });

    test('preserves empty cells in the middle of a row', () {
      final g = parseCsvGrid('a,,c');
      expect(g.first, ['a', '', 'c']);
    });
  });

  group('parsePastedGrid', () {
    test('prefers tabs, which is what spreadsheets put on the clipboard', () {
      final g = parsePastedGrid('Date\tName\tAmount\n2026-03-04\tAma\t500');
      expect(g[1], ['2026-03-04', 'Ama', '500']);
    });

    test('a tabbed cell containing a comma stays one cell', () {
      final g = parsePastedGrid('Name\tNotes\nAma\tGave 500, cash');
      expect(g[1], ['Ama', 'Gave 500, cash']);
    });

    test('falls back to CSV when there are no tabs', () {
      final g = parsePastedGrid('Date,Name\n2026-03-04,Ama');
      expect(g[1], ['2026-03-04', 'Ama']);
    });

    test('a single column with no delimiters still yields rows', () {
      final g = parsePastedGrid('Ama\nKweku\nEfua');
      expect(g.length, 3);
      expect(g[2].first, 'Efua');
    });
  });

  test('isCsvFileName accepts csv and txt only', () {
    expect(isCsvFileName('entries.csv'), isTrue);
    expect(isCsvFileName('ENTRIES.CSV'), isTrue);
    expect(isCsvFileName('export.txt'), isTrue);
    expect(isCsvFileName('PARTNERSHIP SAMPLE.xlsx'), isFalse);
  });
}
