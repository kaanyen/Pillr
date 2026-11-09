import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/entry_duplicate_utils.dart';
import '../../../core/utils/text_case_utils.dart';
import '../../activity/activity_log_helper.dart';
import '../../arms/domain/partnership_arm.dart';
import '../../auth/domain/church_user.dart';
import '../../partners/domain/partner.dart';
import '../../partners/providers/partners_providers.dart';
import '../../periods/domain/partnership_period.dart';
import '../domain/partnership_entry.dart';
import '../providers/entries_providers.dart';
import 'bulk_import_batches.dart';
import 'bulk_import_models.dart';
import 'bulk_import_phone.dart';
import '../../../core/errors/plain_error.dart';

class BulkImportCommitResult {
  BulkImportCommitResult({
    required this.entriesCreated,
    required this.partnersCreated,
    required this.entriesApproved,
    required this.rowsSkipped,
    required this.errors,
    required this.batchId,
    required this.totalCedis,
    required this.rowsAttempted,
    this.incomplete = false,
  });

  final int entriesCreated;
  final int partnersCreated;
  final int entriesApproved;
  final int rowsSkipped;
  final List<String> errors;

  /// Stamped on every entry this run created, so the import can be found —
  /// and undone — afterwards.
  final String batchId;
  final double totalCedis;
  final int rowsAttempted;
  final bool incomplete;

  bool get isPartial =>
      incomplete || (entriesCreated > 0 && rowsSkipped > 0);
}

Map<String, dynamic> _partnerSnapshot(Partner p) => {
  'memberId': p.memberId,
  'fullName': p.fullName,
  'fellowship': p.fellowship,
  'email': p.email,
  'phone': p.phone,
};

Map<String, dynamic> _armSnapshot(PartnershipArm a) => {'name': a.name};

Map<String, dynamic> _periodSnapshot(PartnershipPeriod p) => {
  'name': p.name,
  'startDate': Timestamp.fromDate(p.startDate),
  'endDate': Timestamp.fromDate(p.endDate),
};

Map<String, dynamic> _afterEntryValues({
  required Partner partner,
  required PartnershipArm arm,
  required PartnershipPeriod period,
  required double amount,
  required DateTime dateGiven,
  required String? notes,
  required String status,
}) => {
  'partnerId': partner.id,
  'partnerName': partner.fullName,
  'memberId': partner.memberId,
  'amountCedis': amount,
  'partnershipArmId': arm.id,
  'armName': arm.name,
  'partnershipPeriodId': period.id,
  'periodName': period.name,
  'status': status,
  'notes': notes,
  'dateGiven': dateGiven.toIso8601String(),
};

String _partnerCreateKey(BulkResolvedRow r) =>
    '${normalizePhoneDigits(r.phone)}|${r.fullName.toLowerCase().trim()}|${r.fellowship.toLowerCase().trim()}';

typedef BulkImportCommitProgressCallback =
    void Function(int current, int total, String message);

