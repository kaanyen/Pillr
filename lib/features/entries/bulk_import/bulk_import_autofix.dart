import '../../../core/utils/text_case_utils.dart';
import 'bulk_import_columns.dart';
import 'bulk_import_mapping.dart';
import 'bulk_import_models.dart';

/// A class of correction the importer can make on its own.
enum AutoFixKind {
  /// 'marian gasinu' → 'Marian Gasinu', doubled spaces collapsed.
  nameCasing,

  /// 'GHS 1,000' → '1000'.
  amount,

  /// '4/3/2026' → '2026-03-04'.
  date,

  /// '024 400 0000' → '0244000000'.
  phone,
}

extension AutoFixKindLabel on AutoFixKind {
  String get label => switch (this) {
        AutoFixKind.nameCasing => 'Name formatting',
        AutoFixKind.amount => 'Amount formatting',
        AutoFixKind.date => 'Date formatting',
        AutoFixKind.phone => 'Phone formatting',
      };

  BulkImportColumn get column => switch (this) {
        AutoFixKind.nameCasing => BulkImportColumn.name,
        AutoFixKind.amount => BulkImportColumn.amount,
        AutoFixKind.date => BulkImportColumn.date,
        AutoFixKind.phone => BulkImportColumn.contact,
      };
}

/// One proposed change to one cell.
class AutoFixProposal {
  const AutoFixProposal({
    required this.rowIndex,
    required this.sheetRow,
    required this.column,
    required this.before,
    required this.after,
  });

  /// Index into the working row list — what actually gets patched.
  final int rowIndex;

  /// 1-based spreadsheet row, for display.
  final int sheetRow;

  final BulkImportColumn column;
  final String before;
  final String after;
}

/// All the proposals of one kind, ready to preview and apply together.
class AutoFixGroup {
  const AutoFixGroup({required this.kind, required this.proposals});

  final AutoFixKind kind;
  final List<AutoFixProposal> proposals;

  int get count => proposals.length;
  String get label => kind.label;
}

// ---------------------------------------------------------------------------
// Individual rules. Each returns null when the value is already fine, so a
// proposal is only ever produced for a cell that would actually change.
// ---------------------------------------------------------------------------

/// Title-cases a name and collapses stray whitespace.
String? fixNameCasing(String raw) {
  final fixed = TextCaseUtils.toTitleCase(raw);
  if (fixed.isEmpty || fixed == raw) return null;
  return fixed;
}

/// Strips currency symbols, spaces and thousands separators from an amount.
///
/// Returns null when the value already parses, so a clean '500' is left alone,
/// and null when the result is not a number, so nonsense is surfaced as an
/// error rather than silently rewritten.
String? fixAmount(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  if (double.tryParse(trimmed) != null) return null;

  var s = trimmed
      .replaceAll(RegExp(r'[A-Za-z₵€£$\s]'), '')
      .replaceAll(',', '');
  // A trailing '.00' is fine; a lone trailing '.' is not.
  s = s.replaceAll(RegExp(r'\.$'), '');
  if (s.isEmpty) return null;

  final value = double.tryParse(s);
  if (value == null || value <= 0) return null;
  // Emit a plain number; the parser reads it back with double.tryParse.
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();
}

