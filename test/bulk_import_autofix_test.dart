import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_autofix.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_columns.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_models.dart';

BulkRawRow row(int n, Map<BulkImportColumn, String> v) =>
    BulkRawRow(sheetRowNumber: n, valuesByColumn: v);

void main() {
  group('fixNameCasing', () {
    test('title-cases and collapses whitespace', () {
      expect(fixNameCasing('marian gasinu'), 'Marian Gasinu');
      expect(fixNameCasing('ELIKPLIM  BARRIGAH'), 'Elikplim Barrigah');
      expect(fixNameCasing('  Kweku Attah  '), 'Kweku Attah');
    });
    test('leaves an already-correct name alone', () {
      expect(fixNameCasing('Ama Boateng'), isNull);
    });
  });

  group('fixAmount', () {
    test('strips currency, spaces and separators', () {
      expect(fixAmount('GHS 1,000'), '1000');
      expect(fixAmount('₵500'), '500');
      expect(fixAmount(r'$1 200.50'), '1200.5');
    });
    test('leaves a clean number alone', () {
      expect(fixAmount('500'), isNull);
      expect(fixAmount('1200.50'), isNull);
    });
    test('refuses nonsense rather than inventing a number', () {
      expect(fixAmount('abc'), isNull);
      expect(fixAmount('-'), isNull);
      expect(fixAmount('0'), isNull);
    });
  });

  group('fixDate', () {
    test('day-first and month-first read 4/3/2026 differently', () {
      expect(fixDate('4/3/2026', dayFirst: true), '2026-03-04');
      expect(fixDate('4/3/2026', dayFirst: false), '2026-04-03');
    });

    test('an impossible month resolves the ambiguity by itself', () {
      // 25 cannot be a month either way, so this is 25 March regardless.
      expect(fixDate('25/3/2026', dayFirst: false), '2026-03-25');
    });

    test('leaves ISO alone', () {
      expect(fixDate('2026-03-04', dayFirst: true), isNull);
    });

    test('reads a four-digit leading year as y-m-d', () {
      expect(fixDate('2026/3/4', dayFirst: true), '2026-03-04');
    });

    test('reads named months', () {
      expect(fixDate('04-Mar-26', dayFirst: true), '2026-03-04');
      expect(fixDate('4 March 2026', dayFirst: true), '2026-03-04');
    });

    test('reads an Excel serial', () {
      // 46085 = 2026-03-04
      expect(fixDate('46085', dayFirst: true), '2026-03-04');
    });

    test('rejects an impossible date rather than rolling it over', () {
      // 31 February must not silently become 3 March.
      expect(fixDate('31/2/2026', dayFirst: true), isNull);
    });

    test('two-digit years land this century', () {
      expect(fixDate('4/3/26', dayFirst: true), '2026-03-04');
    });
  });

  group('fixPhone', () {
    test('reduces spaced and prefixed numbers to one form', () {
      expect(fixPhone('024 400 0000'), '0244000000');
      expect(fixPhone('+233244000000'), '0244000000');
      expect(fixPhone('233244000000'), '0244000000');
    });
    test('leaves an already-clean number alone', () {
      expect(fixPhone('0244000000'), isNull);
    });
    test('ignores something too short to be a number', () {
      expect(fixPhone('12'), isNull);
    });
  });

  group('detectAutoFixes', () {
    final rows = [
      row(2, {
        BulkImportColumn.name: 'marian gasinu',
        BulkImportColumn.amount: 'GHS 1,000',
        BulkImportColumn.date: '4/3/2026',
        BulkImportColumn.contact: '024 400 0000',
      }),
      row(3, {
        BulkImportColumn.name: 'Ama Boateng',
        BulkImportColumn.amount: '500',
        BulkImportColumn.date: '2026-03-05',
      }),
    ];

    test('groups only the cells that would actually change', () {
      final groups = detectAutoFixes(rows, dayFirst: true);
      expect(groups.map((g) => g.kind), containsAll([
        AutoFixKind.amount, AutoFixKind.date,
        AutoFixKind.nameCasing, AutoFixKind.phone,
      ]));
      // Row 3 is already clean, so every group holds exactly one proposal.
      for (final g in groups) {
        expect(g.count, 1, reason: '${g.kind} should skip the clean row');
      }
    });

    test('puts blocking problems before cosmetic ones', () {
      final groups = detectAutoFixes(rows, dayFirst: true);
      expect(groups.first.kind, AutoFixKind.amount);
      expect(groups.last.kind, AutoFixKind.phone);
    });
  });

  group('applyAutoFixes', () {
    test('writes the corrected values', () {
      final rows = [row(2, {BulkImportColumn.name: 'marian gasinu'})];
      final groups = detectAutoFixes(rows, dayFirst: true);
      final out = applyAutoFixes(rows, groups.first.proposals);
      expect(out.first.valuesByColumn[BulkImportColumn.name], 'Marian Gasinu');
    });

    test('a stale proposal cannot overwrite a manual edit', () {
      final rows = [row(2, {BulkImportColumn.name: 'marian gasinu'})];
      final groups = detectAutoFixes(rows, dayFirst: true);
      // The user edits the cell before applying the suggestion.
      final edited = [row(2, {BulkImportColumn.name: 'Marian G. Gasinu'})];
      final out = applyAutoFixes(edited, groups.first.proposals);
      expect(out.first.valuesByColumn[BulkImportColumn.name], 'Marian G. Gasinu');
    });

    test('leaves other rows untouched', () {
      final rows = [
        row(2, {BulkImportColumn.name: 'marian gasinu'}),
        row(3, {BulkImportColumn.name: 'Ama Boateng'}),
      ];
      final groups = detectAutoFixes(rows, dayFirst: true);
      final out = applyAutoFixes(rows, groups.first.proposals);
      expect(out[1].valuesByColumn[BulkImportColumn.name], 'Ama Boateng');
    });
  });
}
