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
  String? _openId;

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
        Row(
          children: [
            SelLink(label: 'Records', onTap: () => context.go('/records')),
            Text('  /  ', style: SelType.bodySm),
            Text('Imports', style: SelType.bodySm),
          ],
        ),
        const SizedBox(height: SelSpace.x3),
        SelPageTitle(
          title: 'Imports',
          subtitle:
              'Every sheet brought into Pillr, and what it created. Clear or move a whole import in one step.',
          actions: [
            SelButton.cyan(
              label: 'Bring in a sheet',
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
              _ImportsTable(
                batches: state.batches,
                money: money,
                openId: _openId ?? state.batches.first.id,
                onOpen: (b) => setState(() => _openId = b.id),
              ),
              const SizedBox(height: SelSpace.x4),
              for (final b in state.batches)
                if (b.id == (_openId ?? state.batches.first.id))
                  _BatchCard(
                    batch: b,
                    // Null while counting: the take-back action waits for it.
                    waiting: idx == null
                        ? null
                        : ref
                              .watch(importWaitingCountProvider('${idx.churchId}/${b.id}'))
                              .valueOrNull,
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
      // Undo, clear or restore can change how many entries are waiting.
      if (mounted) {
        ref.invalidate(importWaitingCountProvider);
        setState(() => _busyBatchId = null);
      }
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
    required this.waiting,
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

  /// Entries of this import still waiting for a pastor; null while counting.
  final int? waiting;

  @override
  Widget build(BuildContext context) {
    final settled = batch.isVoided || batch.isUndone;
    final actions = <(String, String, String, VoidCallback, bool)>[
      // (title, help, button, action, primary-looking)
      ('See its rows', 'Every entry this import created, in Records.', 'Open', onOpenRows, false),
      if (canEdit && !settled)
        ('Correct its rows', 'Fix amounts, arms or partners across the import.', 'Edit', onEdit, false),
      if (canManage && !settled)
        ('Move to another period', 'For a sheet brought into the wrong year. Every entry it created moves with it.', 'Move', onReassign, true),
      if (canManage && !settled && batch.canUndoMove)
        ('Move it back', 'Puts its entries back where they were before the last move.', 'Undo move', onUndoMove, false),
      if (!settled && (waiting ?? 0) > 0)
        (
          'Take back the $waiting still waiting',
          'Removes the ${waiting == 1 ? 'entry' : 'entries'} no pastor has approved yet. Approved ones stay.',
          'Undo',
          onUndo,
          false,
        ),
      if (canEdit && !settled && batch.canRevertEdits)
        ('Revert the last corrections', 'Puts the rows back as they were before the last edit.', 'Revert', onRevertEdits, false),
      if (canManage && !batch.isVoided)
        ('Clear this import', 'Voids all ${batch.entryCount} entries. Approved ones leave the totals; nothing is deleted.', 'Clear', onClear, true),
      if (canManage && batch.isVoided)
        ('Restore this import', 'Brings its entries back, as they were before it was cleared.', 'Restore', onRestore, true),
      if (canManage)
        ('Rename', 'A file name says little six months later.', 'Rename', onRename, false),
      if (canManage && batch.canUndoRename)
        ('Undo the name', 'Goes back to the name it had before.', 'Undo name', onUndoRename, false),
    ];

    return SelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(batch.displayName, style: SelType.subtitle)),
              Text(
                '${batch.entryCount} entries · ${money(batch.totalCedis)} · ${batch.periodName}',
                style: SelType.small,
              ),
            ],
          ),
          if (batch.note != null) ...[
            const SizedBox(height: SelSpace.x1),
            Text(batch.note!, style: SelType.bodySm),
          ],
          const SizedBox(height: SelSpace.x2),
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Sel.rowLine),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          actions[i].$1,
                          style: SelType.body.copyWith(
                            color: Sel.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(actions[i].$2, style: SelType.small),
                      ],
                    ),
                  ),
                  const SizedBox(width: SelSpace.x4),
                  if (actions[i].$5)
                    SelButton(
                      label: actions[i].$3,
                      onPressed: busy ? null : actions[i].$4,
                    )
                  else
                    SelLink(
                      label: actions[i].$3,
                      onTap: busy ? null : actions[i].$4,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Every import as one table row: what it was, when and by whom, what it
/// created and where it stands. Open shows its actions below the table.
class _ImportsTable extends ConsumerWidget {
  const _ImportsTable({
    required this.batches,
    required this.money,
    required this.openId,
    required this.onOpen,
  });

  final List<BulkImportBatch> batches;
  final String Function(num) money;
  final String openId;
  final ValueChanged<BulkImportBatch> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final churchId = ref.watch(userChurchIndexProvider).valueOrNull?.churchId;
    int waiting(BulkImportBatch b) => churchId == null
        ? 0
        : ref.watch(importWaitingCountProvider('$churchId/${b.id}')).valueOrNull ?? 0;
    return SelLedger(
      minWidth: 860,
      rowExtent: kSelLedgerStackedRowExtent,
      columns: const [
        SelColumn('Import', flex: 3),
        SelColumn('Brought in', flex: 2),
        SelColumn.numeric('Entries', width: 80),
        SelColumn.numeric('Giving', width: 140),
        SelColumn('Also', flex: 2),
        SelColumn('Status', fit: SelColFit.fixed, width: 130),
        SelColumn('', fit: SelColFit.fixed, width: 90),
      ],
      rows: [
        for (final b in batches)
          SelRow(
            selected: b.id == openId,
            onTap: () => onOpen(b),
            cells: [
              SelCell.stacked(b.displayName, b.fileName),
              SelCell.stacked(
                formatFirestoreDate(b.createdAt, pattern: 'd MMM, HH:mm'),
                b.createdByName,
              ),
              SelCell.numeric(b.entryCount == 0 ? '—' : '${b.entryCount}', strong: false),
              SelCell.numeric(b.entryCount == 0 ? '—' : money(b.totalCedis)),
              SelCell.secondary(
                b.isVoided
                    ? 'Every row left out'
                    : b.partnersCreated > 0
                    ? '${b.partnersCreated} new ${b.partnersCreated == 1 ? 'partner' : 'partners'}'
                    : b.skippedCount > 0
                    ? '${b.skippedCount} rows skipped'
                    : b.periodName,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: b.isIncomplete
                    ? const SelStatusMark(status: SelStatus.pending, label: 'Not finished')
                    : b.isVoided
                    ? const SelStatusMark(status: SelStatus.voided, label: 'Cleared')
                    : b.isUndone
                    ? const SelStatusMark(status: SelStatus.voided, label: 'Undone')
                    : waiting(b) > 0
                    ? SelStatusMark(status: SelStatus.pending, label: '${waiting(b)} waiting')
                    : const SelStatusMark(status: SelStatus.approved, label: 'Approved'),
              ),
              SelLink(label: 'Open', onTap: () => onOpen(b)),
            ],
          ),
      ],
    );
  }
}

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
