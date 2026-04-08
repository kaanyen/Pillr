import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/constants/firebase_constants.dart';
import '../../../core/errors/app_exception.dart';
import '../domain/partnership_period.dart';

class PeriodsRepository {
  PeriodsRepository(this._firestore, this._functions);

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> _periods(String churchId) {
    return _firestore.collection('churches').doc(churchId).collection('partnership_periods');
  }

  Stream<List<PartnershipPeriod>> watchPeriods(String churchId) {
    return _periods(churchId).orderBy('startDate', descending: true).snapshots().map(
          (snap) => snap.docs.map(PartnershipPeriod.fromDoc).toList(),
        );
  }

  /// One-shot read (e.g. bulk import) — same ordering as [watchPeriods].
  Future<List<PartnershipPeriod>> fetchPeriods(String churchId) async {
    final q = await _periods(churchId).orderBy('startDate', descending: true).get();
    return q.docs.map(PartnershipPeriod.fromDoc).toList();
  }

  Future<void> createPeriod({
    required String churchId,
    required String uid,
    required String name,
    String? description,
    required DateTime startDate,
    required DateTime endDate,
    bool isActive = false,
  }) async {
    final ref = _periods(churchId).doc();
    final now = FieldValue.serverTimestamp();
    await ref.set({
      'id': ref.id,
      'churchId': churchId,
      'name': name.trim(),
      'description': description?.trim().isEmpty ?? true ? null : description!.trim(),
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'isActive': isActive,
      'totalApprovedAmount': 0,
      'entryCount': 0,
      'createdBy': uid,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  Future<void> updatePeriod({
    required String churchId,
    required PartnershipPeriod period,
    required String name,
    String? description,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    await _periods(churchId).doc(period.id).update({
      'name': name.trim(),
      'description': description?.trim().isEmpty ?? true ? null : description!.trim(),
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deletePeriod({
    required String churchId,
    required String periodId,
  }) async {
    await _periods(churchId).doc(periodId).delete();
  }

  /// Returns true if any entry references this period.
  Future<bool> hasEntriesForPeriod(String churchId, String periodId) async {
    final q = await _firestore
        .collection('churches')
        .doc(churchId)
        .collection('entries')
        .where('partnershipPeriodId', isEqualTo: periodId)
        .limit(1)
        .get();
    return q.docs.isNotEmpty;
  }

  Future<void> activatePeriod({
    required String churchId,
    required String periodId,
  }) async {
    try {
      final callable = _functions.httpsCallable(FirebaseConstants.activatePeriod);
      await callable.call(<String, dynamic>{
        'churchId': churchId,
        'periodId': periodId,
      });
    } on FirebaseFunctionsException catch (e) {
      throw AppException(e.message ?? 'Could not activate period.', code: e.code);
    }
  }
}