Future<BulkImportCommitResult> commitBulkImport({
  required WidgetRef ref,
  required String churchId,
  required ChurchUser staff,
  required String churchDisplayName,
  required List<BulkResolvedRow> rows,
  required List<PartnershipArm> arms,
  required PartnershipPeriod period,
  required bool allChurchEntries,
  required bool viewerIsPastor,
  required Set<int> duplicateAcknowledgedSheetRows,
  required String fileName,
  /// Who put the sheet together, if the person importing said.
  String? preparedBy,
  Map<String, List<PartnershipEntry>>? duplicateCache,
  BulkImportCommitProgressCallback? onProgress,
}) async {
  final partnersRepo = ref.read(partnersRepositoryProvider);
  final entriesRepo = ref.read(entriesRepositoryProvider);
  final batchesRepo = ref.read(bulkImportBatchRepositoryProvider);
  final batchId = batchesRepo.newBatchId(churchId);
  var totalCedis = 0.0;

  final createdPartners = <String, Partner>{};
  final batchEntries = <PartnershipEntry>[];
  final partnerEntryCache = Map<String, List<PartnershipEntry>>.from(
    duplicateCache ?? const {},
  );
  var partnersCreated = 0;
  var entriesCreated = 0;
  var entriesApproved = 0;
  var skipped = 0;
  var incomplete = false;
  final errors = <String>[];

  await batchesRepo.begin(
    churchId: churchId,
    batchId: batchId,
    fileName: fileName,
    periodName: period.name,
    staff: staff,
    preparedBy: preparedBy,
  );

  Partner partnerForRow(BulkResolvedRow r, String partnerId, String memberId) {
    return Partner(
      id: partnerId,
      churchId: churchId,
      memberId: memberId,
      fullName: TextCaseUtils.toTitleCase(r.fullName),
      fellowship: TextCaseUtils.toTitleCase(r.fellowship),
      email: r.email.trim().isEmpty ? null : r.email.trim(),
      phone: r.phone.trim().isEmpty ? null : r.phone.trim(),
      isActive: true,
      totalApprovedAmount: 0,
      entryCount: 0,
      createdBy: staff.uid,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  Future<Partner> resolvePartner(BulkResolvedRow r) async {
    if (r.partnerId != null && r.partner != null) {
      return r.partner!;
    }
    final key = _partnerCreateKey(r);
    final existing = createdPartners[key];
    if (existing != null) return existing;

    final created = await partnersRepo.createPartner(
      churchId: churchId,
      uid: staff.uid,
      fullName: r.fullName,
      fellowship: r.fellowship,
      email: r.email,
      phone: r.phone,
      churchDisplayName: churchDisplayName,
    );
    partnersCreated++;
    final p = partnerForRow(r, created.id, created.memberId);
    createdPartners[key] = p;
    await logPillrActivity(
      ref,
      churchId: churchId,
      action: 'partner.create',
      entityType: 'partner',
      entityId: created.id,
      entitySnapshot: {
        'memberId': created.memberId,
        'fullName': TextCaseUtils.toTitleCase(r.fullName),
        'fellowship': TextCaseUtils.toTitleCase(r.fellowship),
      },
    );
    return p;
  }

  final processable = rows
      .where(
        (r) => !r.isBlocking && r.resolution != PartnerResolutionKind.ambiguous,
      )
      .length;
  var processed = 0;
  onProgress?.call(
    0,
    processable > 0 ? processable : rows.length,
    'Starting import…',
  );

  try {
  for (final r in rows) {
    if (r.isBlocking) {
      skipped++;
      errors.add('Row ${r.sheetRowNumber}: blocked by validation.');
      continue;
    }
    if (r.resolution == PartnerResolutionKind.ambiguous) {
      skipped++;
      errors.add(
        'Row ${r.sheetRowNumber}: ambiguous partner — pick the right person.',
      );
      continue;
    }

    final armId = r.armId;
    if (armId == null) {
      skipped++;
      errors.add('Row ${r.sheetRowNumber}: missing arm.');
      continue;
    }

    PartnershipArm? arm;
    for (final a in arms) {
      if (a.id == armId) {
        arm = a;
        break;
      }
    }
    if (arm == null) {
      skipped++;
      errors.add('Row ${r.sheetRowNumber}: arm not found.');
      continue;
    }

    Partner partner;
    try {
      partner = await resolvePartner(r);
    } catch (e) {
      skipped++;
      errors.add('Row ${r.sheetRowNumber}: partner error. ${plainError(e)}');
      continue;
    }

    var candidates = partnerEntryCache[partner.id];
    if (candidates == null) {
      candidates = await entriesRepo.fetchEntriesForDuplicateCheck(
        churchId,
        partnerId: partner.id,
        allChurchEntries: allChurchEntries,
        createdByUid: allChurchEntries ? null : staff.uid,
      );
      partnerEntryCache[partner.id] = candidates;
    }
    final combined = [...candidates, ...batchEntries];
    final similar = hasSimilarPartnershipEntryWithSameDate(
      combined,
      partnerId: partner.id,
      armId: arm.id,
      periodId: period.id,
      amount: r.amountCedis,
      dateGiven: r.dateGiven,
    );
    if (similar && !duplicateAcknowledgedSheetRows.contains(r.sheetRowNumber)) {
      skipped++;
      errors.add(
        'Row ${r.sheetRowNumber}: similar entry already exists for this date, partner, arm, and period (±10% amount).',
      );
      continue;
    }

    try {
      final entryId = await entriesRepo.createEntry(
        churchId: churchId,
        staff: staff,
        partnerId: partner.id,
        partnerSnapshot: _partnerSnapshot(partner),
        partnershipArmId: arm.id,
        armSnapshot: _armSnapshot(arm),
        partnershipPeriodId: period.id,
        periodSnapshot: _periodSnapshot(period),
        amountCedis: r.amountCedis,
        sourceCurrency: r.sourceCurrency,
        sourceAmount: r.sourceAmount ?? r.amountCedis,
        exchangeRateToBase: r.exchangeRateToBase,
        dateGiven: r.dateGiven,
        notes: r.notes,
        importBatchId: batchId,
      );
      entriesCreated++;
      totalCedis += r.amountCedis;

      // Built here rather than read back. The row it would fetch is the row we
      // just wrote, and on an eight-hundred-row sheet that read-after-write is
      // eight hundred round trips for information we already hold.
      final entry = PartnershipEntry(
        id: entryId,
        churchId: churchId,
        partnerId: partner.id,
        partnerSnapshot: _partnerSnapshot(partner),
        partnershipArmId: arm.id,
        armSnapshot: _armSnapshot(arm),
        partnershipPeriodId: period.id,
        periodSnapshot: _periodSnapshot(period),
        amountCedis: r.amountCedis,
        dateGiven: r.dateGiven,
        notes: r.notes,
        status: viewerIsPastor ? 'approved' : 'pending',
        createdBy: staff.uid,
        createdBySnapshot: {'fullName': staff.fullName, 'role': staff.role},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        reviewedBy: viewerIsPastor ? staff.uid : null,
        reviewedBySnapshot: viewerIsPastor
            ? {'fullName': staff.fullName}
            : null,
        reviewedAt: viewerIsPastor ? DateTime.now() : null,
        declineReason: null,
        editHistory: const [],
      );
      {
        batchEntries.add(entry);
        await logPillrActivity(
          ref,
          churchId: churchId,
          action: 'entry.create',
          entityType: 'entry',
          entityId: entryId,
          entitySnapshot: _afterEntryValues(
            partner: partner,
            arm: arm,
            period: period,
            amount: r.amountCedis,
            dateGiven: r.dateGiven,
            notes: r.notes,
            status: viewerIsPastor ? 'approved' : 'pending',
          ),
        );

        if (viewerIsPastor) {
          entriesApproved++;
        }
      }
    } catch (e) {
      skipped++;
      errors.add('Row ${r.sheetRowNumber}. ${plainError(e)}');
    }

    processed++;
    onProgress?.call(
      processed,
      processable > 0 ? processable : rows.length,
      [
        'Row ${r.sheetRowNumber}',
        if (r.fullName.isNotEmpty) r.fullName,
        '₵${r.amountCedis.toStringAsFixed(2)}',
        if (r.armName.isNotEmpty) r.armName,
        if (r.resolution == PartnerResolutionKind.createNew)
          'new partner${r.fellowship.isEmpty ? '' : ', added to ${r.fellowship}'}',
      ].join(' · '),
    );
  }
  } catch (e) {
    incomplete = true;
    errors.add(
      'Stopped after $entriesCreated of ${rows.length} rows. ${plainError(e)}',
    );
  }

  try {
    await batchesRepo.finish(
      churchId: churchId,
      batchId: batchId,
      entryCount: entriesCreated,
      partnersCreated: partnersCreated,
      totalCedis: totalCedis,
      skippedCount: skipped,
    );
  } catch (e) {
    incomplete = true;
    errors.add('The import recorded $entriesCreated entries but could not '
        'close the batch record. ${plainError(e)}');
  }

  if (entriesCreated > 0 || skipped > 0) {
    await logPillrActivity(
      ref,
      churchId: churchId,
      action: 'import.commit',
      entityType: 'import_batch',
      entityId: batchId,
      entitySnapshot: {
        'fileName': fileName,
        'periodName': period.name,
        'entryCount': entriesCreated,
        'partnersCreated': partnersCreated,
        'skippedCount': skipped,
        'totalCedis': totalCedis,
      },
    );
  }

  ref.invalidate(rankingEntriesProvider);
  invalidateEntryDerivedData(ref);

  return BulkImportCommitResult(
    entriesCreated: entriesCreated,
    partnersCreated: partnersCreated,
    entriesApproved: entriesApproved,
    rowsSkipped: skipped,
    errors: errors,
    batchId: batchId,
    totalCedis: totalCedis,
    rowsAttempted: rows.length,
    incomplete: incomplete,
  );
}
