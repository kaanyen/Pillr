import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/partnership_goal.dart';

class GoalsRepository {
  GoalsRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _goals(String churchId) {
    return _firestore.collection('churches').doc(churchId).collection('goals');
  }

  /// One goal per period+arm — stable id for uniqueness.
  static String documentId(String partnershipPeriodId, String partnershipArmId) =>
      '${partnershipPeriodId}__$partnershipArmId';

  Stream<List<PartnershipGoal>> watchGoals(String churchId) {
    return _goals(churchId).snapshots().map(
          (snap) => snap.docs.map(PartnershipGoal.fromDoc).toList(),
        );
  }

  Future<void> createGoal({
    required String churchId,
    required String uid,
    required String partnershipPeriodId,
    required String partnershipArmId,
    required double targetAmountCedis,
  }) async {
    final id = documentId(partnershipPeriodId, partnershipArmId);
    final ref = _goals(churchId).doc(id);
    final existing = await ref.get();
    if (existing.exists) {
      throw StateError('A goal already exists for this period and arm.');
    }
    final now = FieldValue.serverTimestamp();
    await ref.set({
      'id': id,
      'churchId': churchId,
      'partnershipPeriodId': partnershipPeriodId,
      'partnershipArmId': partnershipArmId,
      'targetAmountCedis': targetAmountCedis,
      'currentAmountCedis': 0,
      'createdBy': uid,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  Future<void> updateGoalTarget({
    required String churchId,
    required PartnershipGoal goal,
    required double targetAmountCedis,
  }) async {
    await _goals(churchId).doc(goal.id).update({
      'targetAmountCedis': targetAmountCedis,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteGoal({required String churchId, required String goalId}) async {
    await _goals(churchId).doc(goalId).delete();
  }

  /// Newest first by `updatedAt`.
  Future<({
    List<PartnershipGoal> items,
    DocumentSnapshot<Map<String, dynamic>>? lastDoc,
    bool hasMore,
  })> fetchGoalsPage(
    String churchId, {
    int pageSize = 20,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    Query<Map<String, dynamic>> q =
        _goals(churchId).orderBy('updatedAt', descending: true).limit(pageSize + 1);
    if (startAfter != null) {
      q = q.startAfterDocument(startAfter);
    }
    final snap = await q.get();
    final hasMore = snap.docs.length > pageSize;
    final docs = hasMore ? snap.docs.take(pageSize).toList() : snap.docs.toList();
    final items = docs.map(PartnershipGoal.fromDoc).toList();
    final lastDoc = docs.isEmpty ? null : docs.last;
    return (items: items, lastDoc: lastDoc, hasMore: hasMore);
  }
}
