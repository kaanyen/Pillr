import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/core/utils/export_naming.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_template.dart';

void main() {
  test('records exports name themselves after what they contain', () {
    expect(
      pillrExportFileName(
        report: 'Records',
        scope: 'Q3 2026 Partnership',
        on: DateTime(2026, 8, 23),
        extension: 'pdf',
      ),
      'pillr_records_q3-2026-partnership_2026-08-23.pdf',
    );
  });

  test('a report with no scope simply omits it', () {
    expect(
      pillrExportFileName(report: 'Queue', on: DateTime(2026, 1, 5), extension: 'csv'),
      'pillr_queue_2026-01-05.csv',
    );
  });

  test('punctuation and case collapse to one kebab part', () {
    expect(
      pillrExportFileName(
        report: 'Partner ranking',
        scope: "St. Peter's — Q1/2026",
        on: DateTime(2026, 12, 31),
        extension: 'pdf',
      ),
      'pillr_partner-ranking_st-peter-s-q1-2026_2026-12-31.pdf',
    );
  });

  test('the import template uses the same format', () {
    expect(
      importTemplateFileName('Demo Community Church'),
      'pillr_import-template_demo-community-church.csv',
    );
    expect(importTemplateFileName(null), 'pillr_import-template.csv');
  });
}
