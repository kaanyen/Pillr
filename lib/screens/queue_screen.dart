import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/navigation/panel_flows.dart';
import '../core/notifications/sel_notice.dart';
import '../features/activity/activity_log_helper.dart';
import '../core/utils/date_utils.dart';
import '../design/seline.dart';
import '../l10n/app_localizations.dart';
import '../features/arms/providers/arms_providers.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/entries/domain/partnership_entry.dart';
import '../features/entries/presentation/entry_amount_cell.dart';
import '../features/entries/providers/entries_providers.dart';
import '../features/entries/providers/record_filters.dart';
import '../features/partners/providers/partners_providers.dart';
import '../features/entries/fellowship_of.dart';
import 'record_filter_bar.dart';
import 'arm_palette.dart';
import 'approval_playback.dart';
import 'export_actions.dart';
import '../core/errors/plain_error.dart';

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
    this.importBatchId,
    this.mode = QueueMode.queue,
  });

  /// Lets `/approvals` land here pre-filtered instead of 404ing.
  final String? initialFilter;

  /// Narrows Records to the rows one import created. Set by `?import=`.
  final String? importBatchId;

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
  final Set<String> _decidingIds = {};

  /// Row the keyboard is on, as an index into the rows on screen.
  int _cursor = 0;

  /// How long a decided entry stays visible under the queue before it belongs
  /// to Records alone.
  static const _decidedWindow = Duration(hours: 24);

  /// The cutoff for the decided strip, floored to the minute.
  ///
  /// This keys a provider family, and the screen rebuilds far more often than
  /// the clock ticks — a raw `DateTime.now()` would spawn a fresh subscription
  /// on every frame. Flooring it makes the key change once a minute, which is
  /// exactly how often the timer moves the window.
  DateTime get _decidedSince {
    final n = DateTime.now().subtract(_decidedWindow);
    return DateTime(n.year, n.month, n.day, n.hour, n.minute);
  }

  /// The window is a moving edge, so the screen has to re-read the clock.
  /// Without this an entry approved while the tab sat open would still be
  /// listed a day later.
  Timer? _clock;

  static const _recordsPageSize = 80;
  final ScrollController _recordsScrollController = ScrollController();
  List<PartnershipEntry> _recordsItems = [];
  DocumentSnapshot<Map<String, dynamic>>? _recordsCursor;
  bool _recordsHasMore = true;
  bool _recordsLoading = false;
  bool _recordsLoadingMore = false;
  String? _recordsError;

  @override
  void initState() {
    super.initState();
    if (widget.mode == QueueMode.queue) {
      _clock = Timer.periodic(
        const Duration(minutes: 1),
        (_) => mounted ? setState(() {}) : null,
      );
    } else {
      _recordsScrollController.addListener(_onRecordsScroll);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadRecordsPage(reset: true);
      });
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    if (widget.mode == QueueMode.records) {
      _recordsScrollController.removeListener(_onRecordsScroll);
      _recordsScrollController.dispose();
    }
    super.dispose();
  }

  void _onRecordsScroll() {
    if (!_recordsHasMore || _recordsLoadingMore || _recordsLoading) return;
    final pos = _recordsScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      _loadRecordsPage();
    }
  }

  Future<void> _loadRecordsPage({bool reset = false}) async {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null) return;
    if (reset) {
      setState(() {
        _recordsLoading = true;
        _recordsError = null;
        _recordsItems = [];
        _recordsCursor = null;
        _recordsHasMore = true;
      });
    } else {
      if (!_recordsHasMore) return;
      setState(() => _recordsLoadingMore = true);
    }
    try {
      final page = await ref
          .read(entriesRepositoryProvider)
          .fetchEntriesPage(
            idx.churchId,
            allChurchEntries: idx.isPastor,
            createdByUid: idx.isPastor ? null : idx.uid,
            importBatchId: widget.importBatchId,
            pageSize: _recordsPageSize,
            startAfter: reset ? null : _recordsCursor,
          );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _recordsItems = page.items;
        } else {
          _recordsItems = [..._recordsItems, ...page.items];
        }
        _recordsCursor = page.lastDoc;
        _recordsHasMore = page.hasMore;
        _recordsLoading = false;
        _recordsLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recordsError = plainError(e);
        _recordsLoading = false;
        _recordsLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // The first page is requested once, right after the first frame, and gives
    // up if the signed-in user's church is not known yet. On a cold load or a
    // refresh of /records that is the usual case, and nothing asked again: the
    // screen sat on "No entries yet" over a church with 1,265 of them. Ask
    // again the moment the church arrives, and whenever it changes.
    if (widget.mode == QueueMode.records) {
      ref.listen(userChurchIndexProvider, (previous, next) {
        final was = previous?.valueOrNull;
        final now = next.valueOrNull;
        if (now == null) return;
        if (was?.churchId == now.churchId && was?.uid == now.uid) return;
        _loadRecordsPage(reset: true);
      });
    }
    final l10n = AppLocalizations.of(context);
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final money = ref.watch(churchMoneyFormatProvider);
    // The queue is pending work; Records pages its own rows in. Neither needs
    // the church's whole entry collection.
    final entriesAsync = widget.mode == QueueMode.queue
        ? ref.watch(pendingEntriesProvider)
        : const AsyncValue<List<PartnershipEntry>>.data([]);
    final armColors = ref.watch(armColorsProvider);
    final arms = ref.watch(armsStreamProvider).valueOrNull ?? [];
    final armTree = ref.watch(armTreeProvider);
    final isPastor = idx?.isPastor ?? false;

    final all = widget.mode == QueueMode.records
        ? _recordsItems
        : (entriesAsync.valueOrNull ?? []);
    // Records and the ranked view share one filter set, so a window narrowed
    // in one is narrowed in the other.
    final scoped = widget.mode == QueueMode.records
        ? applyRecordFilters(
            all,
            ref.watch(recordFiltersProvider),
            now: DateTime.now(),
            fellowshipByPartnerId: ref.watch(partnerFellowshipByIdProvider),
            armFamilyOf: armTree.familyOf,
          )
        : all;
    // Picking a main arm takes in its sub-arms too.
    final armFamily = _armId == null ? null : armTree.familyOf(_armId!);
    final rows = scoped.where((e) {
      final byStatus = switch (_filter) {
        _Filter.all => true,
        _Filter.pending => e.status == 'pending',
        _Filter.approved => e.status == 'approved',
        _Filter.declined => e.status == 'declined',
      };
      final byArm = armFamily == null || armFamily.contains(e.partnershipArmId);
      return byStatus && byArm;
    }).toList();
    // The Queue is worked oldest first, so the longest wait is at the top.
    if (widget.mode == QueueMode.queue) {
      rows.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }

    final pendingInView = rows.where((e) => e.status == 'pending').toList();
    final canBulk = isPastor && pendingInView.isNotEmpty;
    // Clamped here rather than in state: the list shrinks under the cursor
    // every time something is approved.
    final cursor = rows.isEmpty ? -1 : _cursor.clamp(0, rows.length - 1);
    final canReview = isPastor && widget.mode == QueueMode.queue;

    // What was decided in the last day, newest first. The queue proper is
    // pending only — this sits under it so a pastor can see the batch they
    // just approved without going to Records, and it empties itself.
    //
    // Its own query now, rather than a sieve over every entry in the church:
    // the cutoff is a range filter Firestore can serve from the index, and
    // pending rows carry no `reviewedAt` so they fall out on their own.
    final now = DateTime.now();
    final decided = widget.mode != QueueMode.queue
        ? const <PartnershipEntry>[]
        : (ref.watch(recentlyDecidedProvider(_decidedSince)).valueOrNull ??
                  const <PartnershipEntry>[])
              .where((e) => armFamily == null || armFamily.contains(e.partnershipArmId))
              .toList();

    return CallbackShortcuts(
      bindings: _shortcuts(rows, canReview),
      child: Focus(
        autofocus: true,
        child: SelPageBody(
          // Chosen rows: the same pinned bar as Letters, so approving many
          // stays in reach however far down the list you are.
          bottomBar: widget.mode == QueueMode.records || !canReview
              ? null
              : () {
                  final chosen = [for (final e in rows) if (_selected.contains(e.id)) e];
                  if (chosen.isEmpty) return null;
                  final names = chosen
                      .map((e) => e.partnerSnapshot['fullName']?.toString() ?? '')
                      .where((n) => n.isNotEmpty)
                      .toList();
                  final who = names.length <= 2
                      ? names.join(' and ')
                      : '${names.take(2).join(', ')} and ${names.length - 2} more';
                  return SelChoiceBar(
                    count: chosen.length,
                    note: '${money(chosen.fold<double>(0, (s, e) => s + e.amountCedis))} · $who',
                    busy: _busy,
                    action: 'Approve ${chosen.length}',
                    onClear: () => setState(_selected.clear),
                    onAction: () => _approve(chosen),
                  );
                }(),
          onRefresh: widget.mode == QueueMode.records
              ? () => _loadRecordsPage(reset: true)
              : () async {
                  ref.invalidate(pendingEntriesProvider);
                  invalidateEntryDerivedData(ref);
                },
          children: [
            SelPageTitle(
              title: widget.mode == QueueMode.queue
                  ? l10n.queueTitle
                  : l10n.navRecordsAll,
              subtitle: widget.mode == QueueMode.queue
                  ? (all.isEmpty
                        ? l10n.queueSubtitle
                        : '${all.length} ${all.length == 1 ? 'entry' : 'entries'} waiting · '
                              '${money(all.fold<double>(0, (s, e) => s + e.amountCedis))} · '
                              '${isPastor ? 'totals change only when you approve' : 'they count once a pastor approves them'}')
                  : 'Every giving entry, newest first',
              actions: [
                if (widget.mode == QueueMode.records)
                  EntryExportButtons(
                    entries: rows,
                    title: 'Records',
                    subtitle: _filterDescription(rows.length),
                  ),
                if (widget.mode == QueueMode.records)
                  const SizedBox(width: SelSpace.x2),
                if (widget.mode == QueueMode.queue && arms.isNotEmpty) ...[
                  SizedBox(
                    width: 170,
                    child: SelSelect<String?>(
                      value: _armId,
                      onChanged: (v) => setState(() => _armId = v),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(l10n.queueAllArms),
                        ),
                        for (final a in armTree.mains)
                          if (arms.any((x) => x.id == a.id))
                            DropdownMenuItem(value: a.id, child: Text(a.name)),
                      ],
                    ),
                  ),
                  const SizedBox(width: SelSpace.x2),
                ],
                if (widget.mode == QueueMode.records)
                  SelButton(
                    label: 'Import a sheet',
                    icon: LucideIcons.upload,
                    onPressed: () => context.go('/entries/bulk-import'),
                  ),
                if (idx?.isStaff == true || isPastor) ...[
                  const SizedBox(width: SelSpace.x2),
                  SelButton.cyan(
                    label: l10n.actionNewEntry,
                    icon: LucideIcons.plus,
                    onPressed: () => showEntryFormPanel(context),
                  ),
                ],
              ],
            ),

            if (canBulk && widget.mode == QueueMode.records) ...[
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

            if (widget.mode == QueueMode.records && _recordsLoading)
              const SelCard(child: SelSkeletonRows())
            else if (widget.mode == QueueMode.records && _recordsError != null)
              SelError(
                message: _recordsError!,
                onRetry: () => _loadRecordsPage(reset: true),
              )
            else if (widget.mode == QueueMode.records)
              _RecordsCard(
                all: scoped,
                rows: rows,
                arms: arms,
                pool: all,
                filter: _filter,
                onFilter: (f) => setState(() {
                  _filter = f;
                  _selected.clear();
                }),
                money: money,
                hasMore: _recordsHasMore,
                loadingMore: _recordsLoadingMore,
                onMore: () => _loadRecordsPage(),
                scrollController: _recordsScrollController,
                emptyAction: _filter == _Filter.all
                    ? () => showEntryFormPanel(context)
                    : null,
              )
            else
              entriesAsync.when(
                loading: () => const SelCard(child: SelSkeletonRows()),
                error: (e, _) => SelError(
                  message: plainError(e),
                  onRetry: () => ref.invalidate(pendingEntriesProvider),
                ),
                data: (_) => _QueueBoard(
                  rows: rows,
                  selected: _selected,
                  cursor: cursor,
                  canReview: canReview,
                  busy: _busy,
                  money: money,
                  onToggle: (id) => setState(
                    () => _selected.contains(id)
                        ? _selected.remove(id)
                        : _selected.add(id),
                  ),
                  onSelectAll: () => setState(() {
                    if (_selected.length == pendingInView.length) {
                      _selected.clear();
                    } else {
                      _selected
                        ..clear()
                        ..addAll(pendingInView.map((e) => e.id));
                    }
                  }),
                  onCursor: (i) => setState(() => _cursor = i),
                  onApprove: _approve,
                  onDecline: _decline,
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
                minWidth: 728,
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
                  const SelColumn(
                    '',
                    fit: SelColFit.fixed,
                    width: 88,
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
                          color: armColors[e.partnershipArmId],
                        ),
                        EntryAmountCell(
                          entry: e,
                          formattedAmount: money(e.amountCedis),
                          tone: _amountTone(e.status),
                        ),
                        SelStatusMark.fromString(
                          status: e.status,
                          label: _statusLabel(e.status),
                        ),
                        SelCell.secondary(_ago(now.difference(e.reviewedAt!))),
                        SelButton(
                          label: 'Undo',
                          kind: SelButtonKind.quiet,
                          dense: true,
                          onPressed: _busy ? null : () => _undoDecision(e),
                        ),
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
      'voided' || 'void' => l10n.statusVoided,
      _ => l10n.statusPending,
    };
  }

  SelTone _amountTone(String status) => switch (status) {
    'approved' => SelTone.positive,
    'declined' => SelTone.negative,
    _ => SelTone.neutral,
  };

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

    setState(() {
      _busy = true;
      _decidingIds
        ..clear()
        ..addAll(entries.map((e) => e.id));
    });
    try {
      await ref
          .read(entriesRepositoryProvider)
          .approveEntries(
            churchId: idx.churchId,
            entries: entries,
            pastor: pastor,
          );
      for (final e in entries) {
        await logPillrActivity(
          ref,
          churchId: idx.churchId,
          action: 'entry.approve',
          entityType: 'entry',
          entityId: e.id,
          entitySnapshot: {
            'amountCedis': e.amountCedis,
            'partnerName': e.partnerSnapshot['fullName'],
          },
        );
      }
      if (mounted) setState(() => _selected.clear());
      // The queue and the decided strip are live queries and correct already;
      // the dashboard totals are aggregates and have to be told.
      invalidateEntryDerivedData(ref);
      if (!mounted) return;
      final money = ref.read(churchMoneyFormatProvider);
      if (entries.length == 1) {
        final e = entries.first;
        final name =
            e.partnerSnapshot['fullName']?.toString() ?? 'this partner';
        selNotice(
          context,
          'Approved ${money(e.amountCedis)} for $name.',
          kind: SelNoticeKind.success,
        );
      } else {
        await ApprovalPlayback.show(
          context,
          entries: entries,
          formatMoney: money,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _decidingIds.clear();
        });
      }
    }
  }

  Future<void> _undoDecision(PartnershipEntry entry) async {
    if (_busy) return;
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    final pastor = ref.read(churchUserProfileProvider).valueOrNull;
    if (idx == null || pastor == null) return;

    final ok = await selConfirm(
      context,
      title: entry.status == 'approved'
          ? 'Undo this approval?'
          : 'Undo this send-back?',
      message: 'Puts the entry back on the queue as pending.',
      confirmLabel: 'Undo',
    );
    if (!ok) return;

    setState(() {
      _busy = true;
      _decidingIds
        ..clear()
        ..add(entry.id);
    });
    try {
      final action = entry.status == 'approved'
          ? 'entry.approve_undo'
          : 'entry.decline_undo';
      await ref.read(entriesRepositoryProvider).reopenEntry(
            churchId: idx.churchId,
            entry: entry,
            actor: pastor,
          );
      await logPillrActivity(
        ref,
        churchId: idx.churchId,
        action: action,
        entityType: 'entry',
        entityId: entry.id,
        entitySnapshot: {
          'amountCedis': entry.amountCedis,
          'partnerName': entry.partnerSnapshot['fullName'],
        },
      );
      invalidateEntryDerivedData(ref);
      if (mounted) {
        selNotice(
          context,
          'Returned to the queue.',
          kind: SelNoticeKind.success,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _decidingIds.clear();
        });
      }
    }
  }

  Future<void> _decline(PartnershipEntry entry) async {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    final pastor = ref.read(churchUserProfileProvider).valueOrNull;
    if (idx == null || pastor == null) return;

    final reason = await _askReason(context);
    if (reason == null || reason.trim().isEmpty) return;

    setState(() {
      _busy = true;
      _decidingIds
        ..clear()
        ..add(entry.id);
    });
    try {
      await ref
          .read(entriesRepositoryProvider)
          .declineEntry(
            churchId: idx.churchId,
            entry: entry,
            pastor: pastor,
            reason: reason,
          );
      await logPillrActivity(
        ref,
        churchId: idx.churchId,
        action: 'entry.decline',
        entityType: 'entry',
        entityId: entry.id,
        entitySnapshot: {
          'amountCedis': entry.amountCedis,
          'partnerName': entry.partnerSnapshot['fullName'],
        },
        metadata: {'reason': reason},
      );
      invalidateEntryDerivedData(ref);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _decidingIds.clear();
        });
      }
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

