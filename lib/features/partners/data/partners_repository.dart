import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/member_id_generator.dart';
import '../../../core/utils/text_case_utils.dart';
import '../domain/partner.dart';

class PartnersRepository {
  PartnersRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _partners(String churchId) {
    return _firestore
        .collection('churches')
        .doc(churchId)
        .collection('partners');
  }

  Stream<List<Partner>> watchPartners(
    String churchId, {
    bool includeInactive = false,
  }) {
    return _partners(churchId).orderBy('memberId').snapshots().map((snap) {
      final list = snap.docs.map(Partner.fromDoc).toList();
      if (includeInactive) return list;
      return list.where((p) => p.isActive).toList();
    });
  }

  /// Returns the partner with this [memberId], or null if none.
  Future<Partner?> findPartnerByMemberId(
    String churchId,
    String memberId,
  ) async {
    final normalized = memberId.trim().toUpperCase();
    if (normalized.isEmpty) return null;
    final q = await _partners(
      churchId,
    ).where('memberId', isEqualTo: normalized).limit(1).get();
    if (q.docs.isEmpty) return null;
    return Partner.fromDoc(q.docs.first);
  }

  /// All active partners (paginated internally). Used for bulk import matching.
  Future<List<Partner>> fetchAllActivePartners(String churchId) =>
      fetchAllPartners(churchId, includeInactive: false);

  Future<List<Partner>> fetchAllPartners(
    String churchId, {
    required bool includeInactive,
  }) async {
    final out = <Partner>[];
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    while (true) {
      final page = await fetchPartnersPage(
        churchId,
        includeInactive: includeInactive,
        pageSize: 400,
        startAfter: cursor,
      );
      out.addAll(page.items);
      if (!page.hasMore || page.lastDoc == null) break;
      cursor = page.lastDoc;
    }
    return out;
  }

  Future<bool> memberIdExists(
    String churchId,
    String memberId, {
    String? excludePartnerId,
  }) async {
    final normalized = memberId.trim().toUpperCase();
    // A retired ID — one a merged person used to have — counts as taken, so
    // an old receipt or sheet never points at someone new.
    final results = await Future.wait([
      _partners(
        churchId,
      ).where('memberId', isEqualTo: normalized).limit(5).get(),
      _partners(
        churchId,
      ).where('formerMemberIds', arrayContains: normalized).limit(5).get(),
    ]);
    for (final q in results) {
      for (final d in q.docs) {
        if (excludePartnerId != null && d.id == excludePartnerId) continue;
        return true;
      }
    }
    return false;
  }

