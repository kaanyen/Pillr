import '../../arms/domain/partnership_arm.dart';

/// The columns the importer understands, in the order the template writes
/// them. Kept beside the template so the two never drift.
const templateHeaders = <String>[
  'DATE',
  'NAME',
  'CONTACT',
  'FELLOWSHIP',
  'EMAIL',
  'AMOUNT',
  'CATEGORY',
  'NOTES',
  'PASTOR CONFIRMED',
];

String _csvCell(String v) {
  final needsQuotes =
      v.contains(',') || v.contains('"') || v.contains('\n') || v.contains('\r');
  final escaped = v.replaceAll('"', '""');
  return needsQuotes ? '"$escaped"' : escaped;
}

String _csvRow(List<String> cells) => cells.map(_csvCell).join(',');

/// Builds a starter spreadsheet for a specific church.
///
/// The point is to remove guesswork before it happens, so the template is not
/// generic: it lists **this church's** actual partnership arms in a reference
/// block, because "CATEGORY" is the column that fails most often and the
/// person filling it in has no other way to know what the app will accept.
///
/// Emitted as CSV rather than .xlsx — every spreadsheet program opens it, it
/// needs no zip container, and the importer accepts it back directly.
String buildImportTemplateCsv({
  required List<PartnershipArm> arms,
  DateTime? exampleDate,
}) {
  final active = arms.where((a) => a.isActive).toList();
  final date = exampleDate ?? DateTime.now();
  final iso = '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
  final exampleArm = active.isNotEmpty ? active.first.name : 'Missions';

  final lines = <String>[
    _csvRow(templateHeaders),
    _csvRow([
      iso,
      'Ama Boateng',
      '0244000000',
      'Grace Fellowship',
      'ama@example.com',
      '500',
      exampleArm,
      'Example row — delete before importing',
      'NO',
    ]),
    '',
    _csvRow(['# Notes']),
    _csvRow(['# DATE must be year-month-day, e.g. $iso']),
    _csvRow(['# AMOUNT is a plain number. No currency symbol.']),
    _csvRow(['# PASTOR CONFIRMED is YES or NO.']),
    _csvRow(['# The active giving period is applied to every row.']),
    '',
    _csvRow(['# CATEGORY must be one of your partnership arms:']),
    if (active.isEmpty)
      _csvRow(['# (none configured yet — add arms under Configuration)'])
    else
      for (final a in active) _csvRow(['# ${a.name}']),
  ];

  return '${lines.join('\n')}\n';
}

/// Filename for the generated template.
String importTemplateFileName(String? churchName) {
  final slug = (churchName ?? 'pillr')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return '${slug.isEmpty ? 'pillr' : slug}-import-template.csv';
}