/// Records, as on the canvas: the status totals as tabs, the filters, the
/// table (Given, Partner, Fellowship, Arm, Amount, Status, Entered by) and
/// the pager, all in one card.
class _RecordsCard extends ConsumerWidget {
  const _RecordsCard({
    required this.all,
    required this.rows,
    required this.arms,
    required this.pool,
    required this.filter,
    required this.onFilter,
    required this.money,
    required this.hasMore,
    required this.loadingMore,
    required this.onMore,
    required this.scrollController,
    this.emptyAction,
  });

  final List<PartnershipEntry> all;
  final List<PartnershipEntry> rows;
  final List<dynamic> arms;
  final List<PartnershipEntry> pool;
  final _Filter filter;
  final ValueChanged<_Filter> onFilter;
  final String Function(num) money;
  final bool hasMore;
  final bool loadingMore;
  final VoidCallback onMore;
  final ScrollController scrollController;
  final VoidCallback? emptyAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(armTreeProvider);
    final byPartner = ref.watch(partnerFellowshipByIdProvider);
    (int, double) sum(bool Function(PartnershipEntry) f) {
      final list = all.where(f);
      return (list.length, list.fold(0.0, (s, e) => s + e.amountCedis));
    }

    final tabs = [
      (_Filter.all, 'All', sum((_) => true)),
      (_Filter.approved, 'Approved', sum((e) => e.status == 'approved')),
      (_Filter.pending, 'Waiting', sum((e) => e.status == 'pending')),
      (_Filter.declined, 'Declined', sum((e) => e.status == 'declined')),
    ];

