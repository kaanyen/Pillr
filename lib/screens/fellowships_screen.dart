import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../design/seline.dart';
import '../features/arms/domain/partnership_arm.dart';
import '../features/arms/providers/arms_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/entries/domain/partnership_entry.dart';
import '../features/entries/providers/entries_providers.dart';
import '../features/entries/providers/record_filters.dart';
import '../features/leaderboard/leaderboard_models.dart';
import '../features/leaderboard/leaderboard_providers.dart';
import '../features/partners/providers/partners_providers.dart';
import 'export_actions.dart';
import 'ranked_views.dart';
import 'record_filter_bar.dart';

enum _View { directory, ranked }

/// Fellowships — directory of groups, with giving rankings alongside.
///
/// Partners answers "who gives the most in the church?" Fellowships answers
/// "how do Bethel, Zion and Grace compare?" Tap a fellowship to see who
/// leads within that group.
class FellowshipsScreen extends ConsumerStatefulWidget {
  const FellowshipsScreen({
    super.key,
    this.initialView,
    this.initialFellowship,
  });

  final String? initialView;
  final String? initialFellowship;

  @override
  ConsumerState<FellowshipsScreen> createState() => _FellowshipsScreenState();
}

class _FellowshipsScreenState extends ConsumerState<FellowshipsScreen> {
  late _View _view = widget.initialView == 'ranked'
      ? _View.ranked
      : _View.directory;
  String _query = '';

  @override
  void initState() {
    super.initState();
    final fellowship = widget.initialFellowship?.trim().toLowerCase();
    if (fellowship != null && fellowship.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(recordFiltersProvider.notifier)
            .set(RecordFilters.empty.withFellowship(fellowship));
      });
    }
  }

  void _openFellowshipMembers(String fellowshipKey) {
    ref
        .read(recordFiltersProvider.notifier)
        .set(RecordFilters.empty.withFellowship(fellowshipKey));
    context.go(
      '/fellowships?view=ranked&fellowship=${Uri.encodeComponent(fellowshipKey)}',
    );
    setState(() => _view = _View.ranked);
  }

  void _backToAllFellowships() {
    ref.read(recordFiltersProvider.notifier).set(RecordFilters.empty);
    context.go('/fellowships?view=ranked');
  }

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(churchMoneyFormatProvider);
    final partnersAsync = ref.watch(partnersStreamProvider(false));
    // Same period-scoped set the rankings use; the filter bar draws its
    // options from it.
    final allEntries = ref.watch(rankingEntriesProvider).valueOrNull ?? const [];
    final arms =
        ref.watch(armsStreamProvider).valueOrNull ?? const <PartnershipArm>[];
    final filters = ref.watch(recordFiltersProvider);
    final fellowshipFilter = filters.fellowship?.toLowerCase();
    final showingMembers =
        _view == _View.ranked && fellowshipFilter != null && fellowshipFilter.isNotEmpty;

    return SelPageBody(
      onRefresh: () async {
        ref.invalidate(partnersStreamProvider(false));
        ref.invalidate(rankingEntriesProvider);
        invalidateEntryDerivedData(ref);
      },
      children: [
        SelPageTitle(
          title: 'Fellowships',
          subtitle: _view == _View.directory
              ? 'Every fellowship group in your church and what they have given this period.'
              : showingMembers
                  ? 'Partners ranked within this fellowship group.'
                  : 'Fellowships ranked by total approved giving.',
          actions: [
            if (_view == _View.ranked)
              EntryExportButtons(
                entriesLoader: () => loadEntriesForExport(ref),
                title: showingMembers
                    ? 'Fellowship member ranking'
                    : 'Fellowship ranking',
                subtitle: showingMembers
                    ? 'Partners ranked within this fellowship'
                    : 'Fellowships ranked by approved giving',
              ),
            if (_view == _View.ranked) const SizedBox(width: SelSpace.x2),
          ],
        ),

        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SelPillGroup<_View>(
                  selected: _view,
                  onChanged: (v) => setState(() => _view = v),
                  options: const [
                    (_View.directory, 'Directory'),
                    (_View.ranked, 'Ranked'),
                  ],
                ),
                const Spacer(),
                if (_view == _View.directory)
                  SizedBox(
                    width: 240,
                    child: SelField(
                      hint: 'Search fellowship',
                      prefixIcon: LucideIcons.search,
                      onChanged: (v) =>
                          setState(() => _query = v.trim().toLowerCase()),
                    ),
                  ),
              ],
            ),
          ],
        ),

        const SizedBox(height: SelSpace.x6),

        if (_view == _View.directory)
          partnersAsync.when(
            loading: () => const SelCard(child: SelSkeletonRows()),
            error: (e, _) => SelError(message: '$e'),
            data: (_) => _FellowshipDirectory(
              query: _query,
              money: money,
              onOpenFellowship: _openFellowshipMembers,
            ),
          )
        else
          _FellowshipRankedView(
            money: money,
            all: allEntries,
            arms: arms,
            filters: filters,
            onOpenFellowship: _openFellowshipMembers,
            onBackToAll: _backToAllFellowships,
          ),
      ],
    );
  }
}

