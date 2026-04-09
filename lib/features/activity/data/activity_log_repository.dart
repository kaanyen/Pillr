import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/text_case_utils.dart';
import '../domain/activity_log_row.dart';

/// Client-written audit rows under `churches/{churchId}/activity_logs` (build doc §7).
class ActivityLogRepository {
  ActivityLogRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _logs(String churchId) {
    return _firestore.collection('churches').doc(churchId).collection('activity_logs');
  }

  /// Newest first (requires `createdAt` on documents).
  Stream<List<ActivityLogRow>> watchActivityLogs(String churchId, {int limit = 200}) {
    return _logs(churchId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(ActivityLogRow.fromDoc).toList());
  }

  /// Newest first; use [startAfter] for the next page.
  Future<({
    List<ActivityLogRow> items,
    DocumentSnapshot<Map<String, dynamic>>? lastDoc,
    bool hasMore,
  })> fetchActivityLogsPage(
    String churchId, {
    int pageSize = 50,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    Query<Map<String, dynamic>> q =
        _logs(churchId).orderBy('createdAt', descending: true).limit(pageSize + 1);
    if (startAfter != null) {
      q = q.startAfterDocument(startAfter);
    }
    final snap = await q.get();
    final hasMore = snap.docs.length > pageSize;
    final docs = hasMore ? snap.docs.take(pageSize).toList() : snap.docs.toList();
    final items = docs.map(ActivityLogRow.fromDoc).toList();
    final lastDoc = docs.isEmpty ? null : docs.last;
    return (items: items, lastDoc: lastDoc, hasMore: hasMore);
  }

  Future<void> log({
    required String churchId,
    required String actorUid,
    required Map<String, dynamic> actorSnapshot,
    required String action,
    required String entityType,
    String? entityId,
    Map<String, dynamic>? entitySnapshot,
    Map<String, dynamic>? metadata,
  }) async {
    await _logs(churchId).add({
      'churchId': churchId,
      'actorUid': actorUid,
      'actorSnapshot': TextCaseUtils.normalizePersonSnapshot(actorSnapshot),
      'action': action,
      'entityType': entityType,
      'entityId': entityId,
      'entitySnapshot': entitySnapshot == null
          ? null
          : TextCaseUtils.normalizeLooseEntitySnapshot(entitySnapshot),
      'metadata': metadata,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
