import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/utils/date_utils.dart';
import '../design/seline.dart';
import '../features/arms/providers/arms_providers.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/entries/domain/partnership_entry.dart';
import '../features/entries/providers/entries_providers.dart';
import 'arm_palette.dart';

/// Which slice of the collection the queue is showing.
enum _Filter { all, pending, approved, declined }

/// Queue — Entries and Approvals, merged.
///
/// These were always one collection filtered two ways: Approvals was
/// `status == pending` with review buttons, Entries was everything without
/// them. Keeping them apart meant a pastor approving a batch had to leave the
/// screen to see what they had just approved.
///
/// Now it is one list with a status filter. When the filter includes pending
/// rows and the viewer is a pastor, the review actions appear inline on those
/// rows — so approving never costs a navigation.
/// Which job this screen is doing.
///
/// Same records, two purposes. A work queue opens on what still needs a
/// decision; an archive opens on everything. Splitting them into separate
/// destinations means neither has to be reached through the other.
enum QueueMode {
  /// Things awaiting action. Opens filtered to pending.
  queue,

  /// Every entry ever recorded. Opens unfiltered.
  records,
}

class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({
    super.key,
    this.initialFilter,
    this.mode = QueueMode.queue,
  });

  /// Lets `/approvals` land here pre-filtered instead of 404ing.
  final String? initialFilter;

  final QueueMode mode;

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  late _Filter _filter = switch (widget.initialFilter) {
    'pending' => _Filter.pending,
    'approved' => _Filter.approved,
    'declined' => _Filter.declined,
    'all' => _Filter.all,
    // No explicit filter: the queue opens on what needs a decision, records
    // opens on everything.
    _ => widget.mode == QueueMode.queue ? _Filter.pending : _Filter.all,
  };

  String? _armId;
  final Set<String> _selected = {};
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final money = ref.watch(churchMoneyFormatProvider);
    final entriesAsync = ref.watch(entriesListProvider);
    final arms = ref.watch(armsStreamProvider).valueOrNull ?? [];
    final isPastor = idx?.isPastor ?? false;

    final all = entriesAsync.valueOrNull ?? [];
    final rows = all.where((e) {
      final byStatus = switch (_filter) {
        _Filter.all => true,
        _Filter.pending => e.status == 'pending',
        _Filter.approved => e.status == 'approved',
        _Filter.declined => e.status == 'declined',
      };
      final byArm = _armId == null || e.partnershipArmId == _armId;
      return byStatus && byArm;
    }).toList();

    final pendingInView = rows.where((e) => e.status == 'pending').toList();
    final canBulk = isPastor && pendingInView.isNotEmpty;

    return SelPageBody(
      onRefresh: () async => ref.invalidate(entriesListProvider),
      children: [
        SelPageTitle(
          title: widget.mode == QueueMode.queue ? 'Queue' : 'Records',
          subtitle: widget.mode == QueueMode.queue
              ? 'Entries waiting on a decision.'
              : 'Every partnership entry for your church, newest first.',
          actions: [
            if (idx?.isStaff == true || isPastor)
              SelButton.cyan(
                label: 'New entry',
                icon: LucideIcons.plus,
                onPressed: () => context.go('/entries/new'),
              ),
            SelButton(
              label: 'Import',
              icon: LucideIcons.upload,
              onPressed: () => context.go('/entries/bulk-import'),
            ),
          ],
        ),

        // Filters sit on the canvas above the card, not inside it — the card
        // holds records, the canvas holds controls.
        Row(
          children: [
            Expanded(
              child: SelPillGroup<_Filter>(
                selected: _filter,
                onChanged: (f) => setState(() {
                  _filter = f;
                  _selected.clear();
                }),
                options: [
                  (_Filter.all, 'All ${all.isEmpty ? "" : "(${all.length})"}'.trim()),
                  (_Filter.pending, 'Pending'),
                  (_Filter.approved, 'Approved'),
                  (_Filter.declined, 'Declined'),
                ],
              ),
            ),
            if (arms.isNotEmpty) ...[
              const SizedBox(width: SelSpace.x4),
              SizedBox(
                width: 190,
                child: SelSelect<String?>(
                  value: _armId,
                  onChanged: (v) => setState(() => _armId = v),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All arms')),
                    for (final a in arms)
                      DropdownMenuItem(value: a.id, child: Text(a.name)),
                  ],
                ),
              ),
            ],
          ],
        ),

        if (canBulk) ...[
          const SizedBox(height: SelSpace.x4),
          _BulkBar(
            selectedCount: _selected.length,
            pendingCount: pendingInView.length,
            busy: _busy,
            onSelectAll: () => setState(() {
              if (_selected.length == pendingInView.length) {
                _selected.clear();
              } else {
                _selected
                  ..clear()
                  ..addAll(pendingInView.map((e) => e.id));
              }
            }),
            onApprove: () => _approve(
              pendingInView.where((e) => _selected.contains(e.id)).toList(),
            ),
          ),
        ],

        const SizedBox(height: SelSpace.x6),

        entriesAsync.when(
          loading: () => const SelCard(child: SelSkeletonRows()),
          error: (e, _) => SelError(
            message: '$e',
            onRetry: () => ref.invalidate(entriesListProvider),
          ),
          data: (_) => SelLedger(
            minWidth: 760,
            columns: [
              const SelColumn('Partner', flex: 3),
              const SelColumn('Arm', flex: 2),
              const SelColumn.numeric('Amount', width: 130),
              const SelColumn('Status', fit: SelColFit.fixed, width: 120),
              SelColumn(
                isPastor ? 'Review' : 'Submitted',
                fit: SelColFit.fixed,
                width: isPastor ? 170 : 110,
                align: TextAlign.right,
              ),
            ],
            emptyState: SelEmpty(
              title: _filter == _Filter.all ? 'No entries yet' : 'Nothing here',
              message: _filter == _Filter.all
                  ? 'Partnership entries will appear as your team records them.'
                  : 'No entries match this filter.',
              actionLabel: _filter == _Filter.all ? 'Record the first entry' : null,
              onAction: _filter == _Filter.all
                  ? () => context.go('/entries/new')
                  : null,
            ),
            rows: [
              for (final e in rows)
                SelRow(
                  onTap: () => context.go('/entries/${e.id}'),
                  selected: _selected.contains(e.id),
                  leading: canBulk && e.status == 'pending'
                      ? Checkbox(
                          value: _selected.contains(e.id),
                          visualDensity: VisualDensity.compact,
                          onChanged: (v) => setState(() {
                            v == true ? _selected.add(e.id) : _selected.remove(e.id);
                          }),
                        )
                      : const SizedBox.shrink(),
                  cells: [
                    SelCell.stacked(
                      e.partnerSnapshot['fullName']?.toString() ?? '—',
                      e.createdBySnapshot['fullName']?.toString() ?? '',
                    ),
                    ArmLabel(
                      armId: e.partnershipArmId,
                      name: e.armSnapshot['name']?.toString() ?? '—',
                    ),
                    SelCell.numeric(
                      money(e.amountCedis),
                      tone: switch (e.status) {
                        'approved' => SelTone.positive,
                        'declined' => SelTone.negative,
                        _ => SelTone.neutral,
                      },
                    ),
                    SelStatusMark.fromString(
                      status: e.status,
                      label: _statusLabel(e.status),
                    ),
                    if (isPastor && e.status == 'pending')
                      _RowActions(
                        busy: _busy,
                        onApprove: () => _approve([e]),
                        onDecline: () => _decline(e),
                      )
                    else
                      SelCell.secondary(formatFirestoreDate(e.createdAt, pattern: 'd MMM')),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _statusLabel(String s) => switch (s) {
        'approved' => 'Approved',
        'declined' => 'Declined',
        _ => 'Pending',
      };

  Future<void> _approve(List<PartnershipEntry> entries) async {
    if (entries.isEmpty || _busy) return;
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    final pastor = ref.read(churchUserProfileProvider).valueOrNull;
    if (idx == null || pastor == null) return;

    if (entries.length > 1) {
      final ok = await selConfirm(
        context,
        title: 'Approve ${entries.length} entries?',
        message:
            'They will be added to partner totals and period figures immediately.',
        confirmLabel: 'Approve all',
      );
      if (!ok) return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(entriesRepositoryProvider).approveEntries(
            churchId: idx.churchId,
            entries: entries,
            pastor: pastor,
          );
      if (mounted) setState(() => _selected.clear());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline(PartnershipEntry entry) async {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    final pastor = ref.read(churchUserProfileProvider).valueOrNull;
    if (idx == null || pastor == null) return;

    final reason = await _askReason(context);
    if (reason == null || reason.trim().isEmpty) return;

    setState(() => _busy = true);
    try {
      await ref.read(entriesRepositoryProvider).declineEntry(
            churchId: idx.churchId,
            entry: entry,
            pastor: pastor,
            reason: reason,
          );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Decline always asks for a reason — the staff member who submitted it sees
/// this text, so an empty decline is not allowed.
Future<String?> _askReason(BuildContext context) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => SelDialog(
      title: 'Send this entry back',
      subtitle: 'Your note is shown to whoever submitted it.',
      width: 460,
      scrollable: false,
      actions: [
        SelButton(
          label: 'Cancel',
          kind: SelButtonKind.quiet,
          onPressed: () => Navigator.of(context).pop(),
        ),
        SelButton.cyan(
          label: 'Send back',
          onPressed: () => Navigator.of(context).pop(c.text),
        ),
      ],
      child: SelField(
        controller: c,
        label: 'Reason',
        hint: 'Amount does not match the deposit slip',
        maxLines: 3,
        autofocus: true,
      ),
    ),
  );
}

class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.busy,
    required this.onApprove,
    required this.onDecline,
  });

  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SelButton(
          label: 'Send back',
          kind: SelButtonKind.quiet,
          dense: true,
          onPressed: busy ? null : onDecline,
        ),
        const SizedBox(width: SelSpace.x1),
        SelButton(
          label: 'Approve',
          kind: SelButtonKind.edge,
          dense: true,
          onPressed: busy ? null : onApprove,
        ),
      ],
    );
  }
}

/// Bulk action bar. Sits on the canvas above the ledger as a white strip.
class _BulkBar extends StatelessWidget {
  const _BulkBar({
    required this.selectedCount,
    required this.pendingCount,
    required this.busy,
    required this.onSelectAll,
    required this.onApprove,
  });

  final int selectedCount;
  final int pendingCount;
  final bool busy;
  final VoidCallback onSelectAll;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    final all = selectedCount == pendingCount && pendingCount > 0;
    return SelCard(
      lift: SelLift.flat,
      padding: const EdgeInsets.symmetric(
        horizontal: SelSpace.x4,
        vertical: SelSpace.x2,
      ),
      child: Row(
        children: [
          SelButton(
            label: all ? 'Clear selection' : 'Select all $pendingCount pending',
            kind: SelButtonKind.quiet,
            dense: true,
            onPressed: onSelectAll,
          ),
          const Spacer(),
          if (selectedCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: SelSpace.x3),
              child: Text('$selectedCount selected', style: SelType.bodyMuted),
            ),
          SelButton.cyan(
            label: 'Approve selected',
            loading: busy,
            onPressed: selectedCount == 0 ? null : onApprove,
          ),
        ],
      ),
    );
  }
}
