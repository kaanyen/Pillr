import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/text_case_utils.dart';
import '../domain/arm_tree.dart';
import '../domain/partnership_arm.dart';

class ArmsRepository {
  ArmsRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _arms(String churchId) {
    return _firestore.collection('churches').doc(churchId).collection('partnership_arms');
  }

  Stream<List<PartnershipArm>> watchArms(String churchId) {
    return _arms(churchId).orderBy('sortOrder').snapshots().map(
          (snap) => snap.docs.map(PartnershipArm.fromDoc).toList(),
        );
  }

  /// One-shot read (e.g. bulk import) — avoids relying on [armsStreamProvider] timing.
  Future<List<PartnershipArm>> fetchArms(String churchId) async {
    final q = await _arms(churchId).orderBy('sortOrder').get();
    return q.docs.map(PartnershipArm.fromDoc).toList();
  }

  Future<int> _nextSortOrder(String churchId) async {
    final q = await _arms(churchId).orderBy('sortOrder', descending: true).limit(1).get();
    if (q.docs.isEmpty) return 0;
    final v = q.docs.first.data()['sortOrder'];
    final n = (v is num) ? v.toInt() : 0;
    return n + 1;
  }

  Future<void> createArm({
    required String churchId,
    required String uid,
    required String name,
    String? description,
    bool isActive = true,
    String? colorHex,
  }) async {
    final ref = _arms(churchId).doc();
    final sortOrder = await _nextSortOrder(churchId);
    final now = FieldValue.serverTimestamp();
    await ref.set({
      'id': ref.id,
      'churchId': churchId,
      'name': TextCaseUtils.toTitleCase(name),
      'description': trimOrNull(description),
      'isActive': isActive,
      'colorHex': normalizeArmColorHex(colorHex),
      'sortOrder': sortOrder,
      'createdBy': uid,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  Future<void> updateArm({
    required String churchId,
    required PartnershipArm arm,
    required String name,
    String? description,
    required bool isActive,
    String? colorHex,
  }) async {
    await _arms(churchId).doc(arm.id).update({
      'name': TextCaseUtils.toTitleCase(name),
      'description': trimOrNull(description),
      'isActive': isActive,
      'colorHex': normalizeArmColorHex(colorHex),
      'sortOrder': arm.sortOrder,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Saves a new arrangement of arms: which main arm each counts toward, and
  /// the order they are listed in.
  ///
  /// Only `parentArmId`, `sortOrder` and `updatedAt` are written, and only on
  /// arms whose place actually changed. No entry, total or goal is touched:
  /// a main arm's figures are added up from its sub-arms when they are shown.
  Future<void> arrangeArms({
    required String churchId,
    required List<ArmPlacement> placements,
  }) async {
    if (placements.isEmpty) return;
    final batch = _firestore.batch();
    for (final p in placements) {
      batch.update(_arms(churchId).doc(p.armId), {
        'parentArmId': p.parentArmId,
        'sortOrder': p.sortOrder,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> setActive({
    required String churchId,
    required String armId,
    required bool isActive,
  }) async {
    await _arms(churchId).doc(armId).update({
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Records a spreadsheet spelling that resolves to [armId].
  ///
  /// Uses [FieldValue.arrayUnion] so concurrent imports cannot clobber each
  /// other's mappings, and stores the normalised form because that is what the
  /// matcher compares against.
  Future<void> rememberArmAlias({
    required String churchId,
    required String armId,
    required String alias,
  }) async {
    final normalized = alias.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return;
    await _arms(churchId).doc(armId).update({
      'aliases': FieldValue.arrayUnion([normalized]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteArm({
    required String churchId,
    required String armId,
  }) async {
    await _arms(churchId).doc(armId).delete();
  }
}

