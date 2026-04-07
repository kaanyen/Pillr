import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/member_id_generator.dart';
import '../domain/partner.dart';

class PartnersRepository {
  PartnersRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _partners(String churchId) {
    return _firestore.collection('churches').doc(churchId).collection('partners');
  }

  Stream<List<Partner>> watchPartners(String churchId, {bool includeInactive = false}) {
    return _partners(churchId).orderBy('memberId').snapshots().map((snap) {
      final list = snap.docs.map(Partner.fromDoc).toList();
      if (includeInactive) return list;
      return list.where((p) => p.isActive).toList();
    });
  }

  Future<bool> memberIdExists(String churchId, String memberId, {String? excludePartnerId}) async {
    final normalized = memberId.trim().toUpperCase();
    final q = await _partners(churchId).where('memberId', isEqualTo: normalized).limit(5).get();
    for (final d in q.docs) {
      if (excludePartnerId != null && d.id == excludePartnerId) continue;
      return true;
    }
    return false;
  }

  /// `{churchInitials}{100000–999999}` until unique within the church.
  Future<String> generateUniqueMemberId(String churchId, String? churchDisplayName) async {
    final prefix = churchInitialsFromName(churchDisplayName);
    final rnd = Random();
    for (var attempt = 0; attempt < 100; attempt++) {
      final n = 100000 + rnd.nextInt(900000);
      final id = '$prefix$n';
      if (!await memberIdExists(churchId, id)) return id;
    }
    for (var attempt = 0; attempt < 50; attempt++) {
      final id = '$prefix${DateTime.now().microsecondsSinceEpoch % 1000000}';
      if (!await memberIdExists(churchId, id)) return id;
    }
    throw StateError('Could not generate a unique member ID');
  }

  Future<void> createPartner({
    required String churchId,
    required String uid,
    required String fullName,
    required String fellowship,
    String? email,
    String? phone,
    required String churchDisplayName,
  }) async {
    final memberId = await generateUniqueMemberId(churchId, churchDisplayName);
    final ref = _partners(churchId).doc();
    final now = FieldValue.serverTimestamp();
    await ref.set({
      'id': ref.id,
      'churchId': churchId,
      'memberId': memberId.trim().toUpperCase(),
      'fullName': fullName.trim(),
      'fellowship': fellowship.trim(),
      'email': email?.trim().isEmpty ?? true ? null : email!.trim(),
      'phone': phone?.trim().isEmpty ?? true ? null : phone!.trim(),
      'isActive': true,
      'totalApprovedAmount': 0,
      'entryCount': 0,
      'createdBy': uid,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  Future<void> updatePartner({
    required String churchId,
    required Partner partner,
    required String memberId,
    required String fullName,
    required String fellowship,
    String? email,
    String? phone,
    required bool isActive,
  }) async {
    await _partners(churchId).doc(partner.id).update({
      'memberId': memberId.trim().toUpperCase(),
      'fullName': fullName.trim(),
      'fellowship': fellowship.trim(),
      'email': email?.trim().isEmpty ?? true ? null : email!.trim(),
      'phone': phone?.trim().isEmpty ?? true ? null : phone!.trim(),
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<Partner?> watchPartner(String churchId, String partnerId) {
    return _partners(churchId).doc(partnerId).snapshots().map((s) {
      if (!s.exists) return null;
      return Partner.fromDoc(s);
    });
  }
}
