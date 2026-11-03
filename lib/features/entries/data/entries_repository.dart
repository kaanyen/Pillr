import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/money.dart';
import '../../../core/utils/text_case_utils.dart';
import '../../auth/domain/church_user.dart';
import '../../church/domain/exchange_rates.dart';
import '../domain/partnership_entry.dart';

bool _isPastorRole(ChurchUser staff) => staff.role == 'pastor';

/// Status the row had immediately before it was voided.
String statusBeforeVoid(PartnershipEntry e) {
  for (final h in e.editHistory.reversed) {
    final desc = h['changeDescription']?.toString() ?? '';
    if (desc.startsWith('Entry voided')) {
      final prev = h['previousValues'];
      if (prev is Map && prev['status'] is String) {
        return prev['status'] as String;
      }
    }
  }
  return 'approved';
}

class EntriesRepository {
  EntriesRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _entries(String churchId) {
    return _firestore.collection('churches').doc(churchId).collection('entries');
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

  /// Approved entries — the set every ranking is computed from.
  ///
  /// Rankings have always been period-scoped (`LeaderboardRow.fromEntries`
  /// takes a `periodId` and drops everything else), so scoping the *query* the
  /// same way returns the same rows without streaming the church's whole
  /// history to do it. No `orderBy`: every consumer sorts by amount itself.
  ///
  /// [periodId] null ranks across every period, which is what a church with no
  /// active period has always seen. [createdByUid] narrows to one person's
  /// submissions — the rules let staff read the whole church, but staff
  /// rankings have always covered only what they recorded, and a performance
  /// change is the wrong place to widen that.
  Stream<List<PartnershipEntry>> watchApprovedEntriesForRanking(
    String churchId, {
    String? periodId,
    String? createdByUid,
  }) {
    Query<Map<String, dynamic>> q =
        _entries(churchId).where('status', isEqualTo: 'approved');
    if (periodId != null && periodId.isNotEmpty) {
      q = q.where('partnershipPeriodId', isEqualTo: periodId);
    }
    if (createdByUid != null && createdByUid.isNotEmpty) {
      q = q.where('createdBy', isEqualTo: createdByUid);
    }
    return q
        .snapshots()
        .map((snap) => snap.docs.map(PartnershipEntry.fromDoc).toList());
  }

  /// Entries decided since [since], newest decision first.
  ///
  /// Feeds the strip under the review queue. Pending entries carry a null
  /// `reviewedAt`, so the range filter leaves them out without a status clause.
  Stream<List<PartnershipEntry>> watchRecentlyDecided(
    String churchId,
    DateTime since,
  ) {
    return _entries(churchId)
        .where('reviewedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('reviewedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(PartnershipEntry.fromDoc).toList());
  }

  /// Status counts and the approved total, computed by Firestore.
  ///
  /// These drive the dashboard tiles, which never needed the documents — only
  /// four numbers derived from them. As aggregate queries they cost a few
  /// index reads instead of downloading every entry in the church.
  /// [createdByUid] narrows to one person's submissions (the staff view).
  Future<EntryStatusTotals> fetchEntryStatusTotals(
    String churchId, {
    String? createdByUid,
  }) async {
    Query<Map<String, dynamic>> base = _entries(churchId);
    if (createdByUid != null && createdByUid.isNotEmpty) {
      base = base.where('createdBy', isEqualTo: createdByUid);
    }

    final results = await Future.wait([
      base.where('status', isEqualTo: 'pending').count().get(),
      base.where('status', isEqualTo: 'declined').count().get(),
      base
          .where('status', isEqualTo: 'approved')
          .aggregate(count(), sum('amountCedis'))
          .get(),
      base.where('status', isEqualTo: 'voided').count().get(),
    ]);

    return EntryStatusTotals(
      pendingCount: results[0].count ?? 0,
      declinedCount: results[1].count ?? 0,
      approvedCount: results[2].count ?? 0,
      approvedTotalCedis: results[2].getSum('amountCedis') ?? 0,
      voidedCount: results[3].count ?? 0,
    );
  }

  /// Approved giving in [periodId] to any of [armIds], summed by Firestore.
  ///
  /// How a main arm's goal counts its sub-arms: the stored goal total only
  /// moves for the arm an entry was recorded to, so the family's figure is
  /// read from the entries themselves rather than written anywhere.
  Future<double> fetchApprovedCedisForArms(
    String churchId, {
    required String periodId,
    required List<String> armIds,
  }) async {
    if (armIds.isEmpty) return 0;
    var total = 0.0;
    // `whereIn` takes at most 30 values.
    for (var i = 0; i < armIds.length; i += 30) {
      final chunk = armIds.sublist(i, i + 30 > armIds.length ? armIds.length : i + 30);
      final snap = await _entries(churchId)
          .where('partnershipPeriodId', isEqualTo: periodId)
          .where('status', isEqualTo: 'approved')
          .where('partnershipArmId', whereIn: chunk)
          .aggregate(sum('amountCedis'))
          .get();
      total += snap.getSum('amountCedis') ?? 0;
    }
    return total;
  }

  /// One partner's giving history, most recent gift first.
  ///
  /// By `dateGiven` for the same reason the paged lists are: this is a record
  /// of giving, and the date on the row is the date it should sort by.
  Stream<List<PartnershipEntry>> watchPartnerEntries(String churchId, String partnerId) {
    return _entries(churchId)
        .where('partnerId', isEqualTo: partnerId)
        .orderBy('dateGiven', descending: true)
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
  /// [statusFilter] when non-null restricts to `pending` | `approved` |
  /// `declined` | `voided`. [importBatchId] narrows to one import run.
  /// [newestFirst] false = oldest first.
  ///
  /// Ordered by `dateGiven` — when the gift was given — not by `createdAt`,
  /// when somebody typed it in. Those are the same moment for an entry a
  /// pastor records, and they are not for one a staff member submits and a
  /// pastor approves days later: approving does not touch `createdAt`, so
  /// ordering by it filed the newly approved gift back under the day it was
  /// keyed in, below everything entered since and often past the end of the
  /// first page. A pastor reading a giving record wants it under the day of
  /// the gift, which is also the field the monthly view groups by — so the
  /// order the pages arrive in and the order they are read in now agree.
  Future<({
    List<PartnershipEntry> items,
    DocumentSnapshot<Map<String, dynamic>>? lastDoc,
    bool hasMore,
  })> fetchEntriesPage(
    String churchId, {
    required bool allChurchEntries,
    String? createdByUid,
    String? statusFilter,
    String? importBatchId,
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
    if (importBatchId != null && importBatchId.isNotEmpty) {
      q = q.where('importBatchId', isEqualTo: importBatchId);
    }
    q = q.orderBy('dateGiven', descending: newestFirst);
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
    String sourceCurrency = 'GHS',
    double? sourceAmount,
    double? exchangeRateToBase,
    required DateTime dateGiven,
    String? notes,
    String? importBatchId,
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
      ..._currencyFields(
        amountCedis: amountCedis,
        sourceCurrency: sourceCurrency,
        sourceAmount: sourceAmount ?? amountCedis,
        exchangeRateToBase: exchangeRateToBase ?? 1.0,
      ),
      'dateGiven': Timestamp.fromDate(dateGiven),
      'notes': notes?.trim().isEmpty ?? true ? null : notes!.trim(),
      // Which import put this row here, if any. Manual entries carry null.
      'importBatchId': importBatchId,
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
    String sourceCurrency = 'GHS',
    double? sourceAmount,
    double? exchangeRateToBase,
    required DateTime dateGiven,
    String? notes,
  }) async {
    final prev = {
      'amountCedis': existing.amountCedis,
      'sourceCurrency': existing.sourceCurrency,
      'sourceAmount': existing.sourceAmount,
      'exchangeRateToBase': existing.exchangeRateToBase,
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
      ..._currencyFields(
        amountCedis: amountCedis,
        sourceCurrency: sourceCurrency,
        sourceAmount: sourceAmount ?? amountCedis,
        exchangeRateToBase: exchangeRateToBase ?? 1.0,
      ),
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
    await _entries(churchId).doc(entry.id).update(_approvePatch(pastor));
  }

  /// Approves many pending entries in Firestore batches (max 500 ops per batch).
  Future<int> approveEntries({
    required String churchId,
    required List<PartnershipEntry> entries,
    required ChurchUser pastor,
  }) async {
    final pending = entries.where((e) => e.status == 'pending').toList();
    if (pending.isEmpty) return 0;

    const chunkSize = 500;
    var approved = 0;
    final patch = _approvePatch(pastor);

    for (var i = 0; i < pending.length; i += chunkSize) {
      final end = (i + chunkSize < pending.length) ? i + chunkSize : pending.length;
      final batch = _firestore.batch();
      for (var j = i; j < end; j++) {
        batch.update(_entries(churchId).doc(pending[j].id), patch);
        approved++;
      }
      await batch.commit();
    }
    return approved;
  }

  Map<String, dynamic> _approvePatch(ChurchUser pastor) => {
        'status': 'approved',
        'reviewedBy': pastor.uid,
        'reviewedBySnapshot': TextCaseUtils.normalizePersonSnapshot({
          'fullName': pastor.fullName,
        }),
        'reviewedAt': FieldValue.serverTimestamp(),
        'declineReason': null,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Puts an approved or declined entry back on the queue.
  ///
  /// The case this exists for is a decision made in error — the wrong row,
  /// the wrong amount noticed a moment later. Voiding is the other way to
  /// take approved money out; this one says "I have not decided yet."
  Future<void> reopenEntry({
    required String churchId,
    required PartnershipEntry entry,
    required ChurchUser actor,
  }) async {
    if (entry.status != 'approved' && entry.status != 'declined') return;
    final history = List<Map<String, dynamic>>.from(entry.editHistory)
      ..add({
        'editedBy': actor.uid,
        'editedAt': Timestamp.now(),
        'previousValues': {
          'status': entry.status,
          'declineReason': entry.declineReason,
        },
        'changeDescription': entry.status == 'approved'
            ? 'Approval undone'
            : 'Decline undone',
      });
    await _entries(churchId).doc(entry.id).update({
      'status': 'pending',
      'reviewedBy': null,
      'reviewedBySnapshot': null,
      'reviewedAt': null,
      'declineReason': null,
      'updatedAt': FieldValue.serverTimestamp(),
      'editHistory': history,
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
    String sourceCurrency = 'GHS',
    double? sourceAmount,
    double? exchangeRateToBase,
    required DateTime dateGiven,
    String? notes,
  }) async {
    final prev = {
      'amountCedis': existing.amountCedis,
      'sourceCurrency': existing.sourceCurrency,
      'sourceAmount': existing.sourceAmount,
      'exchangeRateToBase': existing.exchangeRateToBase,
      'status': existing.status,
      'partnerId': existing.partnerId,
      'partnerSnapshot': existing.partnerSnapshot,
      'partnershipArmId': existing.partnershipArmId,
      'armSnapshot': existing.armSnapshot,
      'partnershipPeriodId': existing.partnershipPeriodId,
      'periodSnapshot': existing.periodSnapshot,
      'dateGiven': Timestamp.fromDate(existing.dateGiven),
      'notes': existing.notes,
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
      ..._currencyFields(
        amountCedis: amountCedis,
        sourceCurrency: sourceCurrency,
        sourceAmount: sourceAmount ?? amountCedis,
        exchangeRateToBase: exchangeRateToBase ?? 1.0,
      ),
      'dateGiven': Timestamp.fromDate(dateGiven),
      'notes': notes?.trim().isEmpty ?? true ? null : notes!.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      'editHistory': history,
    });
  }

  /// Reverses [entries] without destroying them.
  ///
  /// Voiding is a status change, which is all it needs to be: the aggregate
  /// trigger treats anything that is not `approved` as contributing zero, so
  /// partner, period and goal totals unwind themselves through the same
  /// transactional path an edit or a delete takes. Nothing is removed, so a
  /// receipted entry can still be produced and explained afterwards.
  ///
  /// Already-voided rows are skipped, so voiding twice is a no-op rather than
  /// a second reversal. Returns how many were changed.
  Future<int> voidEntries({
    required String churchId,
    required List<PartnershipEntry> entries,
    required ChurchUser actor,
    required String reason,
  }) async {
    final targets = entries.where((e) => !e.isVoided).toList();
    if (targets.isEmpty) return 0;

    const chunkSize = 450;
    var voided = 0;
    for (var i = 0; i < targets.length; i += chunkSize) {
      final end =
          (i + chunkSize < targets.length) ? i + chunkSize : targets.length;
      final batch = _firestore.batch();
      for (var j = i; j < end; j++) {
        final e = targets[j];
        final history = List<Map<String, dynamic>>.from(e.editHistory)
          ..add({
            'editedBy': actor.uid,
            'editedAt': Timestamp.now(),
            'previousValues': {'status': e.status},
            'changeDescription': 'Entry voided: ${reason.trim()}',
          });
        batch.update(_entries(churchId).doc(e.id), {
          'status': 'voided',
          'voidedBy': actor.uid,
          'voidedAt': FieldValue.serverTimestamp(),
          'voidReason': reason.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
          'editHistory': history,
        });
        voided++;
      }
      await batch.commit();
    }
    return voided;
  }

  /// Puts voided entries back to the state they were in before.
  ///
  /// Voiding is reversible because it is a correction, and corrections get made
  /// in error too. Restoring returns the row to the status it held before the
  /// void (approved or pending), taken from the edit history. Approved rows
  /// go back into totals; pending rows go back to the queue.
  ///
  /// The void stamp is cleared but the edit history keeps the round trip, so
  /// the books still show that it happened.
  Future<int> restoreEntries({
    required String churchId,
    required List<PartnershipEntry> entries,
    required ChurchUser actor,
  }) async {
    final targets = entries.where((e) => e.isVoided).toList();
    if (targets.isEmpty) return 0;

    const chunkSize = 450;
    var restored = 0;
    for (var i = 0; i < targets.length; i += chunkSize) {
      final end =
          (i + chunkSize < targets.length) ? i + chunkSize : targets.length;
      final batch = _firestore.batch();
      for (var j = i; j < end; j++) {
        final e = targets[j];
        final history = List<Map<String, dynamic>>.from(e.editHistory)
          ..add({
            'editedBy': actor.uid,
            'editedAt': Timestamp.now(),
            'previousValues': {
              'status': 'voided',
              'voidReason': e.voidReason,
            },
            'changeDescription': 'Entry restored from voided',
          });
        batch.update(_entries(churchId).doc(e.id), {
          'status': statusBeforeVoid(e),
          'voidedAt': null,
          'voidedBy': null,
          'voidReason': null,
          'updatedAt': FieldValue.serverTimestamp(),
          'editHistory': history,
        });
        restored++;
      }
      await batch.commit();
    }
    return restored;
  }

  /// Every entry an import created, whatever became of it.
  Future<List<PartnershipEntry>> fetchEntriesForBatch(
    String churchId,
    String batchId,
  ) async {
    final snap = await _entries(churchId)
        .where('importBatchId', isEqualTo: batchId)
        .get();
    return snap.docs.map(PartnershipEntry.fromDoc).toList();
  }

  /// Moves every entry in an import to a different period and/or arm.
  ///
  /// The case this exists for is a file imported against the wrong period —
  /// previously only fixable by deleting the batch and importing it again.
  /// Snapshots are rewritten alongside the ids so the rows still read
  /// correctly in a ledger, and the aggregate trigger moves the money from the
  /// old period's totals to the new one.
  Future<int> reassignEntries({
    required String churchId,
    required List<PartnershipEntry> entries,
    required ChurchUser actor,
    String? partnershipPeriodId,
    Map<String, dynamic>? periodSnapshot,
    String? partnershipArmId,
    Map<String, dynamic>? armSnapshot,
  }) async {
    if (partnershipPeriodId == null && partnershipArmId == null) return 0;
    // A voided row is settled; moving it would revive money nobody counted.
    final targets = entries.where((e) => !e.isVoided).toList();
    if (targets.isEmpty) return 0;

    final patch = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
    if (partnershipPeriodId != null) {
      patch['partnershipPeriodId'] = partnershipPeriodId;
      if (periodSnapshot != null) {
        patch['periodSnapshot'] =
            TextCaseUtils.normalizeNamedSnapshot(periodSnapshot);
      }
    }
    if (partnershipArmId != null) {
      patch['partnershipArmId'] = partnershipArmId;
      if (armSnapshot != null) {
        patch['armSnapshot'] = TextCaseUtils.normalizeNamedSnapshot(armSnapshot);
      }
    }

    const chunkSize = 450;
    var moved = 0;
    for (var i = 0; i < targets.length; i += chunkSize) {
      final end =
          (i + chunkSize < targets.length) ? i + chunkSize : targets.length;
      final batch = _firestore.batch();
      for (var j = i; j < end; j++) {
        final e = targets[j];
        final history = List<Map<String, dynamic>>.from(e.editHistory)
          ..add({
            'editedBy': actor.uid,
            'editedAt': Timestamp.now(),
            'previousValues': {
              'partnershipPeriodId': e.partnershipPeriodId,
              'periodSnapshot': e.periodSnapshot,
              'partnershipArmId': e.partnershipArmId,
              'armSnapshot': e.armSnapshot,
            },
            'changeDescription': 'Moved with import',
          });
        batch.update(_entries(churchId).doc(e.id), {
          ...patch,
          'editHistory': history,
        });
        moved++;
      }
      await batch.commit();
    }
    return moved;
  }

  /// Puts each row back to the period and arm it had before the last import move.
  Future<int> undoReassignEntries({
    required String churchId,
    required List<PartnershipEntry> entries,
    required ChurchUser actor,
  }) async {
    var moved = 0;
    const chunkSize = 450;
    for (var i = 0; i < entries.length; i += chunkSize) {
      final end =
          (i + chunkSize < entries.length) ? i + chunkSize : entries.length;
      final batch = _firestore.batch();
      var ops = 0;
      for (var j = i; j < end; j++) {
        final e = entries[j];
        Map<String, dynamic>? prev;
        for (final h in e.editHistory.reversed) {
          if (h['changeDescription'] == 'Moved with import') {
            final raw = h['previousValues'];
            if (raw is Map) prev = Map<String, dynamic>.from(raw);
            break;
          }
        }
        if (prev == null) continue;
        final history = List<Map<String, dynamic>>.from(e.editHistory)
          ..add({
            'editedBy': actor.uid,
            'editedAt': Timestamp.now(),
            'previousValues': {
              'partnershipPeriodId': e.partnershipPeriodId,
              'periodSnapshot': e.periodSnapshot,
              'partnershipArmId': e.partnershipArmId,
              'armSnapshot': e.armSnapshot,
            },
            'changeDescription': 'Import move undone',
          });
        batch.update(_entries(churchId).doc(e.id), {
          if (prev['partnershipPeriodId'] != null)
            'partnershipPeriodId': prev['partnershipPeriodId'],
          if (prev['periodSnapshot'] != null)
            'periodSnapshot': prev['periodSnapshot'],
          if (prev['partnershipArmId'] != null)
            'partnershipArmId': prev['partnershipArmId'],
          if (prev['armSnapshot'] != null) 'armSnapshot': prev['armSnapshot'],
          'updatedAt': FieldValue.serverTimestamp(),
          'editHistory': history,
        });
        ops++;
        moved++;
      }
      if (ops > 0) await batch.commit();
    }
    return moved;
  }

  /// Reverts the last pastor edit on each entry, using the values stored
  /// on that history line.
  Future<int> revertLastPastorEdits({
    required String churchId,
    required List<PartnershipEntry> entries,
    required ChurchUser actor,
  }) async {
    var reverted = 0;
    const chunkSize = 450;
    for (var i = 0; i < entries.length; i += chunkSize) {
      final end =
          (i + chunkSize < entries.length) ? i + chunkSize : entries.length;
      final batch = _firestore.batch();
      var ops = 0;
      for (var j = i; j < end; j++) {
        final e = entries[j];
        if (e.editHistory.isEmpty) continue;
        final last = e.editHistory.last;
        if (last['changeDescription'] != 'Pastor edited entry') continue;
        final raw = last['previousValues'];
        if (raw is! Map) continue;
        final prev = Map<String, dynamic>.from(raw);
        final history = List<Map<String, dynamic>>.from(e.editHistory)
          ..add({
            'editedBy': actor.uid,
            'editedAt': Timestamp.now(),
            'previousValues': {
              'amountCedis': e.amountCedis,
              'partnerId': e.partnerId,
              'status': e.status,
            },
            'changeDescription': 'Pastor edit reverted',
          });
        batch.update(_entries(churchId).doc(e.id), {
          if (prev['partnerId'] != null) 'partnerId': prev['partnerId'],
          if (prev['partnerSnapshot'] != null)
            'partnerSnapshot': prev['partnerSnapshot'],
          if (prev['partnershipArmId'] != null)
            'partnershipArmId': prev['partnershipArmId'],
          if (prev['armSnapshot'] != null) 'armSnapshot': prev['armSnapshot'],
          if (prev['partnershipPeriodId'] != null)
            'partnershipPeriodId': prev['partnershipPeriodId'],
          if (prev['periodSnapshot'] != null)
            'periodSnapshot': prev['periodSnapshot'],
          if (prev['amountCedis'] != null) 'amountCedis': prev['amountCedis'],
          if (prev['sourceCurrency'] != null)
            'sourceCurrency': prev['sourceCurrency'],
          if (prev['sourceAmount'] != null) 'sourceAmount': prev['sourceAmount'],
          if (prev['exchangeRateToBase'] != null)
            'exchangeRateToBase': prev['exchangeRateToBase'],
          if (prev['dateGiven'] != null) 'dateGiven': prev['dateGiven'],
          'notes': prev['notes'],
          'updatedAt': FieldValue.serverTimestamp(),
          'editHistory': history,
        });
        ops++;
        reverted++;
      }
      if (ops > 0) await batch.commit();
    }
    return reverted;
  }

  Future<void> deleteEntry({
    required String churchId,
    required String entryId,
  }) async {
    await _entries(churchId).doc(entryId).delete();
  }

  /// Re-applies current [rates] to every entry stored in a foreign currency.
  /// Uses each row's saved [sourceAmount]; only updates when GHS or rate changes.
  Future<RecalculateForeignEntriesResult> recalculateForeignEntries({
    required String churchId,
    required ChurchExchangeRates rates,
  }) async {
    final snap = await _entries(churchId)
        .where(
          'sourceCurrency',
          whereIn: SelectableCurrency.all
              .where((c) => c != BaseCurrency.code)
              .toList(),
        )
        .get();

    var updated = 0;
    var unchanged = 0;

    const chunkSize = 450;
    for (var i = 0; i < snap.docs.length; i += chunkSize) {
      final batch = _firestore.batch();
      var batchOps = 0;
      final end = (i + chunkSize < snap.docs.length) ? i + chunkSize : snap.docs.length;
      for (var j = i; j < end; j++) {
        final doc = snap.docs[j];
        final data = doc.data();
        final sourceCurrency = data['sourceCurrency'] as String?;
        final sourceAmount = (data['sourceAmount'] as num?)?.toDouble();
        if (sourceCurrency == null || sourceAmount == null) continue;

        final conversion = rates.convert(
          sourceAmount: sourceAmount,
          sourceCurrency: sourceCurrency,
        );
        final prevCedis = (data['amountCedis'] as num?)?.toDouble();
        final prevRate = (data['exchangeRateToBase'] as num?)?.toDouble();
        if (prevCedis == conversion.amountBase &&
            prevRate == conversion.exchangeRateToBase) {
          unchanged++;
          continue;
        }

        batch.update(doc.reference, {
          ..._currencyFields(
            amountCedis: conversion.amountBase,
            sourceCurrency: conversion.sourceCurrency,
            sourceAmount: conversion.sourceAmount,
            exchangeRateToBase: conversion.exchangeRateToBase,
          ),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        batchOps++;
        updated++;
      }
      if (batchOps > 0) await batch.commit();
    }

    return RecalculateForeignEntriesResult(
      scanned: snap.docs.length,
      updated: updated,
      unchanged: unchanged,
    );
  }
}

/// What the dashboard tiles need, without the documents behind them.
class EntryStatusTotals {
  const EntryStatusTotals({
    required this.pendingCount,
    required this.approvedCount,
    required this.declinedCount,
    required this.approvedTotalCedis,
    this.voidedCount = 0,
  });

  static const empty = EntryStatusTotals(
    pendingCount: 0,
    approvedCount: 0,
    declinedCount: 0,
    approvedTotalCedis: 0,
  );

  final int pendingCount;
  final int approvedCount;
  final int declinedCount;
  final double approvedTotalCedis;

  /// Reversed after the fact. Counted so the tiles still add up to the
  /// collection, but it contributes nothing to [approvedTotalCedis].
  final int voidedCount;

  int get totalEntries =>
      pendingCount + approvedCount + declinedCount + voidedCount;
}

class RecalculateForeignEntriesResult {
  const RecalculateForeignEntriesResult({
    required this.scanned,
    required this.updated,
    required this.unchanged,
  });

  final int scanned;
  final int updated;
  final int unchanged;
}

/// The money fields of an entry, in whole pesewas.
///
/// Every write of an amount goes through here, so nothing can store a figure
/// finer than the smallest coin: an entry holding ₵416.625 is counted as
/// ₵416.63 by the aggregate trigger and as ₵416.625 by the totals audit's
/// recount, and the difference reads as drift no repair can settle.
Map<String, dynamic> _currencyFields({
  required double amountCedis,
  required String sourceCurrency,
  required double sourceAmount,
  required double exchangeRateToBase,
}) =>
    {
      'amountCedis': fromPesewas(toPesewas(amountCedis)),
      'sourceCurrency': sourceCurrency.toUpperCase(),
      'sourceAmount': fromPesewas(toPesewas(sourceAmount)),
      'exchangeRateToBase': exchangeRateToBase,
    };
