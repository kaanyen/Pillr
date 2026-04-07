import 'package:cloud_firestore/cloud_firestore.dart';

import '../../auth/domain/church_user.dart';
import '../domain/partnership_entry.dart';

class EntriesRepository {
  EntriesRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _entries(String churchId) {
    return _firestore.collection('churches').doc(churchId).collection('entries');
  }

  Stream<List<PartnershipEntry>> watchAllEntries(String churchId) {
    return _entries(churchId).orderBy('createdAt', descending: true).snapshots().map(
          (snap) => snap.docs.map(PartnershipEntry.fromDoc).toList(),
        );
  }

  Stream<List<PartnershipEntry>> watchMyEntries(String churchId, String uid) {
    return _entries(churchId)
        .where('createdBy', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(PartnershipEntry.fromDoc).toList());
  }

  Stream<List<PartnershipEntry>> watchPendingEntries(String churchId) {
    return _entries(churchId)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(PartnershipEntry.fromDoc).toList());
  }

  Stream<List<PartnershipEntry>> watchPartnerEntries(String churchId, String partnerId) {
    return _entries(churchId)
        .where('partnerId', isEqualTo: partnerId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(PartnershipEntry.fromDoc).toList());
  }

  Stream<PartnershipEntry?> watchEntry(String churchId, String entryId) {
    return _entries(churchId).doc(entryId).snapshots().map((s) {
      if (!s.exists) return null;
      return PartnershipEntry.fromDoc(s);
    });
  }

  Future<void> createEntry({
    required String churchId,
    required ChurchUser staff,
    required String partnerId,
    required Map<String, dynamic> partnerSnapshot,
    required String partnershipArmId,
    required Map<String, dynamic> armSnapshot,
    required String partnershipPeriodId,
    required Map<String, dynamic> periodSnapshot,
    required double amountCedis,
    required DateTime dateGiven,
    String? notes,
  }) async {
    final ref = _entries(churchId).doc();
    final now = FieldValue.serverTimestamp();
    await ref.set({
      'id': ref.id,
      'churchId': churchId,
      'partnerId': partnerId,
      'partnerSnapshot': partnerSnapshot,
      'partnershipArmId': partnershipArmId,
      'armSnapshot': armSnapshot,
      'partnershipPeriodId': partnershipPeriodId,
      'periodSnapshot': periodSnapshot,
      'amountCedis': amountCedis,
      'dateGiven': Timestamp.fromDate(dateGiven),
      'notes': notes?.trim().isEmpty ?? true ? null : notes!.trim(),
      'status': 'pending',
      'createdBy': staff.uid,
      'createdBySnapshot': {
        'fullName': staff.fullName,
        'role': staff.role,
      },
      'createdAt': now,
      'updatedAt': now,
      'reviewedBy': null,
      'reviewedBySnapshot': null,
      'reviewedAt': null,
      'declineReason': null,
      'editHistory': <Map<String, dynamic>>[],
    });
  }

  Future<void> staffUpdateEntry({
    required String churchId,
    required PartnershipEntry existing,
    required ChurchUser staff,
    required String partnerId,
    required Map<String, dynamic> partnerSnapshot,
    required String partnershipArmId,
    required Map<String, dynamic> armSnapshot,
    required String partnershipPeriodId,
    required Map<String, dynamic> periodSnapshot,
    required double amountCedis,
    required DateTime dateGiven,
    String? notes,
  }) async {
    final prev = {
      'amountCedis': existing.amountCedis,
      'partnershipArmId': existing.partnershipArmId,
      'partnershipPeriodId': existing.partnershipPeriodId,
      'notes': existing.notes,
    };
    final history = List<Map<String, dynamic>>.from(existing.editHistory);
    history.add({
      'editedBy': staff.uid,
      'editedAt': Timestamp.now(),
      'previousValues': prev,
      'changeDescription': 'Staff updated entry (resubmitted as pending)',
    });
    await _entries(churchId).doc(existing.id).update({
      'partnerId': partnerId,
      'partnerSnapshot': partnerSnapshot,
      'partnershipArmId': partnershipArmId,
      'armSnapshot': armSnapshot,
      'partnershipPeriodId': partnershipPeriodId,
      'periodSnapshot': periodSnapshot,
      'amountCedis': amountCedis,
      'dateGiven': Timestamp.fromDate(dateGiven),
      'notes': notes?.trim().isEmpty ?? true ? null : notes!.trim(),
      'status': 'pending',
      'updatedAt': FieldValue.serverTimestamp(),
      'reviewedBy': null,
      'reviewedBySnapshot': null,
      'reviewedAt': null,
      'declineReason': null,
      'editHistory': history,
    });
  }

  Future<void> approveEntry({
    required String churchId,
    required PartnershipEntry entry,
    required ChurchUser pastor,
  }) async {
    await _entries(churchId).doc(entry.id).update({
      'status': 'approved',
      'reviewedBy': pastor.uid,
      'reviewedBySnapshot': {
        'fullName': pastor.fullName,
      },
      'reviewedAt': FieldValue.serverTimestamp(),
      'declineReason': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> declineEntry({
    required String churchId,
    required PartnershipEntry entry,
    required ChurchUser pastor,
    required String reason,
  }) async {
    await _entries(churchId).doc(entry.id).update({
      'status': 'declined',
      'reviewedBy': pastor.uid,
      'reviewedBySnapshot': {
        'fullName': pastor.fullName,
      },
      'reviewedAt': FieldValue.serverTimestamp(),
      'declineReason': reason.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> pastorUpdateEntry({
    required String churchId,
    required PartnershipEntry existing,
    required ChurchUser pastor,
    required String partnerId,
    required Map<String, dynamic> partnerSnapshot,
    required String partnershipArmId,
    required Map<String, dynamic> armSnapshot,
    required String partnershipPeriodId,
    required Map<String, dynamic> periodSnapshot,
    required double amountCedis,
    required DateTime dateGiven,
    String? notes,
  }) async {
    final prev = {
      'amountCedis': existing.amountCedis,
      'status': existing.status,
    };
    final history = List<Map<String, dynamic>>.from(existing.editHistory);
    history.add({
      'editedBy': pastor.uid,
      'editedAt': Timestamp.now(),
      'previousValues': prev,
      'changeDescription': 'Pastor edited entry',
    });
    await _entries(churchId).doc(existing.id).update({
      'partnerId': partnerId,
      'partnerSnapshot': partnerSnapshot,
      'partnershipArmId': partnershipArmId,
      'armSnapshot': armSnapshot,
      'partnershipPeriodId': partnershipPeriodId,
      'periodSnapshot': periodSnapshot,
      'amountCedis': amountCedis,
      'dateGiven': Timestamp.fromDate(dateGiven),
      'notes': notes?.trim().isEmpty ?? true ? null : notes!.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      'editHistory': history,
    });
  }

  Future<void> deleteEntry({
    required String churchId,
    required String entryId,
  }) async {
    await _entries(churchId).doc(entryId).delete();
  }
}
