import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money.dart';
import '../../../core/utils/text_case_utils.dart';
import '../../auth/domain/church_user.dart';
import '../../auth/providers/auth_providers.dart';
import '../../entries/domain/partnership_entry.dart';
import '../../partners/domain/partner.dart';
import '../domain/data_health.dart';
import '../domain/totals_audit.dart';

/// Reads the whole church, and applies the repairs the tools propose.
///
/// Every scan here walks every entry, which is exactly the thing the rest of
/// the app was just taught not to do. That is deliberate and confined: an audit
/// has to see everything to be an audit, it runs when someone presses a button,
/// and it never holds the result in a live provider. Pages are read in chunks
/// so a large church does not arrive in one response.
class MaintenanceRepository {
  MaintenanceRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _entries(String churchId) =>
      _firestore.collection('churches').doc(churchId).collection('entries');

  CollectionReference<Map<String, dynamic>> _partners(String churchId) =>
      _firestore.collection('churches').doc(churchId).collection('partners');

  CollectionReference<Map<String, dynamic>> _periods(String churchId) =>
      _firestore
          .collection('churches')
          .doc(churchId)
          .collection('partnership_periods');

  /// Every entry in the church, read a page at a time.
  Future<List<PartnershipEntry>> _allEntries(
    String churchId, {
    void Function(int scanned)? onProgress,
  }) async {
    final out = <PartnershipEntry>[];
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    while (true) {
      Query<Map<String, dynamic>> q =
          _entries(churchId).orderBy(FieldPath.documentId).limit(500);
      if (cursor != null) q = q.startAfterDocument(cursor);
      final snap = await q.get();
      if (snap.docs.isEmpty) break;
      out.addAll(snap.docs.map(PartnershipEntry.fromDoc));
      onProgress?.call(out.length);
      if (snap.docs.length < 500) break;
      cursor = snap.docs.last;
    }
    return out;
  }

  Future<List<Partner>> allPartners(String churchId) async {
    final out = <Partner>[];
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    while (true) {
      Query<Map<String, dynamic>> q =
          _partners(churchId).orderBy(FieldPath.documentId).limit(500);
      if (cursor != null) q = q.startAfterDocument(cursor);
      final snap = await q.get();
      if (snap.docs.isEmpty) break;
      out.addAll(snap.docs.map(Partner.fromDoc));
      if (snap.docs.length < 500) break;
      cursor = snap.docs.last;
    }
    return out;
  }

  // ------------------------------------------------------------ totals audit

  /// Compares every stored total against the entries behind it.
  Future<TotalsAuditReport> auditTotals(
    String churchId, {
    void Function(int scanned)? onProgress,
  }) async {
    final entries = await _allEntries(churchId, onProgress: onProgress);
    final partners = await allPartners(churchId);
    final periodDocs = await _periods(churchId).get();

    final partnerDrift = findTotalsDrift(
      kind: TotalsDriftKind.partner,
      stored: [
        for (final p in partners)
          StoredTotal(
            id: p.id,
            name: p.fullName,
            totalApprovedAmount: p.totalApprovedAmount,
            entryCount: p.entryCount,
          ),
      ],
      expected: expectedTotalsBy(entries, (e) => e.partnerId),
    );

    final periodDrift = findTotalsDrift(
      kind: TotalsDriftKind.period,
      stored: [
        for (final d in periodDocs.docs)
          StoredTotal(
            id: d.id,
            name: (d.data()['name'] ?? d.id) as String,
            totalApprovedAmount: storedTotalCedis(
              d.data(),
              pesewasKey: 'totalApprovedPesewas',
              cedisKey: 'totalApprovedAmount',
            ),
            entryCount: ((d.data()['entryCount'] ?? 0) as num).toInt(),
          ),
      ],
      expected: expectedTotalsBy(entries, (e) => e.partnershipPeriodId),
    );

    return TotalsAuditReport(
      partnerDrift: partnerDrift,
      periodDrift: periodDrift,
      entriesScanned: entries.length,
    );
  }