/// Normalises a date to `YYYY-MM-DD`.
///
/// [dayFirst] decides `4/3/2026`: day-first reads 4 March, month-first reads
/// 3 April. There is no way to tell from the value alone, and guessing wrong
/// silently misdates money — so this is a setting the user confirms, not an
/// inference.
String? fixDate(String raw, {required bool dayFirst}) {
  final s = raw.trim();
  if (s.isEmpty) return null;

  // Already ISO.
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return null;

  String two(int v) => v.toString().padLeft(2, '0');

  // Excel serial: days since 1899-12-30.
  final serial = int.tryParse(s);
  if (serial != null && serial > 20000 && serial < 60000) {
    final d = DateTime(1899, 12, 30).add(Duration(days: serial));
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  // d/m/y, m/d/y, d-m-y, d.m.y
  final numeric = RegExp(r'^(\d{1,4})[/\-.](\d{1,2})[/\-.](\d{1,4})$').firstMatch(s);
  if (numeric != null) {
    final a = int.parse(numeric.group(1)!);
    final b = int.parse(numeric.group(2)!);
    final c = int.parse(numeric.group(3)!);

    // Leading 4-digit value is a year: y-m-d.
    if (a > 31) {
      final d = DateTime(a, b, c);
      return '${d.year}-${two(d.month)}-${two(d.day)}';
    }

    var day = dayFirst ? a : b;
    var month = dayFirst ? b : a;
    // If one value cannot be a month, the ambiguity resolves itself.
    if (month > 12 && day <= 12) {
      final t = day;
      day = month;
      month = t;
    }
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final year = c < 100 ? 2000 + c : c;
    final d = DateTime(year, month, day);
    // Reject impossible dates like 31 February rather than rolling them over.
    if (d.month != month || d.day != day) return null;
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  // 04-Mar-26, 4 March 2026
  const months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };
  final named = RegExp(r'^(\d{1,2})[\s\-]+([A-Za-z]{3,})[\s\-]+(\d{2,4})$')
      .firstMatch(s);
  if (named != null) {
    final day = int.parse(named.group(1)!);
    final month = months[named.group(2)!.toLowerCase().substring(0, 3)];
    if (month == null) return null;
    final yRaw = int.parse(named.group(3)!);
    final year = yRaw < 100 ? 2000 + yRaw : yRaw;
    final d = DateTime(year, month, day);
    if (d.month != month || d.day != day) return null;
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  return null;
}

/// Reduces a phone number to digits, so the same person typed three ways is
/// recognised as one partner rather than three.
String? fixPhone(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  var digits = s.replaceAll(RegExp(r'[^\d+]'), '');
  // +233 24 400 0000 → 0244000000
  if (digits.startsWith('+233')) {
    digits = '0${digits.substring(4)}';
  } else if (digits.startsWith('233') && digits.length > 10) {
    digits = '0${digits.substring(3)}';
  }
  digits = digits.replaceAll('+', '');
  if (digits.isEmpty || digits == s) return null;
  if (digits.length < 7) return null;
  return digits;
}

// ---------------------------------------------------------------------------

/// Scans rows and returns every correction that could be made, grouped.
///
/// Nothing is applied here — the caller previews the groups and chooses.
List<AutoFixGroup> detectAutoFixes(
  List<BulkRawRow> rows, {
  required bool dayFirst,
}) {
  final byKind = <AutoFixKind, List<AutoFixProposal>>{};

  void consider(
    AutoFixKind kind,
    int rowIndex,
    BulkRawRow row,
    String? Function(String) rule,
  ) {
    final before = row.valuesByColumn[kind.column];
    if (before == null || before.trim().isEmpty) return;
    final after = rule(before);
    if (after == null || after == before) return;
    byKind.putIfAbsent(kind, () => []).add(
          AutoFixProposal(
            rowIndex: rowIndex,
            sheetRow: row.sheetRowNumber,
            column: kind.column,
            before: before,
            after: after,
          ),
        );
  }

  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    consider(AutoFixKind.nameCasing, i, row, fixNameCasing);
    consider(AutoFixKind.amount, i, row, fixAmount);
    consider(AutoFixKind.date, i, row, (v) => fixDate(v, dayFirst: dayFirst));
    consider(AutoFixKind.phone, i, row, fixPhone);
  }

  // Errors before cosmetics: a bad amount blocks the import, a lowercase name
  // does not.
  const order = [
    AutoFixKind.amount,
    AutoFixKind.date,
    AutoFixKind.nameCasing,
    AutoFixKind.phone,
  ];
  return [
    for (final k in order)
      if (byKind[k]?.isNotEmpty ?? false)
        AutoFixGroup(kind: k, proposals: byKind[k]!),
  ];
}

/// Returns a new row list with [proposals] applied.
List<BulkRawRow> applyAutoFixes(
  List<BulkRawRow> rows,
  List<AutoFixProposal> proposals,
) {
  final out = List<BulkRawRow>.from(rows);
  for (final p in proposals) {
    if (p.rowIndex < 0 || p.rowIndex >= out.length) continue;
    final values = Map<BulkImportColumn, String>.from(
      out[p.rowIndex].valuesByColumn,
    );
    // Only apply if the cell still holds what the proposal was based on, so a
    // stale proposal cannot overwrite a manual edit.
    if (values[p.column] != p.before) continue;
    values[p.column] = p.after;
    out[p.rowIndex] = BulkRawRow(
      sheetRowNumber: out[p.rowIndex].sheetRowNumber,
      valuesByColumn: values,
    );
  }
  return out;
}

/// Label for a field, reused by the issues panel.
String autoFixFieldLabel(BulkImportColumn c) => bulkImportFieldLabel(c);
