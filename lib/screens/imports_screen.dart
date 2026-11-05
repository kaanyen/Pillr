import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/notifications/sel_notice.dart';
import '../core/utils/date_utils.dart';
import '../design/seline.dart';
import '../features/arms/domain/partnership_arm.dart';
import '../features/arms/providers/arms_providers.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/activity/activity_log_helper.dart';
import '../features/entries/bulk_import/bulk_import_batch_actions.dart';
import '../features/entries/bulk_import/bulk_import_batches.dart';
import '../features/entries/bulk_import/bulk_import_history_provider.dart';
import '../features/entries/providers/entries_providers.dart';
import '../features/periods/domain/partnership_period.dart';
import '../features/periods/providers/periods_providers.dart';

/// Imports — every run of the importer, and what can still be done about it.
///
/// An import used to leave almost no trace: five recent runs in a footer on the
/// import screen, and no way to find one afterwards. Sixty-seven entries would
/// land among eight hundred with nothing to say they arrived together, so a
/// file imported against the wrong period could be neither found nor undone.
///
/// This is the third Records view, beside the ledger and the monthly rollup —
/// the same records, asked about a different way: *what did this file do?*
class ImportsScreen extends ConsumerStatefulWidget {
  const ImportsScreen({super.key});

  @override
  ConsumerState<ImportsScreen> createState() => _ImportsScreenState();
}

