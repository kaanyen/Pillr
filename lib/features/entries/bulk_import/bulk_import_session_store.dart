import 'dart:convert';
import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';

import 'bulk_import_columns.dart';
import 'bulk_import_models.dart';

const _boxName = 'pillr_bulk_import_sessions';

/// Disk-backed bulk import draft (survives navigation and idle sign-out).
abstract final class BulkImportSessionStore {
  static Future<Box<String>> _box() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox<String>(_boxName);
    }
    return Hive.box<String>(_boxName);
  }

  static String _key(String uid, String churchId) => '$uid|$churchId';

  static Future<void> save({
    required String uid,
    required String churchId,
    required String? fileName,
    required Uint8List? fileBytes,
    required List<BulkRawRow> rawRows,
    required List<BulkImportIssue> fileIssues,
    required Set<int> duplicateAcknowledgedSheetRows,
    required Map<BulkImportColumn, int> mapping,
  }) async {
    final box = await _box();
    if (rawRows.isEmpty && fileBytes == null) {
      await box.delete(_key(uid, churchId));
      return;
    }
    final payload = <String, dynamic>{
      'fileName': fileName,
      'fileBytes': fileBytes != null ? base64Encode(fileBytes) : null,
      'rawRows': rawRows.map(_rawRowToJson).toList(),
      'fileIssues': fileIssues.map(_issueToJson).toList(),
      'duplicateAcknowledged': duplicateAcknowledgedSheetRows.toList(),
      'mapping': mapping.map((k, v) => MapEntry(k.name, v)),
      'savedAt': DateTime.now().toIso8601String(),
    };
    await box.put(_key(uid, churchId), jsonEncode(payload));
  }

  static Future<BulkImportPersistedSession?> load({
    required String uid,
    required String churchId,
  }) async {
    final box = await _box();
    final raw = box.get(_key(uid, churchId));
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final bytesB64 = m['fileBytes'] as String?;
      return BulkImportPersistedSession(
        fileName: m['fileName'] as String?,
        fileBytes: bytesB64 != null ? base64Decode(bytesB64) : null,
        rawRows: (m['rawRows'] as List<dynamic>)
            .map((e) => _rawRowFromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        fileIssues: (m['fileIssues'] as List<dynamic>? ?? [])
            .map((e) => _issueFromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        duplicateAcknowledgedSheetRows: (m['duplicateAcknowledged'] as List<dynamic>? ?? [])
            .map((e) => (e as num).toInt())
            .toSet(),
        mapping: {
          for (final e in (m['mapping'] as Map<String, dynamic>? ?? {}).entries)
            BulkImportColumn.values.byName(e.key): (e.value as num).toInt(),
        },
        savedAt: DateTime.tryParse(m['savedAt'] as String? ?? ''),
      );
    } catch (_) {
      await box.delete(_key(uid, churchId));
      return null;
    }
  }

  static Future<void> clear({
    required String uid,
    required String churchId,
  }) async {
    final box = await _box();
    await box.delete(_key(uid, churchId));
  }

  static Map<String, dynamic> _rawRowToJson(BulkRawRow r) => {
        'sheetRowNumber': r.sheetRowNumber,
        'values': r.valuesByColumn.map((k, v) => MapEntry(k.name, v)),
      };

  static BulkRawRow _rawRowFromJson(Map<String, dynamic> m) {
    final values = <BulkImportColumn, String>{};
    final rawValues = m['values'] as Map<String, dynamic>? ?? {};
    for (final e in rawValues.entries) {
      final col = BulkImportColumn.values.byName(e.key);
      values[col] = e.value.toString();
    }
    return BulkRawRow(
      sheetRowNumber: (m['sheetRowNumber'] as num).toInt(),
      valuesByColumn: values,
    );
  }

  static Map<String, dynamic> _issueToJson(BulkImportIssue i) => {
        'code': i.code.name,
        'severity': i.severity.name,
        'message': i.message,
      };

  static BulkImportIssue _issueFromJson(Map<String, dynamic> m) => BulkImportIssue(
        code: BulkImportIssueCode.values.byName(m['code'] as String),
        severity: BulkImportSeverity.values.byName(m['severity'] as String),
        message: m['message'] as String?,
      );
}

class BulkImportPersistedSession {
  const BulkImportPersistedSession({
    this.fileName,
    this.fileBytes,
    required this.rawRows,
    required this.fileIssues,
    required this.duplicateAcknowledgedSheetRows,
    required this.mapping,
    this.savedAt,
  });

  final String? fileName;
  final Uint8List? fileBytes;
  final List<BulkRawRow> rawRows;
  final List<BulkImportIssue> fileIssues;
  final Set<int> duplicateAcknowledgedSheetRows;

  /// Which sheet column each field came from, so a resumed draft reads in the
  /// same order as the file it started as.
  final Map<BulkImportColumn, int> mapping;

  final DateTime? savedAt;
}