    return SelCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Sel.border)),
            ),
            child: Row(
              children: [
                for (final (f, label, (n, total)) in tabs)
                  Expanded(
                    child: InkWell(
                      onTap: () => onFilter(f),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(24, 22, 16, 18),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: f == filter ? Sel.ink : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              f == _Filter.all
                                  ? '$label · $n entries'
                                  : '$label · $n',
                              style: SelType.small.copyWith(
                                color: f == filter ? Sel.ink : Sel.warm,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              money(total),
                              style: SelType.subtitle.copyWith(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: f == filter ? Sel.ink : Sel.ink.withValues(alpha: 0.85),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
            child: RecordFilterBar(entries: pool, arms: arms.cast()),
          ),
          SelLedger.builder(
            bare: true,
            scrollController: scrollController,
            maxVirtualHeight: 720,
            rowExtent: kSelLedgerStackedRowExtent,
            minWidth: 900,
            columns: const [
              SelColumn('Given', fit: SelColFit.fixed, width: 96),
              SelColumn('Partner', flex: 3),
              SelColumn('Fellowship', flex: 2),
              SelColumn('Arm', flex: 2),
              SelColumn.numeric('Amount', width: 150),
              SelColumn('Status', fit: SelColFit.fixed, width: 130),
              SelColumn('Entered by', flex: 2),
            ],
            emptyState: SelEmpty(
              title: filter == _Filter.all ? 'No entries yet' : 'Nothing here',
              message: filter == _Filter.all
                  ? 'Record giving or bring in a sheet to start.'
                  : 'Nothing matches what you picked above.',
              actionLabel: emptyAction == null ? null : 'Record giving',
              onAction: emptyAction,
            ),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final e = rows[i];
              final memberId = e.partnerSnapshot['memberId']?.toString() ?? '';
              return SelRow(
                onTap: () => context.go('/entries/${e.id}'),
                cells: [
                  SelCell.secondary(
                    formatFirestoreDate(e.dateGiven, pattern: 'd MMM'),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        e.partnerSnapshot['fullName']?.toString() ?? '—',
                        style: SelType.body.copyWith(
                          color: Sel.text,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (memberId.isNotEmpty)
                        Text(
                          memberId,
                          style: SelType.small.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  SelCell.secondary(fellowshipLabelOf(e, byPartner)),
                  SelCell.secondary(
                    tree.shownNameOf(e.partnershipArmId) ??
                        e.armSnapshot['name']?.toString() ??
                        '—',
                  ),
                  EntryAmountCell(
                    entry: e,
                    formattedAmount: money(e.amountCedis),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelStatusMark.fromString(
                      status: e.status,
                      label: switch (e.status) {
                        'approved' => 'Approved',
                        'declined' => 'Declined',
                        'voided' => 'Voided',
                        _ => 'Waiting',
                      },
                    ),
                  ),
                  Text(
                    e.importBatchId != null
                        ? 'Brought in from a sheet'
                        : e.createdBySnapshot['fullName']?.toString() ?? '',
                    style: SelType.small,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
            child: Row(
              children: [
                Text(
                  rows.isEmpty
                      ? 'No entries'
                      : '1–${rows.length} of ${hasMore ? '${all.length}+' : all.length}',
                  style: SelType.small,
                ),
                const Spacer(),
                if (loadingMore)
                  const PillrLoader(size: 22)
                else if (hasMore)
                  SelButton(label: 'Load more', dense: true, onPressed: onMore),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The Queue, as on the canvas: the waiting entries grouped by age with a
/// navy bar for what is selected, and the entry under the cursor open on the
/// right with Approve and Decline.
class _QueueBoard extends ConsumerWidget {
  const _QueueBoard({
    required this.rows,
    required this.selected,
    required this.cursor,
    required this.canReview,
    required this.busy,
    required this.money,
    required this.onToggle,
    required this.onSelectAll,
    required this.onCursor,
    required this.onApprove,
    required this.onDecline,
  });

  final List<PartnershipEntry> rows;
  final Set<String> selected;
  final int cursor;
  final bool canReview;
  final bool busy;
  final String Function(num) money;
  final ValueChanged<String> onToggle;
  final VoidCallback onSelectAll;
  final ValueChanged<int> onCursor;
  final Future<void> Function(List<PartnershipEntry>) onApprove;
  final Future<void> Function(PartnershipEntry) onDecline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (rows.isEmpty) {
      return const SelCard(
        child: SelEmpty(
          title: 'All caught up',
          message: 'Nothing is waiting on a decision.',
        ),
      );
    }
    final tree = ref.watch(armTreeProvider);
    final now = DateTime.now();
    int age(PartnershipEntry e) => now.difference(e.createdAt).inDays;
    final old = [for (final e in rows) if (age(e) > 30) e];
    final fresh = [for (final e in rows) if (age(e) <= 30) e];
    final current = cursor >= 0 && cursor < rows.length ? rows[cursor] : null;

    Widget group(String title, List<PartnershipEntry> es) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: Sel.rowHover,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$title · ${es.length}',
                  style: SelType.small.copyWith(
                    color: Sel.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                money(es.fold<double>(0, (s, e) => s + e.amountCedis)),
                style: SelType.small.copyWith(
                  color: Sel.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        for (final e in es) ...[
          const Divider(height: 1, color: Sel.rowLine),
          Material(
            color: rows.indexOf(e) == cursor ? Sel.skyTint : Sel.card,
            child: InkWell(
              onTap: () => onCursor(rows.indexOf(e)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 24, 12),
                child: Row(
                  children: [
                    if (canReview)
                      Checkbox(
                        value: selected.contains(e.id),
                        activeColor: Sel.cyan,
                        onChanged: (_) => onToggle(e.id),
                      )
                    else
                      const SizedBox(width: SelSpace.x3),
                    const SizedBox(width: SelSpace.x2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.partnerSnapshot['fullName']?.toString() ?? '—',
                            style: SelType.body.copyWith(
                              color: Sel.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${tree.shownNameOf(e.partnershipArmId) ?? ''} · '
                            '${formatFirestoreDate(e.dateGiven, pattern: 'd MMM')} · '
                            '${e.importBatchId != null ? 'A sheet' : e.createdBySnapshot['fullName'] ?? ''}',
                            style: SelType.small,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: Text(
                        '${age(e)} ${age(e) == 1 ? 'day' : 'days'}',
                        textAlign: TextAlign.right,
                        style: SelType.bodySm,
                      ),
                    ),
                    SizedBox(
                      width: 130,
                      child: Text(
                        money(e.amountCedis),
                        textAlign: TextAlign.right,
                        style: SelType.bodyMedium.copyWith(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );

    final list = SelCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (old.isNotEmpty) group('Waiting over 30 days', old),
          if (fresh.isNotEmpty) group('This month', fresh),
        ],
      ),
    );

    final detail = current == null
        ? null
        : _QueueDetail(
            entry: current,
            money: money,
            canReview: canReview,
            busy: busy,
            onApprove: () => onApprove([current]),
            onDecline: () => onDecline(current),
          );

    return LayoutBuilder(
      builder: (context, c) => c.maxWidth < 980 || detail == null
          ? list
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: list),
                const SizedBox(width: SelSpace.x4),
                SizedBox(width: 360, child: detail),
              ],
            ),
    );
  }
}

class _QueueDetail extends ConsumerWidget {
  const _QueueDetail({
    required this.entry,
    required this.money,
    required this.canReview,
    required this.busy,
    required this.onApprove,
    required this.onDecline,
  });

  final PartnershipEntry entry;
  final String Function(num) money;
  final bool canReview;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(armTreeProvider);
    final name = entry.partnerSnapshot['fullName']?.toString() ?? '—';
    final words = name.split(' ').where((w) => w.isNotEmpty);
    final recent = (ref.watch(partnerEntriesProvider(entry.partnerId)).valueOrNull ??
            const <PartnershipEntry>[])
        .take(4)
        .toList();
    final full = money(entry.amountCedis);
    final dot = full.lastIndexOf('.');
    Widget fact(String k, String v) => Padding(
      padding: const EdgeInsets.only(bottom: SelSpace.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(k, style: SelType.bodySm)),
          Expanded(child: Text(v, style: SelType.body.copyWith(color: Sel.text))),
        ],
      ),
    );
    return SelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: Sel.skyWash, shape: BoxShape.circle),
                child: Text(
                  words.take(2).map((w) => w[0].toUpperCase()).join(),
                  style: SelType.tag.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: SelSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: SelType.subtitle),
                    InkWell(
                      onTap: () => context.go('/partners/${entry.partnerId}'),
                      child: Text(
                        '${entry.partnerSnapshot['memberId'] ?? ''} · Open partner',
                        style: SelType.small.copyWith(color: Sel.cyanEdge),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: SelSpace.x4),
          Text.rich(
            TextSpan(
              text: dot < 0 ? full : full.substring(0, dot),
              style: SelType.hero.copyWith(fontSize: 38),
              children: [
                if (dot >= 0)
                  TextSpan(
                    text: full.substring(dot),
                    style: SelType.subtitle.copyWith(color: Sel.warm),
                  ),
              ],
            ),
          ),
          const SizedBox(height: SelSpace.x4),
          fact('Arm', tree.fullNameOf(entry.partnershipArmId) ?? entry.armSnapshot['name']?.toString() ?? '—'),
          fact('Given on', formatFirestoreDate(entry.dateGiven, pattern: 'd MMM y')),
          if (entry.notes != null && entry.notes!.isNotEmpty) fact('Notes', entry.notes!),
          fact(
            'Entered by',
            '${entry.createdBySnapshot['fullName'] ?? '—'}, ${formatFirestoreDate(entry.createdAt, pattern: 'd MMM, HH:mm')}',
          ),
          if (recent.length > 1) ...[
            const SizedBox(height: SelSpace.x3),
            Text("${name.split(' ').first}'s recent giving", style: SelType.bodyMedium),
            const SizedBox(height: SelSpace.x2),
            Wrap(
              spacing: SelSpace.x2,
              runSpacing: SelSpace.x2,
              children: [
                for (final r in recent)
                  Container(
                    width: 150,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: r.id == entry.id ? Sel.skyTint : Sel.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: r.id == entry.id ? const Color(0xFF9ACFF6) : Sel.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${formatFirestoreDate(r.dateGiven, pattern: 'd MMM')}${r.id == entry.id ? ' · this' : ''}',
                          style: SelType.small,
                        ),
                        Text(money(r.amountCedis), style: SelType.bodyMedium),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          if (canReview) ...[
            const SizedBox(height: SelSpace.x6),
            Row(
              children: [
                Expanded(
                  child: SelButton.cyan(
                    label: 'Approve',
                    expanded: true,
                    loading: busy,
                    onPressed: onApprove,
                  ),
                ),
                const SizedBox(width: SelSpace.x3),
                Expanded(
                  child: SelButton(
                    label: 'Decline',
                    expanded: true,
                    onPressed: busy ? null : onDecline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: SelSpace.x3),
            Text(
              'A approve · D decline · J K next and previous',
              style: SelType.small,
            ),
          ],
          const SizedBox(height: SelSpace.x2),
          SelLink(
            label: 'Open the entry',
            onTap: () => context.go('/entries/${entry.id}'),
          ),
        ],
      ),
    );
  }
}
