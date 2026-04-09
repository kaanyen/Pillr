import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/text_case_utils.dart';
import '../../auth/domain/church_user.dart';
import '../domain/partnership_entry.dart';

bool _isPastorRole(ChurchUser staff) => staff.role == 'pastor';

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

  Future<PartnershipEntry?> getEntry(String churchId, String entryId) async {
    final d = await _entries(churchId).doc(entryId).get();
    if (!d.exists) return null;
    return PartnershipEntry.fromDoc(d);
  }

  /// Paged fetch for lists (§16.4.7). [allChurchEntries] true = pastor view; else filter [createdByUid].
  /// [statusFilter] when non-null restricts to `pending` | `approved` | `declined`.
  /// [newestFirst] false = oldest first (`createdAt` ascending).
  Future<({
    List<PartnershipEntry> items,
    DocumentSnapshot<Map<String, dynamic>>? lastDoc,
    bool hasMore,
  })> fetchEntriesPage(
    String churchId, {
    required bool allChurchEntries,
    String? createdByUid,
    String? statusFilter,
    bool newestFirst = true,
    int pageSize = 20,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    assert(allChurchEntries || (createdByUid != null && createdByUid.isNotEmpty));
    Query<Map<String, dynamic>> q = _entries(churchId);
    if (!allChurchEntries) {
      q = q.where('createdBy', isEqualTo: createdByUid);
    }
    if (statusFilter != null && statusFilter.isNotEmpty) {
      q = q.where('status', isEqualTo: statusFilter);
    }
    q = q.orderBy('createdAt', descending: newestFirst);
    q = q.limit(pageSize + 1);
    if (startAfter != null) {
      q = q.startAfterDocument(startAfter);
    }
    final snap = await q.get();
    final hasMore = snap.docs.length > pageSize;
    final take = hasMore ? pageSize : snap.docs.length;
    final docs = snap.docs.take(take).toList();
    final items = docs.map(PartnershipEntry.fromDoc).toList();
    final lastDoc = docs.isNotEmpty ? docs.last : null;
    return (items: items, lastDoc: lastDoc, hasMore: hasMore);
  }

  /// Entries for a partner — used for duplicate detection (§16.4.3).
  /// Pastor: all entries for that partner; staff: only entries they created.
  Future<List<PartnershipEntry>> fetchEntriesForDuplicateCheck(
    String churchId, {
    required String partnerId,
    required bool allChurchEntries,
    String? createdByUid,
  }) async {
    assert(allChurchEntries || (createdByUid != null && createdByUid.isNotEmpty));
    Query<Map<String, dynamic>> q = _entries(churchId).where('partnerId', isEqualTo: partnerId);
    if (!allChurchEntries) {
      q = q.where('createdBy', isEqualTo: createdByUid);
    }
    final snap = await q.get();
    return snap.docs.map(PartnershipEntry.fromDoc).toList();
  }

  /// All entry rows for export (paginates internally).
  Future<List<PartnershipEntry>> fetchAllEntriesForExport(
    String churchId, {
    required bool allChurchEntries,
    String? createdByUid,
    int chunk = 200,
  }) async {
    final out = <PartnershipEntry>[];
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    while (true) {
      final page = await fetchEntriesPage(
        churchId,
        allChurchEntries: allChurchEntries,
        createdByUid: createdByUid,
        pageSize: chunk,
        startAfter: cursor,
      );
      out.addAll(page.items);
      if (!page.hasMore || page.lastDoc == null) break;
      cursor = page.lastDoc;
    }
    return out;
  }

  /// Returns the new entry document id.
  Future<String> createEntry({
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
    final docRef = _entries(churchId).doc();
    final now = FieldValue.serverTimestamp();
    final pastorCreates = _isPastorRole(staff);
    await docRef.set({
      'id': docRef.id,
      'churchId': churchId,
      'partnerId': partnerId,
      'partnerSnapshot': TextCaseUtils.normalizePartnerSnapshot(partnerSnapshot),
      'partnershipArmId': partnershipArmId,
      'armSnapshot': TextCaseUtils.normalizeNamedSnapshot(armSnapshot),
      'partnershipPeriodId': partnershipPeriodId,
      'periodSnapshot': TextCaseUtils.normalizeNamedSnapshot(periodSnapshot),
      'amountCedis': amountCedis,
      'dateGiven': Timestamp.fromDate(dateGiven),
      'notes': notes?.trim().isEmpty ?? true ? null : notes!.trim(),
      'status': pastorCreates ? 'approved' : 'pending',
      'createdBy': staff.uid,
      'createdBySnapshot': TextCaseUtils.normalizePersonSnapshot({
        'fullName': staff.fullName,
        'role': staff.role,
      }),
      'createdAt': now,
      'updatedAt': now,
      'reviewedBy': pastorCreates ? staff.uid : null,
      'reviewedBySnapshot': pastorCreates
          ? TextCaseUtils.normalizePersonSnapshot({
              'fullName': staff.fullName,
            })
          : null,
      'reviewedAt': pastorCreates ? now : null,
      'declineReason': null,
      'editHistory': <Map<String, dynamic>>[],
    });
    return docRef.id;
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
      'partnerSnapshot': TextCaseUtils.normalizePartnerSnapshot(partnerSnapshot),
      'partnershipArmId': partnershipArmId,
      'armSnapshot': TextCaseUtils.normalizeNamedSnapshot(armSnapshot),
      'partnershipPeriodId': partnershipPeriodId,
      'periodSnapshot': TextCaseUtils.normalizeNamedSnapshot(periodSnapshot),
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
      'reviewedBySnapshot': TextCaseUtils.normalizePersonSnapshot({
        'fullName': pastor.fullName,
      }),
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
      'reviewedBySnapshot': TextCaseUtils.normalizePersonSnapshot({
        'fullName': pastor.fullName,
      }),
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
      'partnerSnapshot': TextCaseUtils.normalizePartnerSnapshot(partnerSnapshot),
      'partnershipArmId': partnershipArmId,
      'armSnapshot': TextCaseUtils.normalizeNamedSnapshot(armSnapshot),
      'partnershipPeriodId': partnershipPeriodId,
      'periodSnapshot': TextCaseUtils.normalizeNamedSnapshot(periodSnapshot),
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
