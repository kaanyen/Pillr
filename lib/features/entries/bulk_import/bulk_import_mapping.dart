import 'bulk_import_columns.dart';
import 'bulk_import_models.dart';

/// What the importer could work out about a sheet's header row on its own.
///
/// Exposing this — rather than silently succeeding or silently failing — is
/// the point. Previously a header the app did not recognise was simply
/// dropped, so a sheet whose amount column said "Amount Given" produced forty
/// rows with no amount and no explanation of why.
class BulkImportHeaderDetection {
  const BulkImportHeaderDetection({
    required this.headerRowIndex,
    required this.labels,
    required this.mapping,
  });

  /// Row in the grid the headers were found on. `-1` when none was found.
  final int headerRowIndex;

  /// The header text of every column on that row, in sheet order. Blank
  /// entries are kept so indices line up with the grid.
  final List<String> labels;

  /// Best guess: field → column index. Only confident matches appear.
  final Map<BulkImportColumn, int> mapping;

  bool get found => headerRowIndex >= 0;

  /// Fields the importer cannot proceed without.
  static const required = <BulkImportColumn>[
    BulkImportColumn.date,
    BulkImportColumn.name,
    BulkImportColumn.amount,
  ];

  List<BulkImportColumn> get missingRequired =>
      required.where((c) => !mapping.containsKey(c)).toList();
}

/// Finds the most likely header row and guesses a mapping for it.
///
/// Deliberately more forgiving than the old detector, which required Date and
/// Name to both be recognised before it would accept a row as the header. That
/// meant an unrecognised header spelling did not just lose one column — it
/// lost the whole sheet. Here the best-scoring row wins and the user corrects
/// the rest.
BulkImportHeaderDetection detectBulkImportHeaders(List<List<String?>> grid) {
  var bestRow = -1;
  var bestScore = 0;
  var bestMap = <BulkImportColumn, int>{};

  final maxScan = grid.length < 80 ? grid.length : 80;
  for (var r = 0; r < maxScan; r++) {
    final row = grid[r];
    final map = <BulkImportColumn, int>{};
    for (var c = 0; c < row.length; c++) {
      final key = normalizeHeaderKey(row[c]);
      if (key.isEmpty) continue;
      final col = columnForHeader(key);
      // First header wins: a later duplicate is usually a second table.
      if (col != null && !map.containsKey(col)) map[col] = c;
    }
    // Prefer rows that identify more fields; break ties toward the earlier row.
    if (map.length > bestScore) {
      bestScore = map.length;
      bestRow = r;
      bestMap = map;
    }
  }

  // Nothing recognisable anywhere: fall back to the first non-empty row so the
  // user still gets a mapping screen instead of a dead end.
  if (bestRow < 0) {
    for (var r = 0; r < maxScan; r++) {
      if (grid[r].any((c) => (c ?? '').trim().isNotEmpty)) {
        bestRow = r;
        break;
      }
    }
  }
  if (bestRow < 0) {
    return const BulkImportHeaderDetection(
      headerRowIndex: -1,
      labels: [],
      mapping: {},
    );
  }

  final labels = grid[bestRow].map((c) => (c ?? '').trim()).toList();
  return BulkImportHeaderDetection(
    headerRowIndex: bestRow,
    labels: labels,
    mapping: bestMap,
  );
}

