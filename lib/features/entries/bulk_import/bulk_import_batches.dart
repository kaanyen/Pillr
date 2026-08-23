import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/domain/church_user.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../auth/providers/auth_providers.dart';

/// One run of the importer: which file, how many rows, and what became of it.
///
/// Without this an import left no trace of itself. Sixty-seven entries would
/// appear among eight hundred with nothing to say they arrived together, so a
/// file imported against the wrong period could be neither found nor undone.
class BulkImportBatch {
  const BulkImportBatch({
    required this.id,
    required this.fileName,
    required this.entryCount,
    required this.partnersCreated,
    required this.totalCedis,
    required this.createdByName,
    required this.createdAt,
    required this.periodName,
    this.undoneAt,
    this.removedCount = 0,
    this.keptCount = 0,
  });

  factory BulkImportBatch.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    return BulkImportBatch(
      id: d.id,
      fileName: (m['fileName'] ?? '') as String,
      entryCount: (m['entryCount'] ?? 0) as int,
      partnersCreated: (m['partnersCreated'] ?? 0) as int,
      totalCedis: ((m['totalCedis'] ?? 0) as num).toDouble(),
      createdByName: (m['createdByName'] ?? '') as String,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      periodName: (m['periodName'] ?? '') as String,
      undoneAt: (m['undoneAt'] as Timestamp?)?.toDate(),
      removedCount: (m['removedCount'] ?? 0) as int,
      keptCount: (m['keptCount'] ?? 0) as int,
    );
  }

  final String id;
  final String fileName;
  final int entryCount;
  final int partnersCreated;
  final double totalCedis;
  final String createdByName;
  final DateTime createdAt;
  final String periodName;
  final DateTime? undoneAt;
  final int removedCount;
  final int keptCount;

  bool get isUndone => undoneAt != null;
}

/// What an undo actually did. Approved entries are money the church has
/// already counted, so they are left alone and reported rather than removed.
class BulkImportUndoResult {
  const BulkImportUndoResult({required this.removed, required this.kept});

  final int removed;
  final int kept;
}

class BulkImportBatchRepository {
  BulkImportBatchRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _batches(String churchId) =>
      _firestore
          .collection('churches')
          .doc(churchId)
          .collection('import_batches');

  CollectionReference<Map<String, dynamic>> _entries(String churchId) =>
      _firestore.collection('churches').doc(churchId).collection('entries');

  /// Claims an id before the import runs, so every entry can carry it.
  String newBatchId(String churchId) => _batches(churchId).doc().id;

  Future<void> record({
    required String churchId,
    required String batchId,
    required String fileName,
    required String periodName,
    required int entryCount,
    required int partnersCreated,
    required double totalCedis,
    required ChurchUser staff,
  }) async {
    await _batches(churchId).doc(batchId).set({
      'id': batchId,
      'churchId': churchId,
      'fileName': fileName,
      'periodName': periodName,
      'entryCount': entryCount,
      'partnersCreated': partnersCreated,
      'totalCedis': totalCedis,
      'createdBy': staff.uid,
      'createdByName': staff.fullName,
      'createdAt': FieldValue.serverTimestamp(),
      'undoneAt': null,
      'removedCount': 0,
      'keptCount': 0,
    });
  }

  Stream<List<BulkImportBatch>> watchRecent(String churchId, {int limit = 5}) {
    return _batches(churchId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(BulkImportBatch.fromDoc).toList());
  }

  /// Removes the entries this import created that nobody has acted on yet.
  ///
  /// Only pending rows go: an approved entry has already moved partner and
  /// period totals and may have been receipted, and quietly deleting it is not
  /// an undo but a second mistake. Those are counted and reported instead.
  Future<BulkImportUndoResult> undo({
    required String churchId,
    required String batchId,
    required String byUid,
  }) async {
    final all = await _entries(
      churchId,
    ).where('importBatchId', isEqualTo: batchId).get();

    final removable = all.docs
        .where((d) => (d.data()['status'] ?? '') == 'pending')
        .toList();
    final kept = all.docs.length - removable.length;

    // Firestore caps a batch at 500 writes.
    for (var i = 0; i < removable.length; i += 400) {
      final batch = _firestore.batch();
      for (final d in removable.skip(i).take(400)) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }

    await _batches(churchId).doc(batchId).set({
      'undoneAt': FieldValue.serverTimestamp(),
      'undoneBy': byUid,
      'removedCount': removable.length,
      'keptCount': kept,
    }, SetOptions(merge: true));

    return BulkImportUndoResult(removed: removable.length, kept: kept);
  }
}

final bulkImportBatchRepositoryProvider = Provider<BulkImportBatchRepository>(
  (ref) => BulkImportBatchRepository(FirebaseFirestore.instance),
);

/// The last few imports for this church, newest first.
final recentImportBatchesProvider =
    StreamProvider.autoDispose<List<BulkImportBatch>>((ref) {
      final idx = ref.watch(userChurchIndexProvider).valueOrNull;
      if (idx == null) return Stream.value(const []);
      return ref
          .watch(bulkImportBatchRepositoryProvider)
          .watchRecent(idx.churchId);
    });
