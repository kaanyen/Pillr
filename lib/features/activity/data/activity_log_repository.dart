import 'package:cloud_firestore/cloud_firestore.dart';

/// Client-written audit rows under `churches/{churchId}/activity_logs` (build doc §7).
class ActivityLogRepository {
  ActivityLogRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _logs(String churchId) {
    return _firestore.collection('churches').doc(churchId).collection('activity_logs');
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
      'actorSnapshot': actorSnapshot,
      'action': action,
      'entityType': entityType,
      'entityId': entityId,
      'entitySnapshot': entitySnapshot,
      'metadata': metadata,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
