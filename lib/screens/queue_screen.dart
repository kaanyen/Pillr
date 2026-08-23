import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/utils/date_utils.dart';
import '../design/seline.dart';
import '../l10n/app_localizations.dart';
import '../features/arms/providers/arms_providers.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/entries/domain/partnership_entry.dart';
import '../features/entries/providers/entries_providers.dart';
import '../features/entries/providers/record_filters.dart';
import 'record_filter_bar.dart';
import 'arm_palette.dart';
import 'approval_playback.dart';
import 'export_actions.dart';

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
  // The queue is only ever what still needs a decision — not even a ?filter=
  // in the URL can widen it, because "the queue" that sometimes shows settled
  // entries is a queue nobody trusts to be empty when it says it is empty.
  late _Filter _filter = widget.mode == QueueMode.queue
      ? _Filter.pending
      : switch (widget.initialFilter) {
          'pending' => _Filter.pending,
          'approved' => _Filter.approved,
          'declined' => _Filter.declined,
          _ => _Filter.all,
        };

  String? _armId;
  final Set<String> _selected = {};
  bool _busy = false;

  /// Row the keyboard is on, as an index into the rows on screen.
  int _cursor = 0;

  /// How long a decided entry stays visible under the queue before it belongs
  /// to Records alone.
  static const _decidedWindow = Duration(hours: 24);

  /// The window is a moving edge, so the screen has to re-read the clock.
  /// Without this an entry approved while the tab sat open would still be
  /// listed a day later.
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    if (widget.mode == QueueMode.queue) {
      _clock = Timer.periodic(
        const Duration(minutes: 1),
        (_) => mounted ? setState(() {}) : null,
      );
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final money = ref.watch(churchMoneyFormatProvider);
    final entriesAsync = ref.watch(entriesListProvider);
    final arms = ref.watch(armsStreamProvider).valueOrNull ?? [];
    final isPastor = idx?.isPastor ?? false;

    final all = entriesAsync.valueOrNull ?? [];
    // Records and the ranked view share one filter set, so a window narrowed
    // in one is narrowed in the other.
    final scoped = widget.mode == QueueMode.records
        ? applyRecordFilters(
            all,
            ref.watch(recordFiltersProvider),
            now: DateTime.now(),
          )
        : all;
    final rows = scoped.where((e) {
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
    // Clamped here rather than in state: the list shrinks under the cursor
    // every time something is approved.
    final cursor = rows.isEmpty ? -1 : _cursor.clamp(0, rows.length - 1);
    final canReview = isPastor && widget.mode == QueueMode.queue;

    // What was decided in the last day, newest first. The queue proper is
    // pending only — this sits under it so a pastor can see the batch they
    // just approved without going to Records, and it empties itself.
    final now = DateTime.now();
    final decided = widget.mode != QueueMode.queue
        ? const <PartnershipEntry>[]
        : (scoped.where((e) {
            if (e.status == 'pending') return false;
            final at = e.reviewedAt;
            if (at == null) return false;
            if (now.difference(at) >= _decidedWindow) return false;
            return _armId == null || e.partnershipArmId == _armId;
          }).toList()..sort((a, b) => b.reviewedAt!.compareTo(a.reviewedAt!)));

    return CallbackShortcuts(
      bindings: _shortcuts(rows, canReview),
      child: Focus(
        autofocus: true,
        child: SelPageBody(
          onRefresh: () async => ref.invalidate(entriesListProvider),
          children: [
            SelPageTitle(
              title: widget.mode == QueueMode.queue
                  ? l10n.queueTitle
                  : l10n.recordsTitle,
              subtitle: widget.mode == QueueMode.queue
                  ? l10n.queueSubtitle
                  : l10n.recordsSubtitle,
              actions: [
                // Exports follow the current filter: what is on screen is what
                // lands in the file.
                EntryExportButtons(
                  entries: rows,
                  title: widget.mode == QueueMode.queue ? 'Queue' : 'Records',
                  subtitle: _filterDescription(rows.length),
                ),
                const SizedBox(width: SelSpace.x2),
                if (idx?.isStaff == true || isPastor)
                  SelButton.cyan(
                    label: l10n.actionNewEntry,
                    icon: LucideIcons.plus,
                    onPressed: () => context.go('/entries/new'),
                  ),
                SelButton(
                  label: l10n.actionImport,
                  icon: LucideIcons.upload,
                  onPressed: () => context.go('/entries/bulk-import'),
                ),
              ],
            ),

            // Filters sit on the canvas above the card, not inside it — the card
            // holds records, the canvas holds controls.
            Row(
              children: [
                // Queue is a work list, so it has no status tabs: everything on it
                // is pending by definition. Records is the archive and keeps them.
                if (widget.mode == QueueMode.records)
                  Expanded(
                    child: SelPillGroup<_Filter>(
                      selected: _filter,
                      onChanged: (f) => setState(() {
                        _filter = f;
                        _selected.clear();
                      }),
                      options: [
                        (
                          _Filter.all,
                          'All ${all.isEmpty ? "" : "(${all.length})"}'.trim(),
                        ),
                        (_Filter.pending, 'Pending'),
                        (_Filter.approved, 'Approved'),
                        (_Filter.declined, 'Declined'),
                      ],
                    ),
                  )
                else
                  const Spacer(),
                // Records gets the full filter bar below; the queue is a short
                // work list where one arm dropdown is the whole need.
                if (widget.mode == QueueMode.queue && arms.isNotEmpty) ...[
                  const SizedBox(width: SelSpace.x4),
                  SizedBox(
                    width: 190,
                    child: SelSelect<String?>(
                      value: _armId,
                      onChanged: (v) => setState(() => _armId = v),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(l10n.queueAllArms),
                        ),
                        for (final a in arms)
                          DropdownMenuItem(value: a.id, child: Text(a.name)),
                      ],
                    ),
                  ),
                ],
              ],
            ),

            if (widget.mode == QueueMode.records) ...[
              const SizedBox(height: SelSpace.x3),
              RecordFilterBar(entries: all, arms: arms),
            ],

            // Shortcuts nobody is told about are folklore.
            if (canReview && rows.isNotEmpty) ...[
              const SizedBox(height: SelSpace.x3),
              Text(l10n.queueShortcutHint, style: SelType.small),
            ],

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
                onApproveAll: () => _approve(pendingInView),
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
                  SelColumn(l10n.queueColPartner, flex: 3),
                  SelColumn(l10n.queueColArm, flex: 2),
                  SelColumn.numeric(l10n.queueColAmount, width: 130),
                  SelColumn(
                    l10n.queueColStatus,
                    fit: SelColFit.fixed,
                    width: 120,
                  ),
                  SelColumn(
                    isPastor ? l10n.queueColReview : l10n.queueColSubmitted,
                    fit: SelColFit.fixed,
                    width: isPastor ? 170 : 110,
                    align: TextAlign.right,
                  ),
                ],
                emptyState: SelEmpty(
                  // An empty queue is good news, not a failed search — say so.
                  title: switch (widget.mode) {
                    QueueMode.queue => l10n.queueEmptyTitle,
                    QueueMode.records =>
                      _filter == _Filter.all
                          ? l10n.recordsEmptyTitle
                          : 'Nothing here',
                  },
                  message: switch (widget.mode) {
                    QueueMode.queue => l10n.queueEmptyMessage,
                    QueueMode.records =>
                      _filter == _Filter.all
                          ? l10n.recordsEmptyMessage
                          : 'Nothing matches what you picked above.',
                  },
                  actionLabel:
                      widget.mode == QueueMode.records && _filter == _Filter.all
                      ? l10n.recordsEmptyAction
                      : null,
                  onAction:
                      widget.mode == QueueMode.records && _filter == _Filter.all
                      ? () => context.go('/entries/new')
                      : null,
                ),
                rows: [
                  for (final (i, e) in rows.indexed)
                    SelRow(
                      onTap: () {
                        setState(() => _cursor = i);
                        context.go('/entries/${e.id}');
                      },
                      selected: _selected.contains(e.id),
                      cursor: i == cursor,
                      leading: canBulk && e.status == 'pending'
                          ? Semantics(
                              label:
                                  'Select the entry for '
                                  '${e.partnerSnapshot['fullName'] ?? "this partner"}',
                              child: Checkbox(
                                value: _selected.contains(e.id),
                                visualDensity: VisualDensity.compact,
                                onChanged: (v) => setState(() {
                                  v == true
                                      ? _selected.add(e.id)
                                      : _selected.remove(e.id);
                                }),
                              ),
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
                          SelCell.secondary(
                            formatFirestoreDate(e.createdAt, pattern: 'd MMM'),
                          ),
                      ],
                    ),
                ],
              ),
            ),

            if (decided.isNotEmpty) ...[
              const SizedBox(height: SelSpace.x8),
              SelSectionLabel(
                label: l10n.queueDecidedTitle,
                trailing: SelCountTag(label: '${decided.length}'),
              ),
              Text(l10n.queueDecidedNote, style: SelType.small),
              const SizedBox(height: SelSpace.x3),
              SelLedger(
                minWidth: 640,
                showCaptions: false,
                columns: [
                  SelColumn(l10n.queueColPartner, flex: 3),
                  SelColumn(l10n.queueColArm, flex: 2),
                  SelColumn.numeric(l10n.queueColAmount, width: 130),
                  SelColumn(
                    l10n.queueColStatus,
                    fit: SelColFit.fixed,
                    width: 120,
                  ),
                  SelColumn(
                    l10n.queueColDecided,
                    fit: SelColFit.fixed,
                    width: 110,
                    align: TextAlign.right,
                  ),
                ],
                rows: [
                  for (final e in decided)
                    SelRow(
                      onTap: () => context.go('/entries/${e.id}'),
                      cells: [
                        SelCell.stacked(
                          e.partnerSnapshot['fullName']?.toString() ?? '—',
                          e.reviewedBySnapshot?['fullName']?.toString() ?? '',
                        ),
                        ArmLabel(
                          armId: e.partnershipArmId,
                          name: e.armSnapshot['name']?.toString() ?? '—',
                        ),
                        SelCell.numeric(
                          money(e.amountCedis),
                          tone: e.status == 'approved'
                              ? SelTone.positive
                              : SelTone.negative,
                        ),
                        SelStatusMark.fromString(
                          status: e.status,
                          label: _statusLabel(e.status),
                        ),
                        SelCell.secondary(_ago(now.difference(e.reviewedAt!))),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "just now" · "40m ago" · "6h ago". Nothing here is older than a day, so
  /// the scale stops there.
  String _ago(Duration d) {
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    return '${d.inHours}h ago';
  }

  // ---------------------------------------------------------------- keyboard

  /// True when the keystroke belongs to something being typed into.
  ///
  /// Without this, filtering by arm and then typing anywhere would approve
  /// entries — 'a' is a letter before it is a command.
  bool get _typing {
    final focus = FocusManager.instance.primaryFocus;
    return focus?.context?.widget is EditableText;
  }

  void _moveCursor(int delta, int count) {
    if (_typing || count == 0) return;
    setState(() => _cursor = (_cursor + delta).clamp(0, count - 1));
  }

  Map<ShortcutActivator, VoidCallback> _shortcuts(
    List<PartnershipEntry> rows,
    bool isPastor,
  ) {
    PartnershipEntry? at() =>
        rows.isEmpty ? null : rows[_cursor.clamp(0, rows.length - 1)];

    return {
      const SingleActivator(LogicalKeyboardKey.keyJ): () =>
          _moveCursor(1, rows.length),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
          _moveCursor(1, rows.length),
      const SingleActivator(LogicalKeyboardKey.keyK): () =>
          _moveCursor(-1, rows.length),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
          _moveCursor(-1, rows.length),
      const SingleActivator(LogicalKeyboardKey.keyX): () {
        final e = at();
        if (e == null || _typing || !isPastor) return;
        setState(() {
          _selected.contains(e.id)
              ? _selected.remove(e.id)
              : _selected.add(e.id);
        });
      },
      const SingleActivator(LogicalKeyboardKey.keyA): () {
        if (_typing || !isPastor) return;
        // With a selection, 'a' means that selection; without one it means
        // the row under the cursor. Approving a hundred by accident is the
        // one thing this must not do, so the selection path still confirms.
        final chosen = _selected.isNotEmpty
            ? rows.where((e) => _selected.contains(e.id)).toList()
            : [?at()];
        _approve(chosen);
      },
      const SingleActivator(LogicalKeyboardKey.keyD): () {
        final e = at();
        if (e == null || _typing || !isPastor) return;
        _decline(e);
      },
      const SingleActivator(LogicalKeyboardKey.enter): () {
        final e = at();
        if (e == null || _typing) return;
        context.go('/entries/${e.id}');
      },
    };
  }

  /// Describes what the export contains, so a PDF is not ambiguous later.
  String _filterDescription(int count) {
    final parts = <String>[
      switch (_filter) {
        _Filter.all => 'All statuses',
        _Filter.pending => 'Pending',
        _Filter.approved => 'Approved',
        _Filter.declined => 'Declined',
      },
    ];
    if (_armId != null) {
      final arms = ref.read(armsStreamProvider).valueOrNull ?? [];
      final arm = arms.where((a) => a.id == _armId).firstOrNull;
      if (arm != null) parts.add(arm.name);
    }
    return '${parts.join(' · ')} — $count entries';
  }

  String _statusLabel(String s) {
    final l10n = AppLocalizations.of(context);
    return switch (s) {
      'approved' => l10n.statusApproved,
      'declined' => l10n.statusDeclined,
      _ => l10n.statusPending,
    };
  }

  Future<void> _approve(List<PartnershipEntry> entries) async {
    if (entries.isEmpty || _busy) return;
    final l10n = AppLocalizations.of(context);
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    final pastor = ref.read(churchUserProfileProvider).valueOrNull;
    if (idx == null || pastor == null) return;

    if (entries.length > 1) {
      final ok = await selConfirm(
        context,
        title: l10n.queueConfirmApproveTitle(entries.length),
        message: l10n.queueConfirmApproveBody,
        confirmLabel: l10n.queueApprove,
      );
      if (!ok) return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(entriesRepositoryProvider)
          .approveEntries(
            churchId: idx.churchId,
            entries: entries,
            pastor: pastor,
          );
      if (mounted) setState(() => _selected.clear());
      // A receipt of what just happened. Only worth playing for a batch —
      // after approving one row you already know what you did.
      if (mounted && entries.length > 1) {
        await ApprovalPlayback.show(
          context,
          entries: entries,
          formatMoney: ref.read(churchMoneyFormatProvider),
        );
      }
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
      await ref
          .read(entriesRepositoryProvider)
          .declineEntry(
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
          label: AppLocalizations.of(context).queueSendBack,
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
          label: AppLocalizations.of(context).queueSendBack,
          kind: SelButtonKind.quiet,
          dense: true,
          onPressed: busy ? null : onDecline,
        ),
        const SizedBox(width: SelSpace.x1),
        SelButton(
          label: AppLocalizations.of(context).queueApprove,
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
    required this.onApproveAll,
  });

  final int selectedCount;
  final int pendingCount;
  final bool busy;
  final VoidCallback onSelectAll;
  final VoidCallback onApprove;
  final VoidCallback onApproveAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = (
      clearSelection: l10n.queueClearSelection,
      selectAll: l10n.queueSelectAll(pendingCount),
      selectedCount: l10n.queueSelectedCount(selectedCount),
      approveAll: l10n.queueApproveAll(pendingCount),
      approveSelected: l10n.queueApproveSelected,
    );
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
            label: all ? labels.clearSelection : labels.selectAll,
            kind: SelButtonKind.quiet,
            dense: true,
            onPressed: onSelectAll,
          ),
          const Spacer(),
          if (selectedCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: SelSpace.x3),
              child: Text(labels.selectedCount, style: SelType.bodyMuted),
            ),
          if (selectedCount == 0)
            SelButton.cyan(
              label: labels.approveAll,
              loading: busy,
              onPressed: onApproveAll,
            )
          else
            SelButton.cyan(
              label: labels.approveSelected,
              loading: busy,
              onPressed: onApprove,
            ),
        ],
      ),
    );
  }
}
