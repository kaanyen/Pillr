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
    this.preparedBy,
    required this.periodName,
    this.undoneAt,
    this.removedCount = 0,
    this.keptCount = 0,
    this.label,
    this.note,
    this.voidedAt,
    this.voidedCount = 0,
    this.inProgress = false,
    this.skippedCount = 0,
    this.reassignedAt,
    this.previousPeriodName,
    this.restoredAt,
    this.previousLabel,
    this.previousNote,
    this.lastEditedAt,
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
      preparedBy: (m['preparedBy'] as String?)?.trim().isEmpty ?? true
          ? null
          : (m['preparedBy'] as String).trim(),
      periodName: (m['periodName'] ?? '') as String,
      undoneAt: (m['undoneAt'] as Timestamp?)?.toDate(),
      removedCount: (m['removedCount'] ?? 0) as int,
      keptCount: (m['keptCount'] ?? 0) as int,
      label: (m['label'] as String?)?.trim().isEmpty ?? true
          ? null
          : (m['label'] as String).trim(),
      note: (m['note'] as String?)?.trim().isEmpty ?? true
          ? null
          : (m['note'] as String).trim(),
      voidedAt: (m['voidedAt'] as Timestamp?)?.toDate(),
      voidedCount: (m['voidedCount'] ?? 0) as int,
      inProgress: m['inProgress'] == true,
      skippedCount: (m['skippedCount'] ?? 0) as int,
      reassignedAt: (m['reassignedAt'] as Timestamp?)?.toDate(),
      previousPeriodName: (m['previousPeriodName'] as String?)?.trim().isEmpty ??
              true
          ? null
          : (m['previousPeriodName'] as String).trim(),
      restoredAt: (m['restoredAt'] as Timestamp?)?.toDate(),
      previousLabel: (m['previousLabel'] as String?)?.trim().isEmpty ?? true
          ? null
          : (m['previousLabel'] as String).trim(),
      previousNote: (m['previousNote'] as String?)?.trim().isEmpty ?? true
          ? null
          : (m['previousNote'] as String).trim(),
      lastEditedAt: (m['lastEditedAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String fileName;
  final int entryCount;
  final int partnersCreated;
  final double totalCedis;
  /// Who uploaded the file — a Pillr user, taken from their profile.
  final String createdByName;
  final DateTime createdAt;

  /// Who put the sheet together, typed in at import time.
  ///
  /// Usually not the same person as the uploader and often not a Pillr user at
  /// all: a fellowship leader writes the list, someone in the office keys it
  /// in. When a figure is queried months later this is the name that answers
  /// "who do we ask about this?", so it is worth capturing even though nothing
  /// in the system can verify it.
  final String? preparedBy;
  final String periodName;
  final DateTime? undoneAt;
  final int removedCount;
  final int keptCount;

  /// What someone called this import. Falls back to the file name, which is
  /// what an import was identified by before it could be named.
  final String? label;
  final String? note;

  /// When the whole batch was reversed, and how many entries that touched.
  final DateTime? voidedAt;
  final int voidedCount;
  final bool inProgress;
  final int skippedCount;
  final DateTime? reassignedAt;
  final String? previousPeriodName;
  final DateTime? restoredAt;
  final String? previousLabel;
  final String? previousNote;
  final DateTime? lastEditedAt;

  bool get isUndone => undoneAt != null;
  bool get isVoided => voidedAt != null;
  bool get isIncomplete => inProgress;
  bool get canUndoMove => reassignedAt != null && previousPeriodName != null;
  bool get canUndoRename => previousLabel != null || previousNote != null;
  bool get canRevertEdits => lastEditedAt != null;

  /// What to show in a list. Never empty.
  String get displayName {
    final l = label?.trim();
    if (l != null && l.isNotEmpty) return l;
    return fileName.isNotEmpty ? fileName : 'Untitled import';
  }
}

/// What an undo actually did. Approved entries are money the church has
/// already counted, so they are left alone and reported rather than removed.
class BulkImportUndoResult {
  const BulkImportUndoResult({required this.removed, required this.kept});

  final int removed;
  final int kept;
}

/// What clearing a whole import did.
///
/// Voiding, not deleting: the entries stay on the books and stay readable,
/// they simply stop counting toward any total. [alreadyVoided] are rows a
/// previous clear had already reversed, so clearing twice reports honestly
/// instead of double-counting.
class BulkImportVoidResult {
  const BulkImportVoidResult({
    required this.voided,
    required this.alreadyVoided,
  });

  final int voided;
  final int alreadyVoided;

  int get total => voided + alreadyVoided;
}

class BulkImportBatchRepository {
  BulkImportBatchRepository(this._firestore, {this.onlyCreatedBy});

  final FirebaseFirestore _firestore;

  /// A staff member's uid: they see only the sheets, and the entries, they
  /// brought in themselves. Null for pastors.
  final String? onlyCreatedBy;

  Query<Map<String, dynamic>> _batchList(String churchId) => onlyCreatedBy == null
      ? _batches(churchId)
      : _batches(churchId).where('createdBy', isEqualTo: onlyCreatedBy);

  CollectionReference<Map<String, dynamic>> _batches(String churchId) =>
      _firestore
          .collection('churches')
          .doc(churchId)
          .collection('import_batches');

  CollectionReference<Map<String, dynamic>> _entries(String churchId) =>
      _firestore.collection('churches').doc(churchId).collection('entries');

  /// How many of an import's entries are still waiting for a pastor. Only
  /// those can be taken back by an undo; a count, so no entries are read.
  Future<int> waitingCount({
    required String churchId,
    required String batchId,
  }) async {
    Query<Map<String, dynamic>> q = _entries(churchId);
    if (onlyCreatedBy != null) q = q.where('createdBy', isEqualTo: onlyCreatedBy);
    final snap = await q
        .where('importBatchId', isEqualTo: batchId)
        .where('status', isEqualTo: 'pending')
        .count()
        .get();
    return snap.count ?? 0;
  }

  /// Claims an id before the import runs, so every entry can carry it.
  String newBatchId(String churchId) => _batches(churchId).doc().id;

  /// Opens the batch record before any entry is written, so a crash mid-loop
  /// still leaves something to undo.
  Future<void> begin({
    required String churchId,
    required String batchId,
    required String fileName,
    required String periodName,
    required ChurchUser staff,
    String? preparedBy,
  }) async {
    await _batches(churchId).doc(batchId).set({
      'id': batchId,
      'churchId': churchId,
      'fileName': fileName,
      'periodName': periodName,
      'entryCount': 0,
      'partnersCreated': 0,
      'totalCedis': 0,
      'skippedCount': 0,
      'inProgress': true,
      'createdBy': staff.uid,
      'createdByName': staff.fullName,
      'preparedBy':
          preparedBy?.trim().isEmpty ?? true ? null : preparedBy!.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'undoneAt': null,
      'removedCount': 0,
      'keptCount': 0,
      'label': null,
      'note': null,
      'voidedAt': null,
      'voidedCount': 0,
    });
  }

  Future<void> finish({
    required String churchId,
    required String batchId,
    required int entryCount,
    required int partnersCreated,
    required double totalCedis,
    required int skippedCount,
  }) async {
    await _batches(churchId).doc(batchId).set({
      'inProgress': false,
      'entryCount': entryCount,
      'partnersCreated': partnersCreated,
      'totalCedis': totalCedis,
      'skippedCount': skippedCount,
    }, SetOptions(merge: true));
  }

  Future<void> record({
    required String churchId,
    required String batchId,
    required String fileName,
    required String periodName,
    required int entryCount,
    required int partnersCreated,
    required double totalCedis,
    required ChurchUser staff,
    String? preparedBy,
  }) async {
    await begin(
      churchId: churchId,
      batchId: batchId,
      fileName: fileName,
      periodName: periodName,
      staff: staff,
      preparedBy: preparedBy,
    );
    await finish(
      churchId: churchId,
      batchId: batchId,
      entryCount: entryCount,
      partnersCreated: partnersCreated,
      totalCedis: totalCedis,
      skippedCount: 0,
    );
  }

  /// Renames an import, and optionally annotates it.
  ///
  /// An import is identified by its file name until someone gives it a better
  /// one. "partners-final-v3.xlsx" says nothing six months later; "March
  /// Sunday offerings" does.
  Future<void> rename({
    required String churchId,
    required String batchId,
    String? label,
    String? note,
    String? preparedBy,
    bool writePreparedBy = false,
    String? previousLabel,
    String? previousNote,
    bool writePrevious = false,
  }) async {
    final trimmedLabel = label?.trim();
    final trimmedNote = note?.trim();
    final trimmedPrepared = preparedBy?.trim();
    await _batches(churchId).doc(batchId).set({
      'label': trimmedLabel?.isEmpty ?? true ? null : trimmedLabel,
      'note': trimmedNote?.isEmpty ?? true ? null : trimmedNote,
      // Only written when the caller edited it. The rename dialog does not ask
      // for it, and a merge that always wrote null would erase it.
      if (writePreparedBy)
        'preparedBy':
            trimmedPrepared?.isEmpty ?? true ? null : trimmedPrepared,
      if (writePrevious) ...{
        'previousLabel':
            previousLabel?.trim().isEmpty ?? true ? null : previousLabel!.trim(),
        'previousNote':
            previousNote?.trim().isEmpty ?? true ? null : previousNote!.trim(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Records that an import was reversed wholesale.
  Future<void> markVoided({
    required String churchId,
    required String batchId,
    required String byUid,
    required int voidedCount,
  }) async {
    await _batches(churchId).doc(batchId).set({
      'voidedAt': FieldValue.serverTimestamp(),
      'voidedBy': byUid,
      'voidedCount': voidedCount,
    }, SetOptions(merge: true));
  }

  /// Records that an import was moved to a different period or arm.
  Future<void> markReassigned({
    required String churchId,
    required String batchId,
    required String byUid,
    required int movedCount,
    String? periodName,
    String? previousPeriodName,
  }) async {
    await _batches(churchId).doc(batchId).set({
      'periodName': ?periodName,
      'previousPeriodName': ?previousPeriodName,
      'reassignedAt': FieldValue.serverTimestamp(),
      'reassignedBy': byUid,
      'reassignedCount': movedCount,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> markReassignUndone({
    required String churchId,
    required String batchId,
    required String byUid,
    required String periodName,
  }) async {
    await _batches(churchId).doc(batchId).set({
      'periodName': periodName,
      'previousPeriodName': null,
      'reassignedAt': null,
      'reassignedBy': null,
      'reassignedCount': 0,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> markRestored({
    required String churchId,
    required String batchId,
    required String byUid,
    required int restoredCount,
  }) async {
    await _batches(churchId).doc(batchId).set({
      'voidedAt': null,
      'voidedBy': null,
      'voidedCount': 0,
      'restoredAt': FieldValue.serverTimestamp(),
      'restoredBy': byUid,
      'restoredCount': restoredCount,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> markEdited({
    required String churchId,
    required String batchId,
    required String byUid,
    required int editedCount,
  }) async {
    await _batches(churchId).doc(batchId).set({
      'lastEditedAt': FieldValue.serverTimestamp(),
      'lastEditedBy': byUid,
      'lastEditedCount': editedCount,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> markEditsReverted({
    required String churchId,
    required String batchId,
    required String byUid,
  }) async {
    await _batches(churchId).doc(batchId).set({
      'lastEditedAt': null,
      'lastEditedBy': null,
      'lastEditedCount': 0,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// One import, or null if it is not there.
  Future<BulkImportBatch?> fetchBatch(String churchId, String batchId) async {
    final d = await _batches(churchId).doc(batchId).get();
    if (!d.exists) return null;
    return BulkImportBatch.fromDoc(d);
  }

  /// Every import, newest first. Paged so a church with years of history does
  /// not pull all of it to show a list.
  Future<({List<BulkImportBatch> items, DocumentSnapshot<Map<String, dynamic>>? lastDoc, bool hasMore})>
      fetchPage(
    String churchId, {
    int pageSize = 25,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    Query<Map<String, dynamic>> q =
        _batchList(churchId).orderBy('createdAt', descending: true).limit(pageSize + 1);
    if (startAfter != null) q = q.startAfterDocument(startAfter);
    final snap = await q.get();
    final hasMore = snap.docs.length > pageSize;
    final docs = snap.docs.take(hasMore ? pageSize : snap.docs.length).toList();
    return (
      items: docs.map(BulkImportBatch.fromDoc).toList(),
      lastDoc: docs.isNotEmpty ? docs.last : null,
      hasMore: hasMore,
    );
  }

  Stream<List<BulkImportBatch>> watchRecent(String churchId, {int limit = 5}) {
    return _batchList(churchId)
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
  // Through the provider, not FirebaseFirestore.instance: every other
  // repository in the app is built this way, and reaching for the singleton
  // here would ignore an override a test had put in place.
  (ref) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    return BulkImportBatchRepository(
      ref.watch(firestoreProvider),
      onlyCreatedBy: idx != null && idx.isStaff ? idx.uid : null,
    );
  },
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

/// Entries of one import still waiting, keyed `churchId/batchId`.
final importWaitingCountProvider = FutureProvider.autoDispose
    .family<int, String>((ref, key) {
      final at = key.indexOf('/');
      return ref
          .watch(bulkImportBatchRepositoryProvider)
          .waitingCount(
            churchId: key.substring(0, at),
            batchId: key.substring(at + 1),
          );
    });
