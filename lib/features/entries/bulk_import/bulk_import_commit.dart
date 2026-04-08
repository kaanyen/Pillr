import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/entry_duplicate_utils.dart';
import '../../activity/activity_log_helper.dart';
import '../../arms/domain/partnership_arm.dart';
import '../../auth/domain/church_user.dart';
import '../../partners/domain/partner.dart';
import '../../partners/providers/partners_providers.dart';
import '../../periods/domain/partnership_period.dart';
import '../domain/partnership_entry.dart';
import '../providers/entries_providers.dart';
import 'bulk_import_models.dart';
import 'bulk_import_phone.dart';

class BulkImportCommitResult {
  BulkImportCommitResult({
    required this.entriesCreated,
    required this.partnersCreated,
    required this.entriesApproved,
    required this.rowsSkipped,
    required this.errors,
  });

  final int entriesCreated;
  final int partnersCreated;
  final int entriesApproved;
  final int rowsSkipped;
  final List<String> errors;
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
}) =>
    {
      'partnerId': partner.id,
      'partnerName': partner.fullName,
      'memberId': partner.memberId,
      'amountCedis': amount,
      'partnershipArmId': arm.id,
      'armName': arm.name,
      'partnershipPeriodId': period.id,
      'periodName': period.name,
      'status': 'pending',
      'notes': notes,
      'dateGiven': dateGiven.toIso8601String(),
    };

String _partnerCreateKey(BulkResolvedRow r) =>
    '${normalizePhoneDigits(r.phone)}|${r.fullName.toLowerCase().trim()}|${r.fellowship.toLowerCase().trim()}';

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
}) async {
  final partnersRepo = ref.read(partnersRepositoryProvider);
  final entriesRepo = ref.read(entriesRepositoryProvider);

  final createdPartners = <String, Partner>{};
  final pendingApprovals = <({String entryId, PartnershipEntry entry})>[];
  final batchEntries = <PartnershipEntry>[];
  var partnersCreated = 0;
  var entriesCreated = 0;
  var entriesApproved = 0;
  var skipped = 0;
  final errors = <String>[];

  Partner partnerForRow(BulkResolvedRow r, String partnerId, String memberId) {
    return Partner(
      id: partnerId,
      churchId: churchId,
      memberId: memberId,
      fullName: r.fullName.trim(),
      fellowship: r.fellowship.trim(),
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
        'fullName': r.fullName.trim(),
        'fellowship': r.fellowship.trim(),
      },
    );
    return p;
  }

  for (final r in rows) {
    if (r.isBlocking) {
      skipped++;
      errors.add('Row ${r.sheetRowNumber}: blocked by validation.');
      continue;
    }
    if (r.resolution == PartnerResolutionKind.ambiguous) {
      skipped++;
      errors.add('Row ${r.sheetRowNumber}: ambiguous partner — fix in sheet.');
      continue;
    }

    final armId = r.armId;
    final periodId = r.periodId;
    if (armId == null || periodId == null) {
      skipped++;
      errors.add('Row ${r.sheetRowNumber}: missing arm or period.');
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

    if (period.id != periodId) {
      skipped++;
      errors.add('Row ${r.sheetRowNumber}: period mismatch.');
      continue;
    }

    Partner partner;
    try {
      partner = await resolvePartner(r);
    } catch (e) {
      skipped++;
      errors.add('Row ${r.sheetRowNumber}: partner error — $e');
      continue;
    }

    final candidates = await entriesRepo.fetchEntriesForDuplicateCheck(
      churchId,
      partnerId: partner.id,
      allChurchEntries: allChurchEntries,
      createdByUid: allChurchEntries ? null : staff.uid,
    );
    final combined = [...candidates, ...batchEntries];
    if (hasSimilarPartnershipEntry(
      combined,
      partnerId: partner.id,
      armId: arm.id,
      periodId: period.id,
      amount: r.amountCedis,
    )) {
      skipped++;
      errors.add(
        'Row ${r.sheetRowNumber}: similar entry already exists (±10%) for this partner, arm, and period.',
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
        dateGiven: r.dateGiven,
        notes: r.notes,
      );
      entriesCreated++;

      final entry = await entriesRepo.getEntry(churchId, entryId);
      if (entry != null) {
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
          ),
        );

        if (r.pastorConfirmed && viewerIsPastor) {
          pendingApprovals.add((entryId: entryId, entry: entry));
        }
      }
    } catch (e) {
      skipped++;
      errors.add('Row ${r.sheetRowNumber}: $e');
    }
  }

  if (viewerIsPastor) {
    for (final p in pendingApprovals) {
      try {
        await entriesRepo.approveEntry(
          churchId: churchId,
          entry: p.entry,
          pastor: staff,
        );
        entriesApproved++;
      } catch (e) {
        errors.add('Approve ${p.entryId}: $e');
      }
    }
  }

  ref.invalidate(entriesListProvider);

  return BulkImportCommitResult(
    entriesCreated: entriesCreated,
    partnersCreated: partnersCreated,
    entriesApproved: entriesApproved,
    rowsSkipped: skipped,
    errors: errors,
  );
}