  /// `{churchInitials}{100000–999999}` until unique within the church.
  Future<String> generateUniqueMemberId(
    String churchId,
    String? churchDisplayName,
  ) async {
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

  /// Returns new document id and assigned member id.
  Future<({String id, String memberId})> createPartner({
    required String churchId,
    required String uid,
    required String fullName,
    required String fellowship,
    String? email,
    String? phone,
    required String churchDisplayName,
  }) async {
    final memberId = await generateUniqueMemberId(churchId, churchDisplayName);
    final mid = memberId.trim().toUpperCase();
    final fn = TextCaseUtils.toTitleCase(fullName);
    final fs = TextCaseUtils.toTitleCase(fellowship);
    final docRef = _partners(churchId).doc();
    final now = FieldValue.serverTimestamp();
    await docRef.set({
      'id': docRef.id,
      'churchId': churchId,
      'memberId': mid,
      'fullName': fn,
      'fellowship': fs,
      'fullNameLower': fn.toLowerCase(),
      'fellowshipLower': fs.toLowerCase(),
      'email': email?.trim().isEmpty ?? true ? null : email!.trim(),
      'phone': phone?.trim().isEmpty ?? true ? null : phone!.trim(),
      'isActive': true,
      'totalApprovedAmount': 0,
      'totalApprovedPesewas': 0,
      'entryCount': 0,
      'createdBy': uid,
      'createdAt': now,
      'updatedAt': now,
    });
    return (id: docRef.id, memberId: mid);
  }

  /// A changed member ID keeps the old one in `formerMemberIds`, so old
  /// receipts, sheets and searches still find this person.
  Future<void> updatePartner({
    required String churchId,
    required Partner partner,
    required String memberId,
    required String fullName,
    required String fellowship,
    String? email,
    String? phone,
    required bool isActive,
    List<String>? phones,
    List<String>? emails,
    String? address,
    String? notes,
  }) async {
    final fn = TextCaseUtils.toTitleCase(fullName);
    final fs = TextCaseUtils.toTitleCase(fellowship);
    final mid = memberId.trim().toUpperCase();
    final oldId = partner.memberId.trim().toUpperCase();
    String? blankToNull(String? v) =>
        v?.trim().isEmpty ?? true ? null : v!.trim();
    await _partners(churchId).doc(partner.id).update({
      'phones': ?phones,
      'emails': ?emails,
      'memberId': mid,
      if (mid != oldId && oldId.isNotEmpty)
        'formerMemberIds': [...partner.formerMemberIds, oldId],
      'fullName': fn,
      'fellowship': fs,
      'fullNameLower': fn.toLowerCase(),
      'fellowshipLower': fs.toLowerCase(),
      'email': blankToNull(email),
      'phone': blankToNull(phone),
      'address': blankToNull(address),
      'notes': blankToNull(notes),
      // Written only when it changes: staff may not touch it, and an older
      // record may have no isActive field at all.
      if (isActive != partner.isActive) 'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Notes why a partner has gone quiet. Blank clears it.
  Future<void> setFollowUpReason({
    required String churchId,
    required String partnerId,
    required String reason,
  }) async {
    final r = reason.trim();
    await _partners(churchId).doc(partnerId).update({
      'followUpReason': r.isEmpty ? null : r,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Prefix search via Firestore (`memberId`, `fullNameLower`, `fellowshipLower`) plus
  /// client fallback for partners missing lowercase fields (legacy) or fuzzy match.
  Future<List<Partner>> searchPartners(
    String churchId,
    String query, {
    bool includeInactive = false,
    int limit = 60,
  }) async {
    final col = _partners(churchId);
    final q = query.trim();
    if (q.isEmpty) {
      final snap = await col.orderBy('memberId').limit(limit).get();
      final list = snap.docs.map(Partner.fromDoc).toList();
      if (includeInactive) return list;
      return list.where((p) => p.isActive).toList();
    }

    final qUpper = q.toUpperCase();
    final qLower = q.toLowerCase();
    final Map<String, Partner> byId = {};

    Future<void> merge(Query<Map<String, dynamic>> rq) async {
      final snap = await rq.get();
      for (final d in snap.docs) {
        final p = Partner.fromDoc(d);
        if (!includeInactive && !p.isActive) continue;
        byId[p.id] = p;
      }
    }

    await Future.wait([
      merge(
        col
            .where('memberId', isGreaterThanOrEqualTo: qUpper)
            .where('memberId', isLessThanOrEqualTo: '$qUpper\uf8ff')
            .limit(25),
      ),
      merge(
        col
            .where('fullNameLower', isGreaterThanOrEqualTo: qLower)
            .where('fullNameLower', isLessThanOrEqualTo: '$qLower\uf8ff')
            .limit(25),
      ),
      // An old member ID from before a merge finds the merged person.
      merge(col.where('formerMemberIds', arrayContains: qUpper).limit(5)),
      merge(
        col
            .where('fellowshipLower', isGreaterThanOrEqualTo: qLower)
            .where('fellowshipLower', isLessThanOrEqualTo: '$qLower\uf8ff')
            .limit(25),
      ),
    ]);

    if (byId.length < 12) {
      final snap = await col.orderBy('memberId').limit(300).get();
      for (final d in snap.docs) {
        final p = Partner.fromDoc(d);
        if (!includeInactive && !p.isActive) continue;
        final hay = '${p.memberId} ${p.fullName} ${p.fellowship}'.toLowerCase();
        if (hay.contains(qLower)) {
          byId[p.id] = p;
        }
      }
    }

    final out = byId.values.toList()
      ..sort((a, b) => a.memberId.compareTo(b.memberId));
    if (out.length <= limit) return out;
    return out.sublist(0, limit);
  }

  Stream<Partner?> watchPartner(String churchId, String partnerId) {
    return _partners(churchId).doc(partnerId).snapshots().map((s) {
      if (!s.exists) return null;
      return Partner.fromDoc(s);
    });
  }

  /// Server-side pagination by `memberId` (active-only uses composite index).
  Future<
    ({
      List<Partner> items,
      DocumentSnapshot<Map<String, dynamic>>? lastDoc,
      bool hasMore,
    })
  >
  fetchPartnersPage(
    String churchId, {
    required bool includeInactive,
    int pageSize = 20,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    Query<Map<String, dynamic>> q = _partners(churchId);
    if (!includeInactive) {
      q = q.where('isActive', isEqualTo: true);
    }
    q = q.orderBy('memberId');
    if (startAfter != null) {
      q = q.startAfterDocument(startAfter);
    }
    final snap = await q.limit(pageSize + 1).get();
    final hasMore = snap.docs.length > pageSize;
    final docs = hasMore
        ? snap.docs.take(pageSize).toList()
        : snap.docs.toList();
    final items = docs.map(Partner.fromDoc).toList();
    final lastDoc = docs.isEmpty ? null : docs.last;
    return (items: items, lastDoc: lastDoc, hasMore: hasMore);
  }
}