class _ImportsScreenState extends ConsumerState<ImportsScreen> {
  final _scrollController = ScrollController();
  String? _busyBatchId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 320) {
      ref.read(importHistoryProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(importHistoryProvider);
    final money = ref.watch(churchMoneyFormatProvider);
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final canManage = (idx?.isPastor ?? false) || (idx?.isAdmin ?? false);

    return SelPageBody(
      controller: _scrollController,
      onRefresh: () => ref.read(importHistoryProvider.notifier).refresh(),
      children: [
        SelPageTitle(
          title: 'Imports',
          subtitle: 'Every spreadsheet brought into Pillr, and what it created.',
          actions: [
            SelButton(
              label: 'Records',
              icon: LucideIcons.list,
              kind: SelButtonKind.quiet,
              onPressed: () => context.go('/records'),
            ),
            const SizedBox(width: SelSpace.x2),
            SelButton.cyan(
              label: 'New import',
              icon: LucideIcons.upload,
              onPressed: () => context.go('/entries/bulk-import'),
            ),
          ],
        ),

        if (state.error != null) ...[
          SelError(
            message: state.error!,
            onRetry: () => ref.read(importHistoryProvider.notifier).refresh(),
          ),
          const SizedBox(height: SelSpace.x4),
        ],

        if (state.loading)
          const SelCard(child: SelSkeletonRows())
        else if (state.batches.isEmpty)
          const SelCard(
            child: SelEmpty(
              title: 'Nothing imported yet',
              message:
                  'When you bring a spreadsheet in, the run is recorded here so '
                  'you can find it, name it, or take it back.',
              icon: LucideIcons.upload,
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final b in state.batches) ...[
                _BatchCard(
                  batch: b,
                  money: money,
                  canManage: canManage,
                  busy: _busyBatchId == b.id,
                  onOpenRows: () => context.go('/records?import=${b.id}'),
                  onEdit: () => context.go('/records/imports/${b.id}/edit'),
                  canEdit: idx?.isPastor ?? false,
                  onRename: () => _rename(b),
                  onReassign: () => _reassign(b),
                  onClear: () => _clear(b),
                  onUndo: () => _undo(b),
                  onRestore: () => _restore(b),
                  onUndoMove: () => _undoMove(b),
                  onUndoRename: () => _undoRename(b),
                  onRevertEdits: () => _revertEdits(b),
                ),
                const SizedBox(height: SelSpace.x3),
              ],
              if (state.loadingMore)
                const Padding(
                  padding: EdgeInsets.only(top: SelSpace.x4),
                  child: Center(
                    child: SizedBox(
                      height: 18,
                      width: 18,
                      child: PillrLoader(size: 20),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  // ------------------------------------------------------------------ actions

  Future<void> _withBusy(String batchId, Future<void> Function() run) async {
    if (_busyBatchId != null) return;
    setState(() => _busyBatchId = batchId);
    try {
      await run();
    } catch (e) {
      if (mounted) selNotice(context, '$e', kind: SelNoticeKind.error);
    } finally {
      if (mounted) setState(() => _busyBatchId = null);
    }
  }

  Future<void> _rename(BulkImportBatch b) async {
    final result = await showDialog<({String label, String note})>(
      context: context,
      builder: (_) => _RenameDialog(batch: b),
    );
    if (result == null) return;

    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null) return;

    await _withBusy(b.id, () async {
      await ref.read(bulkImportBatchRepositoryProvider).rename(
            churchId: idx.churchId,
            batchId: b.id,
            label: result.label,
            note: result.note,
            previousLabel: b.label ?? b.fileName,
            previousNote: b.note,
            writePrevious: true,
          );
      await logPillrActivity(
        ref,
        churchId: idx.churchId,
        action: 'import.rename',
        entityType: 'import_batch',
        entityId: b.id,
        entitySnapshot: {
          'label': result.label,
          'fileName': b.fileName,
        },
        metadata: {
          'previousLabel': b.label,
          'previousNote': b.note,
        },
      );
      await ref.read(importHistoryProvider.notifier).refresh();
      if (mounted) selNotice(context, 'Import renamed. You can undo the name.');
    });
  }

  Future<void> _reassign(BulkImportBatch b) async {
    final periods = ref.read(periodsStreamProvider).valueOrNull ?? const [];
    final arms = ref.read(armsStreamProvider).valueOrNull ?? const [];
    if (periods.isEmpty && arms.isEmpty) return;

    final choice = await showDialog<({PartnershipPeriod? period, PartnershipArm? arm})>(
      context: context,
      builder: (_) => _ReassignDialog(batch: b, periods: periods, arms: arms),
    );
    if (choice == null) return;
    if (choice.period == null && choice.arm == null) return;

    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    final actor = ref.read(churchUserProfileProvider).valueOrNull;
    if (idx == null || actor == null) return;

    await _withBusy(b.id, () async {
      final moved = await ref.read(bulkImportBatchActionsProvider).reassignBatch(
            churchId: idx.churchId,
            batchId: b.id,
            actor: actor,
            period: choice.period,
            arm: choice.arm,
            previousPeriodName: b.periodName,
          );
      await logPillrActivity(
        ref,
        churchId: idx.churchId,
        action: 'import.reassign',
        entityType: 'import_batch',
        entityId: b.id,
        entitySnapshot: {
          'periodName': choice.period?.name ?? b.periodName,
          'armName': choice.arm?.name,
          'moved': moved,
        },
        metadata: {'previousPeriodName': b.periodName},
      );
      invalidateEntryDerivedData(ref);
      ref.invalidate(rankingEntriesProvider);
      await ref.read(importHistoryProvider.notifier).refresh();
      if (mounted) {
        selNotice(
          context,
          moved == 0
              ? 'Nothing to move — every row in this import is already voided.'
              : 'Moved $moved ${moved == 1 ? "entry" : "entries"}.',
        );
      }
    });
  }

  Future<void> _clear(BulkImportBatch b) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ClearDialog(batch: b),
    );
    if (reason == null || reason.trim().isEmpty) return;

    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    final actor = ref.read(churchUserProfileProvider).valueOrNull;
    if (idx == null || actor == null) return;

    await _withBusy(b.id, () async {
      final result = await ref.read(bulkImportBatchActionsProvider).clearBatch(
            churchId: idx.churchId,
            batchId: b.id,
            actor: actor,
            reason: reason,
          );
      invalidateEntryDerivedData(ref);
      ref.invalidate(rankingEntriesProvider);
      await ref.read(importHistoryProvider.notifier).refresh();
      if (mounted) {
        selNotice(
          context,
          result.voided == 0
              ? 'This import was already cleared.'
              : 'Voided ${result.voided} '
                  '${result.voided == 1 ? "entry" : "entries"}. '
                  'They stay on the books but count toward nothing. '
                  'Restore them from this card if that was a mistake.',
        );
      }
      await logPillrActivity(
        ref,
        churchId: idx.churchId,
        action: 'import.void',
        entityType: 'import_batch',
        entityId: b.id,
        entitySnapshot: {
          'fileName': b.fileName,
          'voided': result.voided,
          'reason': reason,
        },
      );
    });
  }

  Future<void> _undo(BulkImportBatch b) async {
    final ok = await selConfirm(
      context,
      title: 'Undo this import?',
      message:
          'Removes the entries from ${b.displayName} that are still waiting '
          'on a decision. Anything already approved stays — use Clear to take '
          'approved money out of the totals without deleting it.',
      confirmLabel: 'Undo import',
      destructive: true,
    );
    if (!ok) return;

    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null) return;

    await _withBusy(b.id, () async {
      final result = await ref.read(bulkImportBatchRepositoryProvider).undo(
            churchId: idx.churchId,
            batchId: b.id,
            byUid: idx.uid,
          );
      await logPillrActivity(
        ref,
        churchId: idx.churchId,
        action: 'import.undo',
        entityType: 'import_batch',
        entityId: b.id,
        entitySnapshot: {
          'fileName': b.fileName,
          'removed': result.removed,
          'kept': result.kept,
        },
      );
      invalidateEntryDerivedData(ref);
      ref.invalidate(rankingEntriesProvider);
      await ref.read(importHistoryProvider.notifier).refresh();
      if (mounted) {
        selNotice(
          context,
          result.kept == 0
              ? 'Removed ${result.removed} '
                  '${result.removed == 1 ? "entry" : "entries"}.'
              : 'Removed ${result.removed}; kept ${result.kept} already '
                  'approved.',
          kind: SelNoticeKind.success,
        );
      }
    });
  }

  Future<void> _restore(BulkImportBatch b) async {
    final ok = await selConfirm(
      context,
      title: 'Restore this import?',
      message:
          'Puts the voided entries back to the status they had before they '
          'were cleared. Approved giving returns to the totals.',
      confirmLabel: 'Restore import',
    );
    if (!ok) return;

    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    final actor = ref.read(churchUserProfileProvider).valueOrNull;
    if (idx == null || actor == null) return;

    await _withBusy(b.id, () async {
      final restored = await ref.read(bulkImportBatchActionsProvider).restoreBatch(
            churchId: idx.churchId,
            batchId: b.id,
            actor: actor,
          );
      await logPillrActivity(
        ref,
        churchId: idx.churchId,
        action: 'import.restore',
        entityType: 'import_batch',
        entityId: b.id,
        entitySnapshot: {
          'fileName': b.fileName,
          'restored': restored,
        },
      );
      invalidateEntryDerivedData(ref);
      ref.invalidate(rankingEntriesProvider);
      await ref.read(importHistoryProvider.notifier).refresh();
      if (mounted) {
        selNotice(
          context,
          restored == 0
              ? 'Nothing to restore.'
              : 'Restored $restored ${restored == 1 ? "entry" : "entries"}.',
          kind: SelNoticeKind.success,
        );
      }
    });
  }

  Future<void> _undoMove(BulkImportBatch b) async {
    final previous = b.previousPeriodName;
    if (previous == null) return;
    final ok = await selConfirm(
      context,
      title: 'Move this import back?',
      message: 'Returns every row to $previous.',
      confirmLabel: 'Move back',
    );
    if (!ok) return;

    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    final actor = ref.read(churchUserProfileProvider).valueOrNull;
    if (idx == null || actor == null) return;

    await _withBusy(b.id, () async {
      final moved = await ref.read(bulkImportBatchActionsProvider).undoReassignBatch(
            churchId: idx.churchId,
            batchId: b.id,
            actor: actor,
            previousPeriodName: previous,
          );
      await logPillrActivity(
        ref,
        churchId: idx.churchId,
        action: 'import.reassign_undo',
        entityType: 'import_batch',
        entityId: b.id,
        entitySnapshot: {
          'periodName': previous,
          'moved': moved,
        },
      );
      invalidateEntryDerivedData(ref);
      ref.invalidate(rankingEntriesProvider);
      await ref.read(importHistoryProvider.notifier).refresh();
      if (mounted) {
        selNotice(
          context,
          'Moved $moved ${moved == 1 ? "entry" : "entries"} back to $previous.',
          kind: SelNoticeKind.success,
        );
      }
    });
  }

  Future<void> _undoRename(BulkImportBatch b) async {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null) return;

    await _withBusy(b.id, () async {
      await ref.read(bulkImportBatchRepositoryProvider).rename(
            churchId: idx.churchId,
            batchId: b.id,
            label: b.previousLabel,
            note: b.previousNote,
            previousLabel: null,
            previousNote: null,
            writePrevious: true,
          );
      await logPillrActivity(
        ref,
        churchId: idx.churchId,
        action: 'import.rename_undo',
        entityType: 'import_batch',
        entityId: b.id,
        entitySnapshot: {
          'label': b.previousLabel,
          'fileName': b.fileName,
        },
      );
      await ref.read(importHistoryProvider.notifier).refresh();
      if (mounted) selNotice(context, 'Name reverted.');
    });
  }

  Future<void> _revertEdits(BulkImportBatch b) async {
    final ok = await selConfirm(
      context,
      title: 'Revert the last corrections?',
      message:
          'Puts each row back to the values it had before the last Edit this '
          'import.',
      confirmLabel: 'Revert corrections',
      destructive: true,
    );
    if (!ok) return;

    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    final actor = ref.read(churchUserProfileProvider).valueOrNull;
    if (idx == null || actor == null) return;

    await _withBusy(b.id, () async {
      final reverted = await ref.read(bulkImportBatchActionsProvider).revertLastEdits(
            churchId: idx.churchId,
            batchId: b.id,
            actor: actor,
          );
      await logPillrActivity(
        ref,
        churchId: idx.churchId,
        action: 'import.batch_edit_undo',
        entityType: 'import_batch',
        entityId: b.id,
        entitySnapshot: {
          'fileName': b.fileName,
          'reverted': reverted,
        },
      );
      invalidateEntryDerivedData(ref);
      ref.invalidate(rankingEntriesProvider);
      await ref.read(importHistoryProvider.notifier).refresh();
      if (mounted) {
        selNotice(
          context,
          reverted == 0
              ? 'Nothing to revert — no row still has a last correction.'
              : 'Reverted $reverted ${reverted == 1 ? "row" : "rows"}.',
          kind: SelNoticeKind.success,
        );
      }
    });
  }
}

// ----------------------------------------------------------------- batch card

class _BatchCard extends StatelessWidget {
  const _BatchCard({
    required this.batch,
    required this.money,
    required this.canManage,
    required this.busy,
    required this.onOpenRows,
    required this.onRename,
    required this.onReassign,
    required this.onClear,
    required this.onEdit,
    required this.canEdit,
    required this.onUndo,
    required this.onRestore,
    required this.onUndoMove,
    required this.onUndoRename,
    required this.onRevertEdits,
  });

  final BulkImportBatch batch;
  final String Function(num) money;
  final bool canManage;
  final bool busy;
  final VoidCallback onOpenRows;
  final VoidCallback onRename;
  final VoidCallback onReassign;
  final VoidCallback onClear;
  final VoidCallback onEdit;
  final VoidCallback onUndo;
  final VoidCallback onRestore;
  final VoidCallback onUndoMove;
  final VoidCallback onUndoRename;
  final VoidCallback onRevertEdits;

  /// Editing a row rewrites an entry, which only a pastor may do.
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final settled = batch.isVoided || batch.isUndone;

    return SelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(batch.displayName, style: SelType.subtitleSm),
                    const SizedBox(height: SelSpace.x1),
                    Text(
                      '${batch.periodName} · uploaded '
                      '${formatFirestoreDate(batch.createdAt, pattern: "d MMM y")} '
                      'by ${batch.createdByName}',
                      style: SelType.small,
                    ),
                    if (batch.preparedBy != null) ...[
                      const SizedBox(height: SelSpace.x1),
                      Text('Prepared by ${batch.preparedBy}',
                          style: SelType.small),
                    ],
                    // The file name is how it was identified before it was
                    // named; keep it visible once it is not the title any more.
                    if (batch.label != null && batch.fileName.isNotEmpty) ...[
                      const SizedBox(height: SelSpace.x1),
                      Text(batch.fileName, style: SelType.small),
                    ],
                    if (batch.note != null) ...[
                      const SizedBox(height: SelSpace.x2),
                      Text(batch.note!, style: SelType.bodyMuted),
                    ],
                  ],
                ),
              ),
              if (batch.isIncomplete)
                const SelStatusMark(status: SelStatus.pending, label: 'Did not finish')
              else if (batch.isVoided)
                const SelStatusMark(status: SelStatus.voided, label: 'Cleared')
              else if (batch.isUndone)
                const SelStatusMark(status: SelStatus.voided, label: 'Undone'),
            ],
          ),

          const SizedBox(height: SelSpace.x4),

          Wrap(
            spacing: SelSpace.x8,
            runSpacing: SelSpace.x3,
            children: [
              _Stat(label: 'Entries', value: '${batch.entryCount}'),
              _Stat(label: 'Total', value: money(batch.totalCedis)),
              _Stat(
                label: 'Prepared by',
                value: batch.preparedBy ?? 'Not recorded',
              ),
              _Stat(label: 'Uploaded by', value: batch.createdByName),
              if (batch.partnersCreated > 0)
                _Stat(
                  label: 'Partners added',
                  value: '${batch.partnersCreated}',
                ),
              if (batch.skippedCount > 0)
                _Stat(label: 'Skipped', value: '${batch.skippedCount}'),
              if (batch.isVoided)
                _Stat(label: 'Voided', value: '${batch.voidedCount}'),
              if (batch.isUndone) ...[
                _Stat(label: 'Removed', value: '${batch.removedCount}'),
                _Stat(label: 'Kept', value: '${batch.keptCount}'),
              ],
            ],
          ),

          const SizedBox(height: SelSpace.x4),
          const Divider(height: 1, color: Sel.border),
          const SizedBox(height: SelSpace.x3),

          Wrap(
            spacing: SelSpace.x2,
            runSpacing: SelSpace.x2,
            children: [
              SelButton(
                label: 'See its rows',
                icon: LucideIcons.list,
                kind: SelButtonKind.quiet,
                dense: true,
                onPressed: onOpenRows,
              ),
              if (canEdit && !settled)
                SelButton(
                  label: 'Edit this import',
                  icon: LucideIcons.pencil,
                  kind: SelButtonKind.quiet,
                  dense: true,
                  onPressed: busy ? null : onEdit,
                ),
              if (!batch.isUndone && !batch.isVoided)
                SelButton(
                  label: 'Undo pending rows',
                  icon: LucideIcons.undo2,
                  kind: SelButtonKind.quiet,
                  dense: true,
                  onPressed: busy ? null : onUndo,
                ),
              if (canManage) ...[
                SelButton(
                  label: 'Rename',
                  icon: LucideIcons.pencil,
                  kind: SelButtonKind.quiet,
                  dense: true,
                  onPressed: busy ? null : onRename,
                ),
                if (batch.canUndoRename)
                  SelButton(
                    label: 'Undo name',
                    icon: LucideIcons.undo2,
                    kind: SelButtonKind.quiet,
                    dense: true,
                    onPressed: busy ? null : onUndoRename,
                  ),
                // A settled import has no money left to move.
                if (!settled)
                  SelButton(
                    label: 'Move to another period',
                    icon: LucideIcons.arrowRightLeft,
                    kind: SelButtonKind.quiet,
                    dense: true,
                    onPressed: busy ? null : onReassign,
                  ),
                if (!settled && batch.canUndoMove)
                  SelButton(
                    label: 'Undo move',
                    icon: LucideIcons.undo2,
                    kind: SelButtonKind.quiet,
                    dense: true,
                    onPressed: busy ? null : onUndoMove,
                  ),
                if (canEdit && !settled && batch.canRevertEdits)
                  SelButton(
                    label: 'Revert last corrections',
                    icon: LucideIcons.undo2,
                    kind: SelButtonKind.quiet,
                    dense: true,
                    onPressed: busy ? null : onRevertEdits,
                  ),
                if (!batch.isVoided)
                  SelButton(
                    label: 'Clear this import',
                    icon: LucideIcons.ban,
                    kind: SelButtonKind.quiet,
                    dense: true,
                    onPressed: busy ? null : onClear,
                  ),
                if (batch.isVoided)
                  SelButton(
                    label: 'Restore this import',
                    icon: LucideIcons.rotateCcw,
                    kind: SelButtonKind.quiet,
                    dense: true,
                    onPressed: busy ? null : onRestore,
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(), style: SelType.caption),
        const SizedBox(height: 2),
        Text(value, style: SelType.bodyMedium),
      ],
    );
  }
}