  /// Writes the recomputed figures back.
  ///
  /// A plain `set` of the correct value, not an increment: the whole point is
  /// that the incremental path is what drifted. The aggregate trigger will not
  /// fight this — it only reacts to writes on `entries`.
  ///
  /// Both forms of the total are written, so this is also how a document that
  /// predates `totalApprovedPesewas` gets one. Until it does, the app reads its
  /// cedi figure and the exactness this buys is simply not there yet.
  Future<int> repairTotals({
    required String churchId,
    required List<TotalsDrift> drift,
  }) async {
    var repaired = 0;
    const chunkSize = 400;
    final fixable = drift.where((d) => d.name != '(missing record)').toList();

    for (var i = 0; i < fixable.length; i += chunkSize) {
      final end =
          (i + chunkSize < fixable.length) ? i + chunkSize : fixable.length;
      final batch = _firestore.batch();
      for (var j = i; j < end; j++) {
        final d = fixable[j];
        final ref = d.kind == TotalsDriftKind.partner
            ? _partners(churchId).doc(d.id)
            : _periods(churchId).doc(d.id);
        batch.update(ref, {
          'totalApprovedAmount': d.expected,
          'totalApprovedPesewas': d.expectedPesewas,
          'entryCount': d.expectedCount,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        repaired++;
      }
      await batch.commit();
    }
    return repaired;
  }

  // -------------------------------------------------------------- duplicates

  Future<List<DuplicatePartnerPair>> scanDuplicatePartners(
    String churchId,
  ) async {
    return findDuplicatePartners(await allPartners(churchId));
  }

  Future<List<DuplicateEntryPair>> scanDuplicateEntries(
    String churchId, {
    void Function(int scanned)? onProgress,
  }) async {
    return findDuplicateEntries(
      await _allEntries(churchId, onProgress: onProgress),
    );
  }

  Future<List<PartnerDataIssue>> scanPartnerData(String churchId) async {
    return findPartnerDataIssues(await allPartners(churchId));
  }

  /// Entries belonging to either partner in a proposed merge.
  Future<List<PartnershipEntry>> entriesForPartners(
    String churchId,
    List<String> partnerIds,
  ) async {
    final out = <PartnershipEntry>[];
    for (final id in partnerIds) {
      final snap =
          await _entries(churchId).where('partnerId', isEqualTo: id).get();
      out.addAll(snap.docs.map(PartnershipEntry.fromDoc));
    }
    return out;
  }

  // ------------------------------------------------------------------ merges

  /// Moves one partner's entries onto another and retires the empty record.
  ///
  /// The absorbed partner is deactivated rather than deleted: it may be
  /// referenced by a receipt, an export or someone's memory, and a record that
  /// vanishes is harder to explain than one marked closed.
  ///
  /// Neither total is written here. Repointing an entry is a write the
  /// aggregate trigger already answers — it takes the money off the absorbed
  /// partner and puts it on the survivor, one entry at a time. Writing the
  /// recomputed figures as well double-counted every gift that moved: the
  /// trigger's increments land a moment after this commit, on top of a total
  /// that already included them. A two-partner merge of ₵200 and ₵300 left the
  /// survivor holding ₵800 and the absorbed record holding −₵300.
  ///
  /// [PartnerMergePlan.resultingTotal] is still what the confirmation shows the
  /// person doing the merge; it is a prediction, not a write.
  Future<int> mergePartners({
    required String churchId,
    required PartnerMergePlan plan,
    required ChurchUser actor,
  }) async {
    final keepSnapshot = TextCaseUtils.normalizePartnerSnapshot({
      'fullName': plan.keep.fullName,
      'fellowship': plan.keep.fellowship,
      'memberId': plan.keep.memberId,
    });

    var moved = 0;
    const chunkSize = 400;
    final toMove = plan.entriesToMove;
    for (var i = 0; i < toMove.length; i += chunkSize) {
      final end = (i + chunkSize < toMove.length) ? i + chunkSize : toMove.length;
      final batch = _firestore.batch();
      for (var j = i; j < end; j++) {
        batch.update(_entries(churchId).doc(toMove[j].id), {
          'partnerId': plan.keep.id,
          'partnerSnapshot': keepSnapshot,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        moved++;
      }
      await batch.commit();
    }

    await _partners(churchId).doc(plan.absorb.id).update({
      'isActive': false,
      'mergedInto': plan.keep.id,
      'mergedBy': actor.uid,
      'mergedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return moved;
  }

  // ------------------------------------------------------------ partner data

  /// Rewrites names and fellowships that are not in the app's title case.
  ///
  /// Only the casing issues — the ones with a proposed value. A missing member
  /// ID or fellowship is a decision for a person, not a repair.
  Future<int> fixPartnerCasing({
    required String churchId,
    required List<PartnerDataIssue> issues,
  }) async {
    final fixable = issues.where((i) => i.isAutoFixable).toList();
    var fixed = 0;
    const chunkSize = 400;

    for (var i = 0; i < fixable.length; i += chunkSize) {
      final end =
          (i + chunkSize < fixable.length) ? i + chunkSize : fixable.length;
      final batch = _firestore.batch();
      for (var j = i; j < end; j++) {
        final issue = fixable[j];
        final patch = <String, dynamic>{
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (issue.suggestedFullName != null) {
          patch['fullName'] = issue.suggestedFullName;
          patch['fullNameLower'] = issue.suggestedFullName!.toLowerCase();
        }
        if (issue.suggestedFellowship != null) {
          patch['fellowship'] = issue.suggestedFellowship;
          patch['fellowshipLower'] = issue.suggestedFellowship!.toLowerCase();
        }
        batch.update(_partners(churchId).doc(issue.partner.id), patch);
        fixed++;
      }
      await batch.commit();
    }
    return fixed;
  }
}

final maintenanceRepositoryProvider = Provider<MaintenanceRepository>(
  (ref) => MaintenanceRepository(ref.watch(firestoreProvider)),
);
