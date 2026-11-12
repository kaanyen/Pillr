import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/extensions/async_value_ext.dart';
import '../../design/seline.dart';
import '../auth/providers/auth_providers.dart';
import '../entries/providers/entries_providers.dart';
import '../partners/providers/partners_providers.dart';
import 'record_ops_repository.dart';

/// The last bulk changes — fellowship merges, moves, dissolves and partner
/// merges — each with Undo while it can still be undone.
///
/// [kindPrefix] narrows the list: `fellowship.` on the Fellowships screen,
/// everything in Tools.
class RecentChangesCard extends ConsumerStatefulWidget {
  const RecentChangesCard({super.key, this.kindPrefix = '', this.blurb});

  final String kindPrefix;
  final String? blurb;

  @override
  ConsumerState<RecentChangesCard> createState() => _RecentChangesCardState();
}

class _RecentChangesCardState extends ConsumerState<RecentChangesCard> {
  bool busy = false;

  Future<void> onUndo(RecordOperation op) async {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null || busy) return;
    final ok = await selConfirm(
      context,
      title: 'Undo this change?',
      message:
          '${op.label}. Everything it changed goes back as it was — partners '
          'to their old fellowship, entries to the partner they came from, a '
          'closed record reopened — except anything someone has edited since, '
          'which is left alone and counted.',
      confirmLabel: 'Undo',
    );
    if (!ok || !mounted) return;
    setState(() => busy = true);
    try {
      await runWithProgress(
        context,
        title: 'Undoing: ${op.label}',
        subtitle: 'Pillr does this on the server; keep this page open.',
        steps: const ['Finding what the change touched', 'Putting each record back', 'Updating the totals'],
        run: (p) async {
          final r = await runServerSteps(
            p,
            () => ref.read(recordOpsRepositoryProvider).undo(churchId: idx.churchId, opId: op.id),
          );
          return SelSummary(
            title: 'Undone',
            subtitle: op.label,
            numbers: [
              ('${r.reverted}', '${r.reverted == 1 ? 'record' : 'records'} put back'),
              if (r.conflicts > 0) ('${r.conflicts}', 'left as they are'),
            ],
            lines: [
              if (r.conflicts > 0)
                SelSummaryLine(
                  '${r.conflicts} had been edited since',
                  detail: 'They were left as they are, so nobody\'s later work was lost.',
                  ok: false,
                ),
            ],
          );
        },
      );
      ref.invalidate(partnersStreamProvider(false));
      ref.invalidate(rankingEntriesProvider);
      invalidateEntryDerivedData(ref);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ops = [
      for (final op
          in ref.watch(recentOperationsProvider).valueOrNull ??
              const <RecordOperation>[])
        if (op.kind.startsWith(widget.kindPrefix)) op,
    ];
    return SelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(LucideIcons.history, size: 18, color: Sel.warm),
              const SizedBox(width: SelSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Recent changes', style: SelType.subtitleSm),
                    const SizedBox(height: SelSpace.x1),
                    Text(
                      widget.blurb ??
                          'Fellowship merges, moves and dissolves, and partner '
                              'merges. Undo puts back what each one changed, '
                              'unless it has been edited since.',
                      style: SelType.bodyMuted,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: SelSpace.x4),
          const Divider(height: 1, color: Sel.border),
          const SizedBox(height: SelSpace.x3),
          if (ops.isEmpty)
            Text('Nothing yet.', style: SelType.small)
          else
            for (final op in ops)
              Padding(
                padding: const EdgeInsets.only(bottom: SelSpace.x2),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(op.label, style: SelType.body),
                          Text(
                            [
                              formatOperationTime(op.createdAt),
                              if (op.actorName.isNotEmpty) op.actorName,
                              operationStatusLabel(op),
                            ].join('  ·  '),
                            style: SelType.small.copyWith(
                              color: op.status == 'failed' ? Sel.danger : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (op.canUndo)
                      SelButton(
                        label: 'Undo',
                        kind: SelButtonKind.quiet,
                        dense: true,
                        onPressed: busy ? null : () => onUndo(op),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

String operationStatusLabel(RecordOperation op) => switch (op.status) {
  'applied' => '${op.planned} ${op.planned == 1 ? "record" : "records"}',
  'failed' =>
    'stopped after ${op.applied} of ${op.planned} — undo or run again',
  'applying' => 'running',
  'undoing' => 'undoing',
  'undone' =>
    op.undoConflictCount == 0
        ? 'undone'
        : 'undone, ${op.undoConflictCount} left as edited',
  _ => op.status,
};

String formatOperationTime(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.day}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}
