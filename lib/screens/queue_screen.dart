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
        _recordsError = '$e';
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
    final compact = SelLayout.isCompact(MediaQuery.sizeOf(context).width);

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
              .where((e) => _armId == null || e.partnershipArmId == _armId)
              .toList();

    return CallbackShortcuts(
      bindings: _shortcuts(rows, canReview),
      child: Focus(
        autofocus: true,
        child: SelPageBody(
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
                  : l10n.recordsTitle,
              subtitle: widget.mode == QueueMode.queue
                  ? l10n.queueSubtitle
                  : l10n.recordsSubtitle,
              actions: [
                if (widget.mode == QueueMode.records)
                  EntryExportButtons(
                    entries: rows,
                    title: 'Records',
                    subtitle: _filterDescription(rows.length),
                  ),
                if (widget.mode == QueueMode.records && compact) ...[
                  const SizedBox(width: SelSpace.x2),
                  SelButton(
                    label: l10n.navRecordsMonthly,
                    icon: LucideIcons.calendar,
                    kind: SelButtonKind.quiet,
                    onPressed: () => context.go('/records/monthly'),
                  ),
                ],
                if (widget.mode == QueueMode.records) ...[
                  const SizedBox(width: SelSpace.x2),
                  SelButton(
                    label: 'Imports',
                    icon: LucideIcons.upload,
                    kind: SelButtonKind.quiet,
                    onPressed: () => context.go('/records/imports'),
                  ),
                ],
                if (widget.mode == QueueMode.records)
                  const SizedBox(width: SelSpace.x2),
                if (widget.mode == QueueMode.queue)
                  EntryExportButtons(
                    entries: rows,
                    title: 'Queue',
                    subtitle: _filterDescription(rows.length),
                  ),
                if (widget.mode == QueueMode.queue)
                  const SizedBox(width: SelSpace.x2),
                if (idx?.isStaff == true || isPastor)
                  SelButton.cyan(
                    label: l10n.actionNewEntry,
                    icon: LucideIcons.plus,
                    onPressed: () => showEntryFormPanel(context),
                  ),
                SelButton(
                  label: l10n.actionImport,
                  icon: LucideIcons.upload,
                  onPressed: () => context.go('/entries/bulk-import'),
                ),
              ],
            ),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Queue is a work list, so it has no status tabs: everything on it
                // is pending by definition. Records is the archive and keeps them.
                if (widget.mode == QueueMode.records)
                  Expanded(
                    child: _ShowRegion(
                      child: SelLabeledPillGroup<_Filter>(
                        label: 'Show',
                        selected: _filter,
                        onChanged: (f) => setState(() {
                          _filter = f;
                          _selected.clear();
                        }),
                        options: [
                          (
                            _Filter.all,
                            'All ${all.isEmpty ? "" : "(${all.length})"}'
                                .trim(),
                          ),
                          (_Filter.pending, 'Pending'),
                          (_Filter.approved, 'Approved'),
                          (_Filter.declined, 'Declined'),
                        ],
                      ),
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

            if (widget.mode == QueueMode.records && _recordsLoading)
              const SelCard(child: SelSkeletonRows())
            else if (widget.mode == QueueMode.records && _recordsError != null)
              SelError(
                message: _recordsError!,
                onRetry: () => _loadRecordsPage(reset: true),
              )
            else if (widget.mode == QueueMode.records)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SelLedger.builder(
                    scrollController: _recordsScrollController,
                    maxVirtualHeight: 640,
                    // Partner cell is two lines (name, who recorded it).
                    rowExtent: kSelLedgerStackedRowExtent,
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
                      title: _filter == _Filter.all
                          ? l10n.recordsEmptyTitle
                          : 'Nothing here',
                      message: _filter == _Filter.all
                          ? l10n.recordsEmptyMessage
                          : 'Nothing matches what you picked above.',
                      actionLabel: _filter == _Filter.all
                          ? l10n.recordsEmptyAction
                          : null,
                      onAction: _filter == _Filter.all
                          ? () => showEntryFormPanel(context)
                          : null,
                    ),
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final e = rows[i];
                      return SelRow(
                        onTap: () {
                          setState(() => _cursor = i);
                          context.go('/entries/${e.id}');
                        },
                        selected: _selected.contains(e.id),
                        cursor: i == cursor,
                        cells: [
                          SelCell.stacked(
                            e.partnerSnapshot['fullName']?.toString() ?? '—',
                            e.createdBySnapshot['fullName']?.toString() ?? '',
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
                          SelCell.secondary(
                            formatFirestoreDate(e.createdAt, pattern: 'd MMM'),
                          ),
                        ],
                      );
                    },
                  ),
                  if (_recordsLoadingMore)
                    const Padding(
                      padding: EdgeInsets.only(top: SelSpace.x4),
                      child: Center(
                        child: SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                ],
              )
            else
              entriesAsync.when(
                loading: () => const SelCard(child: SelSkeletonRows()),
                error: (e, _) => SelError(
                  message: '$e',
                  onRetry: () => ref.invalidate(pendingEntriesProvider),
                ),
                data: (_) => SelLedger.builder(
                  minWidth: 760,
                  maxVirtualHeight: 640,
                  // Partner cell is two lines (name, who recorded it).
                  rowExtent: kSelLedgerStackedRowExtent,
                  // Every row in this ledger carries a leading slot (a checkbox
                  // when bulk review is on, an empty box otherwise), so the
                  // leading column exists exactly when there are rows.
                  hasLeading: rows.isNotEmpty,
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
                        widget.mode == QueueMode.records &&
                            _filter == _Filter.all
                        ? l10n.recordsEmptyAction
                        : null,
                    onAction:
                        widget.mode == QueueMode.records &&
                            _filter == _Filter.all
                        ? () => showEntryFormPanel(context)
                        : null,
                  ),
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final e = rows[i];
                    return SelRow(
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
                        if (isPastor && e.status == 'pending')
                          _RowActions(
                            busy: _busy,
                            deciding: _decidingIds.contains(e.id),
                            onApprove: () => _approve([e]),
                            onDecline: () => _decline(e),
                          )
                        else
                          SelCell.secondary(
                            formatFirestoreDate(e.createdAt, pattern: 'd MMM'),
                          ),
                      ],
                    );
                  },
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

class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.busy,
    required this.deciding,
    required this.onApprove,
    required this.onDecline,
  });

  final bool busy;
  final bool deciding;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SelButton(
          label: l10n.queueSendBack,
          kind: SelButtonKind.quiet,
          dense: true,
          onPressed: busy ? null : onDecline,
        ),
        const SizedBox(width: SelSpace.x1),
        SelButton(
          label: deciding ? 'Approving…' : l10n.queueApprove,
          kind: SelButtonKind.edge,
          dense: true,
          loading: deciding,
          onPressed: busy ? null : onApprove,
        ),
      ],
    );
  }
}

/// Hairline box around the status pills so they read as a filter, not as
/// siblings of New entry.
class _ShowRegion extends StatelessWidget {
  const _ShowRegion({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Sel.card,
        borderRadius: BorderRadius.circular(SelRadius.card),
        border: Border.all(color: Sel.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          SelSpace.x4,
          SelSpace.x3,
          SelSpace.x4,
          SelSpace.x3,
        ),
        child: child,
      ),
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