/// Builds rows using an explicit field → column mapping.
///
/// The mapping comes from the user via the Check columns step, so this does no
/// guessing of its own.
({List<BulkRawRow> rows, List<BulkImportIssue> fileIssues}) parseBulkImportGridWithMapping(
  List<List<String?>> grid, {
  required int headerRowIndex,
  required Map<BulkImportColumn, int> mapping,
}) {
  final fileIssues = <BulkImportIssue>[];

  if (grid.isEmpty || headerRowIndex < 0) {
    fileIssues.add(
      const BulkImportIssue(
        code: BulkImportIssueCode.missingName,
        severity: BulkImportSeverity.error,
        message: 'The spreadsheet is empty.',
      ),
    );
    return (rows: const [], fileIssues: fileIssues);
  }

  final rows = <BulkRawRow>[];
  for (var r = headerRowIndex + 1; r < grid.length; r++) {
    final line = grid[r];
    final values = <BulkImportColumn, String>{};
    for (final e in mapping.entries) {
      final col = e.value;
      if (col < 0 || col >= line.length) continue;
      final cell = line[col]?.trim();
      if (cell != null && cell.isNotEmpty) values[e.key] = cell;
    }
    if (values.isEmpty) continue;
    rows.add(BulkRawRow(sheetRowNumber: r + 1, valuesByColumn: values));
  }

  final ignored = <BulkRawRow>[];

  // A total line is not a gift. Every church sheet ends with one, and it
  // carries a very large amount, so importing it silently doubles the month.
  rows.removeWhere((row) {
    if (!_looksLikeTotalRow(row)) return false;
    ignored.add(row);
    return true;
  });

  // Notes typed under the table — "Prepared by Sis. Cindy". Only trailing
  // rows are considered: a row in the middle with no date and no amount is a
  // real row somebody left incomplete, and dropping it would hide the mistake.
  while (rows.isNotEmpty && _looksLikeTrailingNote(rows.last)) {
    ignored.add(rows.removeLast());
  }

  if (ignored.isNotEmpty) {
    ignored.sort((a, b) => a.sheetRowNumber.compareTo(b.sheetRowNumber));
    final numbers = ignored.map((r) => r.sheetRowNumber).join(', ');
    fileIssues.add(
      BulkImportIssue(
        code: BulkImportIssueCode.ignoredNonDataRow,
        severity: BulkImportSeverity.warning,
        message: ignored.length == 1
            ? 'Row $numbers looks like a total or a note rather than a gift, '
                  'so it was left out.'
            : 'Rows $numbers look like totals or notes rather than gifts, so '
                  'they were left out.',
      ),
    );
  }

  return (rows: rows, fileIssues: fileIssues);
}

const _totalWords = {
  'total',
  'totals',
  'grand total',
  'sub total',
  'subtotal',
  'sum',
  'overall total',
  'total amount',
};

String _norm(String? s) =>
    (s ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z ]'), '').trim().replaceAll(RegExp(r'\s+'), ' ');

/// A summary line: the name cell says TOTAL and none of the things that
/// identify a person are filled in.
bool _looksLikeTotalRow(BulkRawRow row) {
  final name = _norm(row.valuesByColumn[BulkImportColumn.name]);
  if (!_totalWords.contains(name)) return false;
  // Guard against a real partner whose row happens to be sparse: if there is
  // any way to identify a person, treat it as data.
  for (final c in const [
    BulkImportColumn.contact,
    BulkImportColumn.email,
    BulkImportColumn.fellowship,
    BulkImportColumn.memberId,
    BulkImportColumn.date,
  ]) {
    if ((row.valuesByColumn[c] ?? '').trim().isNotEmpty) return false;
  }
  return true;
}

/// A line with nothing that makes it a gift — no date, no amount, and nothing
/// that identifies a person. Only meaningful at the end of a sheet.
bool _looksLikeTrailingNote(BulkRawRow row) {
  for (final c in const [
    BulkImportColumn.date,
    BulkImportColumn.amount,
    BulkImportColumn.contact,
    BulkImportColumn.email,
    BulkImportColumn.memberId,
  ]) {
    if ((row.valuesByColumn[c] ?? '').trim().isNotEmpty) return false;
  }
  return true;
}

/// Human label for a field, used by the mapping UI.
String bulkImportFieldLabel(BulkImportColumn c) => switch (c) {
      BulkImportColumn.date => 'Date given',
      BulkImportColumn.name => 'Partner name',
      BulkImportColumn.memberId => 'Member ID',
      BulkImportColumn.contact => 'Phone',
      BulkImportColumn.fellowship => 'Fellowship',
      BulkImportColumn.email => 'Email',
      BulkImportColumn.amount => 'Amount',
      BulkImportColumn.category => 'Partnership arm',
      BulkImportColumn.givenToNotes => 'Notes',
      BulkImportColumn.pastorConfirmed => 'Pastor confirmed',
    };

/// Fields offered in the mapping step, required ones first.
const bulkImportMappableFields = <BulkImportColumn>[
  BulkImportColumn.date,
  BulkImportColumn.name,
  BulkImportColumn.amount,
  BulkImportColumn.category,
  BulkImportColumn.fellowship,
  BulkImportColumn.contact,
  BulkImportColumn.email,
  BulkImportColumn.memberId,
  BulkImportColumn.givenToNotes,
  BulkImportColumn.pastorConfirmed,
];
