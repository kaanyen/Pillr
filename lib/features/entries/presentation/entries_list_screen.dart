import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:the_pillr/l10n/app_localizations.dart';

import '../../../common/widgets/pillr_badge.dart';
import '../../../common/widgets/pillr_button.dart';
import '../../../common/widgets/pillr_data_table.dart';
import '../../../common/widgets/pillr_dropdown_field.dart';
import '../../../common/widgets/pillr_segmented_control.dart';
import '../../../common/widgets/pillr_entity_card.dart';
import '../../../common/widgets/pillr_empty_state.dart';
import '../../../common/widgets/pillr_error_state.dart';
import '../../../common/widgets/pillr_loading_shimmer.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/pillr_layout.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/entry_export.dart';
import '../../../core/utils/currency_utils.dart';
import '../../arms/providers/arms_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../church/providers/church_settings_providers.dart';
import '../../periods/providers/periods_providers.dart';
import '../domain/partnership_entry.dart';
import '../providers/entries_providers.dart';

class EntriesListScreen extends ConsumerStatefulWidget {
  const EntriesListScreen({super.key});

  @override
  ConsumerState<EntriesListScreen> createState() => _EntriesListScreenState();
}

class _EntriesListScreenState extends ConsumerState<EntriesListScreen> {
  final List<PartnershipEntry> _items = [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  String? _streamFingerprint;
  bool _exporting = false;
  bool _scheduledInitial = false;
  String? _filterArmId;
  String? _filterPeriodId;

  /// `all` | `pending` | `approved` | `declined`
  String _statusSegment = 'all';
  bool _newestFirst = true;

  String? get _statusFilterParam => _statusSegment == 'all' ? null : _statusSegment;

  void _ensureInitialLoad() {
    final i = ref.read(userChurchIndexProvider).valueOrNull;
    if (i == null || _scheduledInitial) return;
    _scheduledInitial = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadFirst();
    });
  }

  Future<void> _loadFirst() async {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(entriesRepositoryProvider);
      final page = await repo.fetchEntriesPage(
        idx.churchId,
        allChurchEntries: idx.isPastor,
        createdByUid: idx.isPastor ? null : idx.uid,
        statusFilter: _statusFilterParam,
        newestFirst: _newestFirst,
        pageSize: 20,
      );
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _cursor = page.lastDoc;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null) return;
    setState(() => _loadingMore = true);
    try {
      final repo = ref.read(entriesRepositoryProvider);
      final page = await repo.fetchEntriesPage(
        idx.churchId,
        allChurchEntries: idx.isPastor,
        createdByUid: idx.isPastor ? null : idx.uid,
        statusFilter: _statusFilterParam,
        newestFirst: _newestFirst,
        pageSize: 20,
        startAfter: _cursor,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.lastDoc;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loadingMore = false;
      });
    }
  }

  Future<void> _exportPdf() async {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      final repo = ref.read(entriesRepositoryProvider);
      final rows = await repo.fetchAllEntriesForExport(
        idx.churchId,
        allChurchEntries: idx.isPastor,
        createdByUid: idx.isPastor ? null : idx.uid,
      );
      final churchName = ref.read(churchNameProvider) ?? 'Church';
      if (!mounted) return;
      final logoUrl = ref.read(churchSettingsProvider).valueOrNull?.logoUrl;
      final l10n = AppLocalizations.of(context);
      final profile = ref.read(churchUserProfileProvider).valueOrNull;
      final email = ref.read(firebaseAuthProvider).currentUser?.email;
      final exporter =
          (profile?.fullName.isNotEmpty == true) ? profile!.fullName : (email ?? '—');
      final when = DateFormat.yMMMd(Localizations.localeOf(context).toString()).add_Hm().format(DateTime.now());
      await shareEntriesPdf(
        title: l10n.entriesPdfTitle,
        subtitle: churchName,
        columnHeaders: [
          l10n.pdfTableHeaderPartner,
          l10n.pdfTableHeaderAmount,
          l10n.pdfTableHeaderStatus,
          l10n.pdfTableHeaderPeriod,
          l10n.pdfTableHeaderArm,
          l10n.pdfTableHeaderDateGiven,
        ],
        entries: rows,
        logoUrl: logoUrl,
        generatedAtLine: l10n.pdfGeneratedAt(when),
        exporterLine: l10n.pdfExporter(exporter),
        footerBrand: l10n.pdfFooterBrand,
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportCsv() async {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      final repo = ref.read(entriesRepositoryProvider);
      final rows = await repo.fetchAllEntriesForExport(
        idx.churchId,
        allChurchEntries: idx.isPastor,
        createdByUid: idx.isPastor ? null : idx.uid,
      );
      final csv = entriesToCsv(rows);
      if (!mounted) return;
      await shareEntriesCsv(csv);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _onStatusSegmentChanged(String segment) {
    setState(() => _statusSegment = segment);
    _cursor = null;
    _hasMore = true;
    _loadFirst();
  }

  void _onSortChanged(bool newest) {
    if (_newestFirst == newest) return;
    setState(() => _newestFirst = newest);
    _cursor = null;
    _hasMore = true;
    _loadFirst();
  }

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final l10n = AppLocalizations.of(context);

    ref.listen(userChurchIndexProvider, (prev, next) {
      final pc = prev?.valueOrNull?.churchId;
      final nc = next.valueOrNull?.churchId;
      if (pc != nc) {
        _items.clear();
        _cursor = null;
        _hasMore = true;
        _streamFingerprint = null;
        _scheduledInitial = false;
        _statusSegment = 'all';
        _newestFirst = true;
        _ensureInitialLoad();
      }
    });

    ref.listen(entriesListProvider, (prev, next) {
      next.maybeWhen(
        data: (list) {
          final fp = '${list.length}:${list.isEmpty ? '' : list.first.id}';
          if (fp == _streamFingerprint) return;
          _streamFingerprint = fp;
          _loadFirst();
        },
        orElse: () {},
      );
    });

    if (idx != null) {
      _ensureInitialLoad();
    }

    final arms = ref.watch(armsStreamProvider).valueOrNull ?? [];
    final periods = ref.watch(periodsStreamProvider).valueOrNull ?? [];
    var displayItems = _items;
    if (_filterArmId != null) {
      displayItems = displayItems.where((e) => e.partnershipArmId == _filterArmId).toList();
    }
    if (_filterPeriodId != null) {
      displayItems = displayItems.where((e) => e.partnershipPeriodId == _filterPeriodId).toList();
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final narrow = c.maxWidth < 640;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (narrow)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        idx?.isPastor == true ? l10n.entriesHeadingAll : l10n.entriesHeadingMine,
                        style: AppTypography.heading2,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        idx?.isPastor == true ? l10n.entriesSubtitleAll : l10n.entriesSubtitleMine,
                        style: AppTypography.body,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          if (idx != null) ...[
                            PillrButton(
                              label: l10n.entriesExportPdf,
                              icon: LucideIcons.fileDown,
                              onPressed: _exporting ? null : _exportPdf,
                              variant: PillrButtonVariant.secondary,
                            ),
                            PillrButton(
                              label: l10n.entriesExportCsv,
                              icon: LucideIcons.table2,
                              onPressed: _exporting ? null : _exportCsv,
                              variant: PillrButtonVariant.secondary,
                            ),
                          ],
                          if (idx != null && (idx.isPastor || idx.isStaff)) ...[
                            PillrButton(
                              label: l10n.entriesBulkImport,
                              icon: LucideIcons.layoutList,
                              onPressed: () => context.go('/entries/bulk-import'),
                              variant: PillrButtonVariant.secondary,
                            ),
                            PillrButton(
                              label: l10n.entriesNewEntry,
                              icon: LucideIcons.plus,
                              onPressed: () => context.go('/entries/new'),
                              variant: PillrButtonVariant.primary,
                            ),
                          ],
                        ],
                      ),
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              idx?.isPastor == true ? l10n.entriesHeadingAll : l10n.entriesHeadingMine,
                              style: AppTypography.heading2,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              idx?.isPastor == true ? l10n.entriesSubtitleAll : l10n.entriesSubtitleMine,
                              style: AppTypography.body,
                            ),
                          ],
                        ),
                      ),
                      if (idx != null) ...[
                        Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.sm),
                          child: PillrButton(
                            label: l10n.entriesExportPdf,
                            icon: LucideIcons.fileDown,
                            onPressed: _exporting ? null : _exportPdf,
                            variant: PillrButtonVariant.secondary,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.sm),
                          child: PillrButton(
                            label: l10n.entriesExportCsv,
                            icon: LucideIcons.table2,
                            onPressed: _exporting ? null : _exportCsv,
                            variant: PillrButtonVariant.secondary,
                          ),
                        ),
                      ],
                      if (idx != null && (idx.isPastor || idx.isStaff)) ...[
                        Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.sm),
                          child: PillrButton(
                            label: l10n.entriesBulkImport,
                            icon: LucideIcons.layoutList,
                            onPressed: () => context.go('/entries/bulk-import'),
                            variant: PillrButtonVariant.secondary,
                          ),
                        ),
                        PillrButton(
                          label: l10n.entriesNewEntry,
                          icon: LucideIcons.plus,
                          onPressed: () => context.go('/entries/new'),
                          variant: PillrButtonVariant.primary,
                        ),
                      ],
                    ],
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        if (idx != null && (idx.isPastor || idx.isStaff)) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: PillrSegmentedControl<String>(
              segments: [
                PillrSegment(value: 'all', label: l10n.entriesStatusAll, icon: LucideIcons.list),
                PillrSegment(value: 'pending', label: l10n.entriesStatusPending, icon: LucideIcons.clock),
                PillrSegment(value: 'approved', label: l10n.entriesStatusApproved, icon: LucideIcons.checkCircle),
                PillrSegment(value: 'declined', label: l10n.entriesStatusDeclined, icon: LucideIcons.xCircle),
              ],
              selected: _statusSegment,
              onChanged: _onStatusSegmentChanged,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: PillrSegmentedControl<bool>(
              segments: [
                PillrSegment(value: true, label: l10n.entriesSortNewest),
                PillrSegment(value: false, label: l10n.entriesSortOldest),
              ],
              selected: _newestFirst,
              onChanged: _onSortChanged,
              accentSelection: false,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (idx != null)
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.entriesArmLabel, style: AppTypography.caption),
                  SizedBox(
                    width: 220,
                    child: PillrDropdownButton<String?>(
                      value: _filterArmId,
                      hint: Text(l10n.entriesAllArms, style: AppTypography.body.copyWith(color: AppColors.gray400)),
                      items: [
                        DropdownMenuItem<String?>(value: null, child: Text(l10n.entriesAllArms)),
                        for (final a in arms)
                          DropdownMenuItem<String?>(value: a.id, child: Text(a.name)),
                      ],
                      onChanged: (v) => setState(() => _filterArmId = v),
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.entriesPeriodLabel, style: AppTypography.caption),
                  SizedBox(
                    width: 220,
                    child: PillrDropdownButton<String?>(
                      value: _filterPeriodId,
                      hint: Text(l10n.entriesAllPeriods, style: AppTypography.body.copyWith(color: AppColors.gray400)),
                      items: [
                        DropdownMenuItem<String?>(value: null, child: Text(l10n.entriesAllPeriods)),
                        for (final p in periods)
                          DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
                      ],
                      onChanged: (v) => setState(() => _filterPeriodId = v),
                    ),
                  ),
                ],
              ),
              Text(
                l10n.entriesFilterHint,
                style: AppTypography.caption,
              ),
            ],
          ),
        const SizedBox(height: AppSpacing.md),
        if (!_loading && idx != null && _items.isNotEmpty)
          Text(
            l10n.entriesShowingLoaded(_items.length, _hasMore ? l10n.entriesMoreAvailable : ''),
            style: AppTypography.caption,
          ),
        const SizedBox(height: AppSpacing.sm),
        if (idx == null)
          const PillrLoadingShimmer(height: 200)
        else if (_loading)
          const PillrLoadingShimmer(height: 200)
        else if (_error != null)
          PillrErrorState(
            message: _error.toString(),
            onRetry: _loadFirst,
          )
        else if (_items.isEmpty)
          PillrEmptyState(
            title: l10n.entriesNoEntriesTitle,
            message: l10n.entriesNoEntriesMessage,
            actionLabel: l10n.entriesNewEntry,
            onAction: idx.isPastor || idx.isStaff ? () => context.go('/entries/new') : null,
          )
        else if (displayItems.isEmpty)
          PillrEmptyState(
            title: l10n.entriesNoMatchesTitle,
            message: l10n.entriesNoMatchesMessage,
            actionLabel: l10n.entriesClearFilters,
            onAction: () => setState(() {
              _filterArmId = null;
              _filterPeriodId = null;
            }),
          )
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final useCards = PillrLayout.useCardListLayout(constraints.maxWidth);
              final dateFmt = (PartnershipEntry e) =>
                  '${e.createdAt.year}-${e.createdAt.month.toString().padLeft(2, '0')}-${e.createdAt.day.toString().padLeft(2, '0')}';
              final table = PillrDataTable(
                minWidth: 720,
                sortColumnIndex: 0,
                sortAscending: false,
                columns: [
                  DataColumn2(label: Text(l10n.entriesColPartner, style: AppTypography.tableHeader), size: ColumnSize.L),
                  DataColumn2(label: Text(l10n.entriesColAmount, style: AppTypography.tableHeader)),
                  DataColumn2(label: Text(l10n.entriesColStatus, style: AppTypography.tableHeader)),
                  DataColumn2(label: Text(l10n.entriesColSubmitted, style: AppTypography.tableHeader)),
                ],
                rows: [
                  for (final e in displayItems)
                    DataRow2(
                      onTap: () => context.go('/entries/${e.id}'),
                      cells: [
                        DataCell(Text(
                          e.partnerSnapshot['fullName']?.toString() ?? '—',
                          style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
                        )),
                        DataCell(Text(formatCedis(e.amountCedis), style: AppTypography.body)),
                        DataCell(_AnimatedStatusBadge(key: ValueKey('${e.id}-${e.status}'), status: e.status, l10n: l10n)),
                        DataCell(Text(
                          dateFmt(e),
                          style: AppTypography.caption,
                        )),
                      ],
                    ),
                ],
              );
              final cardList = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final e in displayItems)
                    PillrEntityCard(
                      onTap: () => context.go('/entries/${e.id}'),
                      title: e.partnerSnapshot['fullName']?.toString() ?? '—',
                      subtitle:
                          '${l10n.entriesColAmount}: ${formatCedis(e.amountCedis)} · ${l10n.entriesColSubmitted}: ${dateFmt(e)}',
                      trailing: _AnimatedStatusBadge(key: ValueKey('c-${e.id}-${e.status}'), status: e.status, l10n: l10n),
                    ),
                ],
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  useCards ? cardList : table,
                  if (_hasMore) ...[
                    const SizedBox(height: AppSpacing.md),
                    Center(
                      child: PillrButton(
                        label: _loadingMore ? l10n.entriesLoadingMore : l10n.entriesLoadMore,
                        onPressed: _loadingMore ? null : _loadMore,
                        variant: PillrButtonVariant.secondary,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ],
    );

    return RefreshIndicator(
      onRefresh: _loadFirst,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: body,
      ),
    );
  }

}

Widget _entryStatusBadgeFor(String s, AppLocalizations l10n) {
  switch (s) {
    case 'approved':
      return PillrBadge(label: l10n.entriesStatusApproved, kind: PillrBadgeKind.approved, compact: true);
    case 'declined':
      return PillrBadge(label: l10n.entriesStatusDeclined, kind: PillrBadgeKind.inactive, compact: true);
    default:
      return PillrBadge(label: l10n.entriesStatusPending, kind: PillrBadgeKind.pending, compact: true);
  }
}

class _AnimatedStatusBadge extends StatelessWidget {
  const _AnimatedStatusBadge({super.key, required this.status, required this.l10n});

  final String status;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Padding(
        key: ValueKey(status),
        padding: EdgeInsets.zero,
        child: _entryStatusBadgeFor(status, l10n),
      ),
    );
  }
}
