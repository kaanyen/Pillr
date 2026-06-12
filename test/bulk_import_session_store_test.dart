import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_columns.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_models.dart';
import 'package:the_pillr/features/entries/bulk_import/bulk_import_session_store.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pillr_bulk_import_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    if (Hive.isBoxOpen('pillr_bulk_import_sessions')) {
      await Hive.box<String>('pillr_bulk_import_sessions').close();
    }
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  BulkRawRow sampleRow() => BulkRawRow(
        sheetRowNumber: 3,
        valuesByColumn: {
          BulkImportColumn.name: 'Jane Doe',
          BulkImportColumn.amount: '100',
        },
      );

  test('save and load round-trip preserves draft fields', () async {
    const uid = 'user-1';
    const churchId = 'church-1';
    final bytes = Uint8List.fromList([1, 2, 3, 4]);

    await BulkImportSessionStore.save(
      uid: uid,
      churchId: churchId,
      fileName: 'partners.xlsx',
      fileBytes: bytes,
      rawRows: [sampleRow()],
      fileIssues: const [
        BulkImportIssue(
          code: BulkImportIssueCode.missingDate,
          severity: BulkImportSeverity.warning,
          message: 'Row 3 missing date',
        ),
      ],
      duplicateAcknowledgedSheetRows: {3, 7},
    );

    final loaded = await BulkImportSessionStore.load(uid: uid, churchId: churchId);
    expect(loaded, isNotNull);
    expect(loaded!.fileName, 'partners.xlsx');
    expect(loaded.fileBytes, bytes);
    expect(loaded.rawRows.length, 1);
    expect(loaded.rawRows.single.sheetRowNumber, 3);
    expect(loaded.rawRows.single.valuesByColumn[BulkImportColumn.name], 'Jane Doe');
    expect(loaded.fileIssues.length, 1);
    expect(loaded.fileIssues.single.code, BulkImportIssueCode.missingDate);
    expect(loaded.duplicateAcknowledgedSheetRows, {3, 7});
  });

  test('clear removes saved draft', () async {
    const uid = 'user-2';
    const churchId = 'church-2';

    await BulkImportSessionStore.save(
      uid: uid,
      churchId: churchId,
      fileName: 'draft.xlsx',
      fileBytes: Uint8List.fromList([9]),
      rawRows: [sampleRow()],
      fileIssues: const [],
      duplicateAcknowledgedSheetRows: {},
    );

    await BulkImportSessionStore.clear(uid: uid, churchId: churchId);

    final loaded = await BulkImportSessionStore.load(uid: uid, churchId: churchId);
    expect(loaded, isNull);
  });

  test('corrupt payload returns null and deletes entry', () async {
    const uid = 'user-3';
    const churchId = 'church-3';
    const key = '$uid|$churchId';

    if (!Hive.isBoxOpen('pillr_bulk_import_sessions')) {
      await Hive.openBox<String>('pillr_bulk_import_sessions');
    }
    final box = Hive.box<String>('pillr_bulk_import_sessions');
    await box.put(key, '{not valid json');

    final loaded = await BulkImportSessionStore.load(uid: uid, churchId: churchId);
    expect(loaded, isNull);
    expect(box.get(key), isNull);
  });

  test('save with empty rows and no file deletes draft', () async {
    const uid = 'user-4';
    const churchId = 'church-4';

    await BulkImportSessionStore.save(
      uid: uid,
      churchId: churchId,
      fileName: 'old.xlsx',
      fileBytes: Uint8List.fromList([1]),
      rawRows: [sampleRow()],
      fileIssues: const [],
      duplicateAcknowledgedSheetRows: {},
    );

    await BulkImportSessionStore.save(
      uid: uid,
      churchId: churchId,
      fileName: null,
      fileBytes: null,
      rawRows: const [],
      fileIssues: const [],
      duplicateAcknowledgedSheetRows: {},
    );

    final loaded = await BulkImportSessionStore.load(uid: uid, churchId: churchId);
    expect(loaded, isNull);
  });
}
