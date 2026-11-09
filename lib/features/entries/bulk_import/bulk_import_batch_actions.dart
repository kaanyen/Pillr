import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/domain/church_user.dart';
import '../../periods/domain/partnership_period.dart';
import '../../arms/domain/partnership_arm.dart';
import '../data/entries_repository.dart';
import '../providers/entries_providers.dart';
import 'bulk_import_batches.dart';

/// The things you can do to an import after it has landed.
///
/// These sit above both repositories rather than inside either: clearing an
/// import writes to `entries` and to `import_batches`, and neither collection
/// owns the other. Keeping the orchestration here means the batch repository
/// stays a plain store and the entries repository stays unaware that imports
/// exist at all.
class BulkImportBatchActions {
  const BulkImportBatchActions({
    required EntriesRepository entries,
    required BulkImportBatchRepository batches,
  })  : _entries = entries,
        _batches = batches;

  final EntriesRepository _entries;
  final BulkImportBatchRepository _batches;

  /// Reverses every entry an import created.
  ///
  /// Voided rather than deleted, so an import that turned out to be wrong can
  /// be taken out of the totals without erasing what was recorded or who
  /// recorded it. The aggregate trigger unwinds partner, period and goal
  /// totals on the status change, so nothing here touches a total directly.
  ///
  /// Safe to run twice: rows already voided are reported, not re-reversed.
  Future<BulkImportVoidResult> clearBatch({
    required String churchId,
    required String batchId,
    required ChurchUser actor,
    required String reason,
  }) async {
    final rows = await _entries.fetchEntriesForBatch(churchId, batchId);
    final alreadyVoided = rows.where((e) => e.isVoided).length;

    final voided = await _entries.voidEntries(
      churchId: churchId,
      entries: rows,
      actor: actor,
      reason: reason,
    );

    await _batches.markVoided(
      churchId: churchId,
      batchId: batchId,
      byUid: actor.uid,
      byName: actor.fullName,
      voidedCount: alreadyVoided + voided,
    );

    return BulkImportVoidResult(
      voided: voided,
      alreadyVoided: alreadyVoided,
    );
  }

  /// Puts a cleared import back the way it was.
  Future<int> restoreBatch({
    required String churchId,
    required String batchId,
    required ChurchUser actor,
  }) async {
    final rows = await _entries.fetchEntriesForBatch(churchId, batchId);
    final restored = await _entries.restoreEntries(
      churchId: churchId,
      entries: rows,
      actor: actor,
    );
    await _batches.markRestored(
      churchId: churchId,
      batchId: batchId,
      byUid: actor.uid,
      restoredCount: restored,
    );
    return restored;
  }

  /// Moves a whole import to a different period and/or arm.
  ///
  /// The case this exists for is a file imported against the wrong period.
  /// Before this, the only remedy was to remove the import and run it again —
  /// which meant re-doing every manual correction made in the grid.
  ///
  /// Voided rows are left where they are: they count toward nothing, and
  /// moving them would put money back into a period nobody expects it in.
  Future<int> reassignBatch({
    required String churchId,
    required String batchId,
    required ChurchUser actor,
    PartnershipPeriod? period,
    PartnershipArm? arm,
    String? previousPeriodName,
  }) async {
    if (period == null && arm == null) return 0;
    final rows = await _entries.fetchEntriesForBatch(churchId, batchId);

    final moved = await _entries.reassignEntries(
      churchId: churchId,
      entries: rows,
      actor: actor,
      partnershipPeriodId: period?.id,
      periodSnapshot: period == null ? null : {'name': period.name},
      partnershipArmId: arm?.id,
      armSnapshot: arm == null ? null : {'name': arm.name},
    );

    await _batches.markReassigned(
      churchId: churchId,
      batchId: batchId,
      byUid: actor.uid,
      movedCount: moved,
      periodName: period?.name,
      previousPeriodName: previousPeriodName,
    );

    return moved;
  }

  Future<int> undoReassignBatch({
    required String churchId,
    required String batchId,
    required ChurchUser actor,
    required String previousPeriodName,
  }) async {
    final rows = await _entries.fetchEntriesForBatch(churchId, batchId);
    final moved = await _entries.undoReassignEntries(
      churchId: churchId,
      entries: rows,
      actor: actor,
    );
    await _batches.markReassignUndone(
      churchId: churchId,
      batchId: batchId,
      byUid: actor.uid,
      periodName: previousPeriodName,
    );
    return moved;
  }

  Future<int> revertLastEdits({
    required String churchId,
    required String batchId,
    required ChurchUser actor,
  }) async {
    final rows = await _entries.fetchEntriesForBatch(churchId, batchId);
    final reverted = await _entries.revertLastPastorEdits(
      churchId: churchId,
      entries: rows,
      actor: actor,
    );
    await _batches.markEditsReverted(
      churchId: churchId,
      batchId: batchId,
      byUid: actor.uid,
    );
    return reverted;
  }
}

final bulkImportBatchActionsProvider = Provider<BulkImportBatchActions>((ref) {
  return BulkImportBatchActions(
    entries: ref.watch(entriesRepositoryProvider),
    batches: ref.watch(bulkImportBatchRepositoryProvider),
  );
});
