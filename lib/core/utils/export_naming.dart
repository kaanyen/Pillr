/// One naming format for every file Pillr hands to a person.
///
/// The build doc (§11) settled on `pillr_records_[period-name]_[date].pdf`,
/// and then nothing used it: exports arrived as `pillr-entries.pdf` whatever
/// they contained, so a folder of them told you nothing about which was which.
///
/// The shape is `pillr_[report]_[scope]_[date].[ext]`, each part kebab-cased
/// and the parts joined by underscores — so the eye can find the boundaries
/// and a sort by name groups every Pillr export together.
///
///   pillr_records_q3-2026-partnership_2026-08-23.pdf
///   pillr_queue_pending_2026-08-23.csv
///   pillr_import-template_demo-community-church.csv
library;

/// Lower-cased, punctuation collapsed to single hyphens, trimmed.
String exportSlug(String? value, {String fallback = ''}) {
  final slug = (value ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? fallback : slug;
}

/// Builds an export filename. [scope] and [on] are both optional: a report
/// that covers everything has no scope, and a blank template has no date.
String pillrExportFileName({
  required String report,
  required String extension,
  String? scope,
  DateTime? on,
}) {
  final parts = <String>[
    'pillr',
    exportSlug(report, fallback: 'export'),
    if (exportSlug(scope).isNotEmpty) exportSlug(scope),
    if (on != null) _isoDate(on),
  ];
  return '${parts.join('_')}.$extension';
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
