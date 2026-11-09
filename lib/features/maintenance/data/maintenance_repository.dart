import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money.dart';
import '../../../core/extensions/async_value_ext.dart';
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
  MaintenanceRepository(this._firestore, {this.onlyCreatedBy});

  final FirebaseFirestore _firestore;

  /// A staff member's uid: checks over entries cover only the ones they
  /// recorded, which is all they can read. Null for pastors.
  final String? onlyCreatedBy;

  Query<Map<String, dynamic>> _entryList(String churchId) => onlyCreatedBy == null
      ? _entries(churchId)
      : _entries(churchId).where('createdBy', isEqualTo: onlyCreatedBy);

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
          _entryList(churchId).orderBy(FieldPath.documentId).limit(500);
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
    // Stored totals live in their own pastor-only records.
    Future<Map<String, Map<String, dynamic>>> totals(String col) async {
      final snap = await _firestore.collection('churches').doc(churchId).collection(col).get();
      return {for (final d in snap.docs) d.id: d.data()};
    }
    final partnerTotals = await totals('partner_totals');
    final periodTotals = await totals('period_totals');
    double cedisOf(Map<String, dynamic>? m) => m == null
        ? 0
        : storedTotalCedis(m, pesewasKey: 'totalApprovedPesewas', cedisKey: 'totalApprovedAmount');
    int countOf(Map<String, dynamic>? m) => ((m?['entryCount'] ?? 0) as num).toInt();

    final partnerDrift = findTotalsDrift(
      kind: TotalsDriftKind.partner,
      stored: [
        for (final p in partners)
          StoredTotal(
            id: p.id,
            name: p.fullName,
            totalApprovedAmount: cedisOf(partnerTotals[p.id]),
            entryCount: countOf(partnerTotals[p.id]),
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
            totalApprovedAmount: cedisOf(periodTotals[d.id]),
            entryCount: countOf(periodTotals[d.id]),
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
        final church = _firestore.collection('churches').doc(churchId);
        final ref = d.kind == TotalsDriftKind.partner
            ? church.collection('partner_totals').doc(d.id)
            : church.collection('period_totals').doc(d.id);
        batch.set(ref, {
          'totalApprovedAmount': d.expected,
          'totalApprovedPesewas': d.expectedPesewas,
          'entryCount': d.expectedCount,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
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
    final results = await Future.wait([
      allPartners(churchId),
      dismissedDuplicatePairs(churchId),
    ]);
    return findDuplicatePartners(
      results[0] as List<Partner>,
      dismissed: results[1] as Set<String>,
    );
  }

  CollectionReference<Map<String, dynamic>> _dismissals(String churchId) =>
      _firestore.collection('churches/$churchId/duplicate_dismissals');

  /// Pairs a person checked and marked as two different people.
  Future<Set<String>> dismissedDuplicatePairs(String churchId) async {
    final snap = await _dismissals(churchId).get();
    return {for (final d in snap.docs) d.id};
  }

  Future<void> dismissDuplicatePair({
    required String churchId,
    required DuplicatePartnerPair pair,
    required String uid,
  }) async {
    await _dismissals(churchId).doc(pair.key).set({
      'a': pair.a.id,
      'b': pair.b.id,
      'aName': pair.a.fullName,
      'bName': pair.b.fullName,
      'reason': pair.reason,
      'dismissedBy': uid,
      'dismissedAt': FieldValue.serverTimestamp(),
    });
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
          await _entryList(churchId).where('partnerId', isEqualTo: id).get();
      out.addAll(snap.docs.map(PartnershipEntry.fromDoc));
    }
    return out;
  }

  // ------------------------------------------------------------------ merges
  //
  // Merging two partners runs on the server: RecordOpsRepository.partnerMerge.
  // It records every entry it moves, so the merge can be undone.

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
  (ref) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    return MaintenanceRepository(
      ref.watch(firestoreProvider),
      onlyCreatedBy: idx != null && idx.isStaff ? idx.uid : null,
    );
  },
);