/// Isolated from [FellowshipsScreen.build] so a directory compute error cannot
/// blank the title and view switch. Production was throwing in the parent
/// `build` and leaving an empty canvas.
class _FellowshipDirectory extends ConsumerWidget {
  const _FellowshipDirectory({
    required this.query,
    required this.money,
    required this.onOpenFellowship,
  });

  final String query;
  final String Function(num) money;
  final ValueChanged<String> onOpenFellowship;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    late final List<FellowshipDirectoryRow> rows;
    try {
      rows = [
        for (final row in ref.watch(fellowshipDirectoryProvider(false)))
          if (query.isEmpty ||
              row.fellowshipName.toLowerCase().contains(query))
            row,
      ];
    } catch (e) {
      return SelError(message: '$e');
    }

    return SelLedger(
      minWidth: 640,
      columns: const [
        SelColumn('Fellowship', flex: 3),
        SelColumn.numeric('Partners', width: 110),
        SelColumn.numeric('Approved this period', width: 190),
      ],
      emptyState: SelEmpty(
        title: query.isEmpty ? 'No fellowships yet' : 'No matches',
        message: query.isEmpty
            ? 'Fellowships appear once partners are assigned to a group.'
            : 'Nothing matches “$query”.',
        icon: LucideIcons.users,
      ),
      rows: [
        for (final row in rows)
          SelRow(
            onTap: () => onOpenFellowship(row.fellowshipKey),
            cells: [
              SelCell.primary(row.fellowshipName),
              SelCell.numeric('${row.partnerCount}'),
              SelCell.numeric(money(row.periodTotalCedis)),
            ],
          ),
      ],
    );
  }
}

class _FellowshipRankedView extends ConsumerWidget {
  const _FellowshipRankedView({
    required this.money,
    required this.all,
    required this.arms,
    required this.filters,
    required this.onOpenFellowship,
    required this.onBackToAll,
  });

  final String Function(num) money;
  final List<PartnershipEntry> all;
  final List<PartnershipArm> arms;
  final RecordFilters filters;
  final ValueChanged<String> onOpenFellowship;
  final VoidCallback onBackToAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fellowshipFilter = filters.fellowship?.toLowerCase();

    if (fellowshipFilter != null && fellowshipFilter.isNotEmpty) {
      return _FellowshipMembersDetail(
        money: money,
        all: all,
        arms: arms,
        filters: filters,
        fellowshipKey: fellowshipFilter,
        onBack: onBackToAll,
      );
    }

    late final List<FellowshipRankRow> rows;
    try {
      rows = ref.watch(fellowshipRankingProvider);
    } catch (e) {
      return SelError(message: '$e');
    }

    if (rows.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RecordFilterBar(entries: all, arms: arms),
          const SizedBox(height: SelSpace.x4),
          SelCard(
            child: SelEmpty(
              title: filters.isEmpty ? 'Nothing ranked yet' : 'Nothing matches',
              message: filters.isEmpty
                  ? 'Rankings appear once entries are approved in this period.'
                  : 'No approved giving matches these filters.',
              icon: LucideIcons.trophy,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RecordFilterBar(entries: all, arms: arms),
        const SizedBox(height: SelSpace.x4),
        SelLedger(
          minWidth: 560,
          columns: const [
            SelColumn('Rank', fit: SelColFit.fixed, width: 70),
            SelColumn('Fellowship', flex: 3),
            SelColumn.numeric('Partners', width: 110),
            SelColumn.numeric('Approved giving', width: 170),
          ],
          rows: [
            for (final row in rows)
              SelRow(
                onTap: () => onOpenFellowship(row.fellowshipKey),
                cells: [
                  Text(
                    '${row.rank}',
                    style: SelType.body.copyWith(
                      color: row.rank <= 3 ? Sel.ink : Sel.ash,
                      fontWeight:
                          row.rank <= 3 ? FontWeight.w500 : FontWeight.w400,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  SelCell.primary(row.fellowshipName),
                  SelCell.numeric('${row.partnerCount}'),
                  SelCell.numeric(money(row.totalCedis)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _FellowshipMembersDetail extends ConsumerWidget {
  const _FellowshipMembersDetail({
    required this.money,
    required this.all,
    required this.arms,
    required this.filters,
    required this.fellowshipKey,
    required this.onBack,
  });

  final String Function(num) money;
  final List<PartnershipEntry> all;
  final List<PartnershipArm> arms;
  final RecordFilters filters;
  final String fellowshipKey;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = ref.watch(fellowshipSectionsProvider);
    final section = sections
        .where((s) => s.fellowshipKey == fellowshipKey)
        .firstOrNull;

    return RankedGroupedBody(
      money: money,
      all: all,
      arms: arms,
      filters: filters,
      intro: SelButton(
        label: 'All fellowships',
        icon: LucideIcons.arrowLeft,
        kind: SelButtonKind.quiet,
        dense: true,
        onPressed: onBack,
      ),
      sections: [
        if (section != null)
          RankGroupSection(
            title: section.fellowshipName,
            icon: LucideIcons.users,
            rows: section.rows,
            emptyTitle: 'Nothing ranked yet',
            emptyMessage:
                'Rankings appear once entries are approved for this fellowship.',
            trailing:
                '${section.rows.length} partners · ${money(section.totalCedis)}',
          ),
      ],
      requireAnyRows: section != null && section.rows.isNotEmpty,
    );
  }
}