// -------------------------------------------------------------------- dialogs

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.batch});
  final BulkImportBatch batch;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _label = TextEditingController(text: widget.batch.label ?? '');
  late final _note = TextEditingController(text: widget.batch.note ?? '');

  @override
  void dispose() {
    _label.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SelDialog(
      title: 'Name this import',
      subtitle:
          'A file name says little six months later. Give it something you '
          'would recognise.',
      width: 460,
      scrollable: false,
      actions: [
        SelButton(
          label: 'Cancel',
          kind: SelButtonKind.quiet,
          onPressed: () => Navigator.of(context).pop(),
        ),
        SelButton.cyan(
          label: 'Save',
          onPressed: () => Navigator.of(context).pop(
            (label: _label.text, note: _note.text),
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SelField(
            controller: _label,
            label: 'Name',
            hint: widget.batch.fileName.isEmpty
                ? 'March Sunday offerings'
                : widget.batch.fileName,
          ),
          const SizedBox(height: SelSpace.x3),
          SelField(
            controller: _note,
            label: 'Note (optional)',
            hint: 'Anything worth remembering about this run.',
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}

class _ReassignDialog extends StatefulWidget {
  const _ReassignDialog({
    required this.batch,
    required this.periods,
    required this.arms,
  });

  final BulkImportBatch batch;
  final List<PartnershipPeriod> periods;
  final List<PartnershipArm> arms;

  @override
  State<_ReassignDialog> createState() => _ReassignDialogState();
}

class _ReassignDialogState extends State<_ReassignDialog> {
  PartnershipPeriod? _period;
  PartnershipArm? _arm;

  @override
  Widget build(BuildContext context) {
    final activeArms = widget.arms.where((a) => a.isActive).toList();

    return SelDialog(
      title: 'Move this import',
      subtitle:
          'Every entry this file created moves with it. Totals for the old and '
          'new period are corrected automatically.',
      width: 480,
      scrollable: false,
      actions: [
        SelButton(
          label: 'Cancel',
          kind: SelButtonKind.quiet,
          onPressed: () => Navigator.of(context).pop(),
        ),
        SelButton.cyan(
          label: 'Move ${widget.batch.entryCount} entries',
          onPressed: _period == null && _arm == null
              ? null
              : () => Navigator.of(context).pop((period: _period, arm: _arm)),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Currently in ${widget.batch.periodName}.', style: SelType.small),
          const SizedBox(height: SelSpace.x4),
          SelSelect<PartnershipPeriod?>(
            value: _period,
            label: 'Move to period',
            onChanged: (v) => setState(() => _period = v),
            items: [
              const DropdownMenuItem(value: null, child: Text('Leave as it is')),
              for (final p in widget.periods)
                DropdownMenuItem(value: p, child: Text(p.name)),
            ],
          ),
          const SizedBox(height: SelSpace.x3),
          SelSelect<PartnershipArm?>(
            value: _arm,
            label: 'Move to arm',
            onChanged: (v) => setState(() => _arm = v),
            items: [
              const DropdownMenuItem(value: null, child: Text('Leave as it is')),
              for (final a in activeArms)
                DropdownMenuItem(value: a, child: Text(a.name)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClearDialog extends StatefulWidget {
  const _ClearDialog({required this.batch});
  final BulkImportBatch batch;

  @override
  State<_ClearDialog> createState() => _ClearDialogState();
}

class _ClearDialogState extends State<_ClearDialog> {
  final _reason = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Typing the count is the pause. Clearing an import reverses money the
    // church has counted, and a button you can hit by reflex is not enough.
    final expected = '${widget.batch.entryCount}';
    final ready = _confirm.text.trim() == expected && _reason.text.trim().isNotEmpty;

    return SelDialog(
      title: 'Clear this import?',
      subtitle:
          'All ${widget.batch.entryCount} entries stay on the books and stay '
          'readable, but stop counting toward any total. Partner and period '
          'totals are corrected automatically. A pastor can restore them later.',
      width: 480,
      scrollable: false,
      actions: [
        SelButton(
          label: 'Cancel',
          kind: SelButtonKind.quiet,
          onPressed: () => Navigator.of(context).pop(),
        ),
        SelButton(
          label: 'Clear import',
          kind: SelButtonKind.edge,
          onPressed:
              ready ? () => Navigator.of(context).pop(_reason.text) : null,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SelField(
            controller: _reason,
            label: 'Why is it being cleared?',
            hint: 'Imported against the wrong period.',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: SelSpace.x3),
          SelField(
            controller: _confirm,
            label: 'Type $expected to confirm',
            hint: expected,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }
}
