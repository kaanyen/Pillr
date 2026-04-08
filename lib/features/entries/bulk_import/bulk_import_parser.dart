import 'dart:typed_data';

import 'package:intl/intl.dart';

import 'bulk_import_columns.dart';
import 'bulk_import_models.dart';
import 'xlsx_sheet_reader.dart';

export 'xlsx_sheet_reader.dart' show readFirstXlsxSheet;

/// Parses the first worksheet bytes into [BulkRawRow] list plus structural issues.
({List<BulkRawRow> rows, List<BulkImportIssue> fileIssues}) parseBulkImportWorkbook(
  List<int> bytes,
) {
  final grid = readFirstXlsxSheet(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
  return parseBulkImportGrid(grid);
}

({List<BulkRawRow> rows, List<BulkImportIssue> fileIssues}) parseBulkImportGrid(
  List<List<String?>> grid,
) {
  final fileIssues = <BulkImportIssue>[];
  if (grid.isEmpty) {
    fileIssues.add(
      const BulkImportIssue(
        code: BulkImportIssueCode.missingArm,
        severity: BulkImportSeverity.error,
        message: 'The spreadsheet is empty.',
      ),
    );
    return (rows: [], fileIssues: fileIssues);
  }

  final headerInfo = _findHeaderRow(grid);
  if (headerInfo == null) {
    fileIssues.add(
      const BulkImportIssue(
        code: BulkImportIssueCode.missingDate,
        severity: BulkImportSeverity.error,
        message: 'Could not find a header row (need columns like Date and Name).',
      ),
    );
    return (rows: [], fileIssues: fileIssues);
  }

  final (headerRowIndex, colMap) = headerInfo;
  if (!colMap.containsKey(BulkImportColumn.date) || !colMap.containsKey(BulkImportColumn.name)) {
    fileIssues.add(
      const BulkImportIssue(
        code: BulkImportIssueCode.missingDate,
        severity: BulkImportSeverity.error,
        message: 'Headers must include Date and Name.',
      ),
    );
  }

  final rows = <BulkRawRow>[];
  for (var r = headerRowIndex + 1; r < grid.length; r++) {
    final line = grid[r];
    final values = <BulkImportColumn, String>{};
    for (final e in colMap.entries) {
      final col = e.value;
      if (col >= line.length) continue;
      final cell = line[col]?.trim();
      if (cell != null && cell.isNotEmpty) {
        values[e.key] = cell;
      }
    }
    if (values.isEmpty) continue;

    rows.add(
      BulkRawRow(
        sheetRowNumber: r + 1,
        valuesByColumn: values,
      ),
    );
  }

  return (rows: rows, fileIssues: fileIssues);
}

/// Returns header row index and map column enum -> column index.
(int, Map<BulkImportColumn, int>)? _findHeaderRow(List<List<String?>> grid) {
  final maxScan = grid.length < 80 ? grid.length : 80;
  for (var r = 0; r < maxScan; r++) {
    final row = grid[r];
    final colMap = <BulkImportColumn, int>{};
    for (var c = 0; c < row.length; c++) {
      final key = normalizeHeaderKey(row[c]);
      if (key.isEmpty) continue;
      final col = columnForHeader(key);
      if (col != null) {
        colMap[col] = c;
      }
    }
    if (colMap.containsKey(BulkImportColumn.date) && colMap.containsKey(BulkImportColumn.name)) {
      return (r, colMap);
    }
  }
  return null;
}

/// Validates a raw row and returns field-level issues (does not resolve partners).
({double? amount, DateTime? date, bool pastorYes, List<BulkImportIssue> issues}) interpretRawValues(
  BulkRawRow row,
) {
  final issues = <BulkImportIssue>[];
  final v = row.valuesByColumn;

  final name = v[BulkImportColumn.name]?.trim() ?? '';
  if (name.isEmpty) {
    issues.add(
      const BulkImportIssue(
        code: BulkImportIssueCode.missingName,
        severity: BulkImportSeverity.error,
      ),
    );
  }

  final fellowship = v[BulkImportColumn.fellowship]?.trim() ?? '';
  if (fellowship.isEmpty) {
    issues.add(
      const BulkImportIssue(
        code: BulkImportIssueCode.missingFellowship,
        severity: BulkImportSeverity.error,
      ),
    );
  }

  final amountStr = v[BulkImportColumn.amount]?.trim() ?? '';
  double? amount;
  if (amountStr.isEmpty) {
    issues.add(
      const BulkImportIssue(
        code: BulkImportIssueCode.missingAmount,
        severity: BulkImportSeverity.error,
      ),
    );
  } else {
    final cleaned = amountStr.replaceAll(',', '');
    amount = double.tryParse(cleaned);
    if (amount == null || amount <= 0) {
      issues.add(
        const BulkImportIssue(
          code: BulkImportIssueCode.invalidAmount,
          severity: BulkImportSeverity.error,
        ),
      );
      amount = null;
    }
  }

  final dateStr = v[BulkImportColumn.date]?.trim() ?? '';
  DateTime? date;
  if (dateStr.isEmpty) {
    issues.add(
      const BulkImportIssue(
        code: BulkImportIssueCode.missingDate,
        severity: BulkImportSeverity.error,
      ),
    );
  } else {
    date = _parseFlexibleDate(dateStr);
    if (date == null) {
      issues.add(
        const BulkImportIssue(
          code: BulkImportIssueCode.invalidDate,
          severity: BulkImportSeverity.error,
        ),
      );
    }
  }

  final armStr = v[BulkImportColumn.category]?.trim() ?? '';
  if (armStr.isEmpty) {
    issues.add(
      const BulkImportIssue(
        code: BulkImportIssueCode.missingArm,
        severity: BulkImportSeverity.error,
      ),
    );
  }

  final pc = _parsePastorConfirmed(v[BulkImportColumn.pastorConfirmed]);

  return (amount: amount, date: date, pastorYes: pc, issues: issues);
}

bool _parsePastorConfirmed(String? raw) {
  if (raw == null || raw.trim().isEmpty) return false;
  final s = raw.trim().toLowerCase();
  return s == 'yes' || s == 'y' || s == 'true' || s == '1';
}

DateTime? _parseFlexibleDate(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;

  final iso = DateTime.tryParse(t);
  if (iso != null) return DateTime(iso.year, iso.month, iso.day);

  for (final pattern in ['d/M/y', 'dd/MM/yyyy', 'M/d/y', 'MM/dd/yyyy']) {
    try {
      final f = DateFormat(pattern);
      return f.parseStrict(t);
    } catch (_) {}
  }

  final n = num.tryParse(t);
  if (n != null) {
    final d = n.toDouble();
    if (d == d.roundToDouble() && d >= 20000 && d <= 80000) {
      return DateTime(1899, 12, 30).add(Duration(days: d.round()));
    }
  }

  return null;
}
