import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/navigation/panel_flows.dart';
import '../design/seline.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/arms/domain/partnership_arm.dart';
import '../features/arms/providers/arms_providers.dart';
import '../features/entries/domain/partnership_entry.dart';
import '../features/entries/providers/entries_providers.dart';
import '../features/entries/providers/record_filters.dart';
import '../features/leaderboard/leaderboard_providers.dart';
import '../features/partners/providers/partners_providers.dart';
import 'export_actions.dart';
import 'ranked_views.dart';
import 'record_filter_bar.dart';

enum _View { directory, ranked }

enum _RankedScope { overall, byArm }

/// Partners — the directory, with Leaderboard folded in as a second view.
///
/// Leaderboard was never a separate concern: it is the same partner records
/// ordered by approved giving. Making it a view toggle rather than a nav item
/// removes a destination and puts the ranking one click from the profile it
/// describes.
class PartnersScreen extends ConsumerStatefulWidget {
  const PartnersScreen({super.key, this.initialView});

  /// Lets `/leaderboard` land here on the ranked view.
  final String? initialView;

  @override
  ConsumerState<PartnersScreen> createState() => _PartnersScreenState();
}

class _PartnersScreenState extends ConsumerState<PartnersScreen> {
  late _View _view = widget.initialView == 'ranked'
      ? _View.ranked
      : _View.directory;
  _RankedScope _rankedScope = _RankedScope.overall;
  bool _includeInactive = false;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final money = ref.watch(churchMoneyFormatProvider);
    final partnersAsync = ref.watch(partnersStreamProvider(_includeInactive));

    return SelPageBody(
      onRefresh: () async {
        ref.invalidate(partnersStreamProvider(_includeInactive));
        ref.invalidate(rankingEntriesProvider);
        invalidateEntryDerivedData(ref);
      },
      children: [
        SelPageTitle(
          title: 'Partners',
          subtitle: _view == _View.directory
              ? 'Everyone with a giving record in your church.'
              : switch (_rankedScope) {
                  _RankedScope.overall =>
                    'Ranked by approved giving in the active period.',
                  _RankedScope.byArm =>
                    'Ranked by approved giving within each partnership arm.',
                },
          actions: [
            if (_view == _View.ranked)
              EntryExportButtons(
                entriesLoader: () => loadEntriesForExport(ref),
                title: switch (_rankedScope) {
                  _RankedScope.overall => 'Partner ranking',
                  _RankedScope.byArm => 'Partner ranking by arm',
                },
                subtitle: switch (_rankedScope) {
                  _RankedScope.overall => 'Ranked by approved giving',
                  _RankedScope.byArm => 'Ranked by approved giving per arm',
                },
              ),
            if (_view == _View.ranked) const SizedBox(width: SelSpace.x2),
            SelButton.cyan(
              label: 'Add partner',
              icon: LucideIcons.plus,
              onPressed: idx == null
                  ? null
                  : () => showPartnerFormPanel(
                      context,
                      churchId: idx.churchId,
                      uid: idx.uid,
                    ),
            ),
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
                if (_view == _View.directory) ...[
                  SizedBox(
                    width: 240,
                    child: SelField(
                      hint: 'Search name or member ID',
                      prefixIcon: LucideIcons.search,
                      onChanged: (v) =>
                          setState(() => _query = v.trim().toLowerCase()),
                    ),
                  ),
                  const SizedBox(width: SelSpace.x3),
                  SelButton(
                    label: _includeInactive ? 'Hide inactive' : 'Show inactive',
                    kind: SelButtonKind.quiet,
                    dense: true,
                    onPressed: () =>
                        setState(() => _includeInactive = !_includeInactive),
                  ),
                ],
              ],
            ),
            if (_view == _View.ranked) ...[
              const SizedBox(height: SelSpace.x4),
              SelLabeledPillGroup<_RankedScope>(
                label: 'Group by',
                selected: _rankedScope,
                onChanged: (v) => setState(() => _rankedScope = v),
                options: const [
                  (_RankedScope.overall, 'All partners'),
                  (_RankedScope.byArm, 'Partnership arm'),
                ],
              ),
            ],
          ],
        ),

        const SizedBox(height: SelSpace.x6),

        if (_view == _View.directory)
          partnersAsync.when(
            loading: () => const SelCard(child: SelSkeletonRows()),
            error: (e, _) => SelError(message: '$e'),
            data: (partners) {
              final rows = partners.where((p) {
                if (_query.isEmpty) return true;
                return p.fullName.toLowerCase().contains(_query) ||
                    p.memberId.toLowerCase().contains(_query) ||
                    p.fellowship.toLowerCase().contains(_query);
              }).toList();

              return SelLedger.builder(
                minWidth: 720,
                maxVirtualHeight: 640,
                columns: const [
                  SelColumn('Member ID', fit: SelColFit.fixed, width: 120),
                  SelColumn('Name', flex: 3),
                  SelColumn('Fellowship', flex: 2),
                  SelColumn.numeric('Total given', width: 140),
                  SelColumn('Status', fit: SelColFit.fixed, width: 110),
                ],
                emptyState: SelEmpty(
                  title: _query.isEmpty ? 'No partners yet' : 'No matches',
                  message: _query.isEmpty
                      ? 'Add partners to start recording their giving.'
                      : 'Nothing matches “$_query”.',
                ),
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final p = rows[i];
                  return SelRow(
                    onTap: () => context.go('/partners/${p.id}'),
                    cells: [
                      SelCell.secondary(p.memberId),
                      SelCell.primary(p.fullName),
                      SelCell.secondary(p.fellowship),
                      SelCell.numeric(money(p.totalApprovedAmount)),
                      SelStatusMark(
                        status: p.isActive
                            ? SelStatus.active
                            : SelStatus.inactive,
                        label: p.isActive ? 'Active' : 'Inactive',
                      ),
                    ],
                  );
                },
              );
            },
          )
        else
          _RankedView(
            money: money,
            scope: _rankedScope,
          ),
      ],
    );
  }
}

class _RankedView extends ConsumerWidget {
  const _RankedView({required this.money, required this.scope});

  final String Function(num) money;
  final _RankedScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The filter bar draws its options from the rows being ranked, so it gets
    // the same period-scoped set the ranking does.
    final all = ref.watch(rankingEntriesProvider).valueOrNull ?? const [];
    final arms =
        ref.watch(armsStreamProvider).valueOrNull ?? const <PartnershipArm>[];
    final filters = ref.watch(recordFiltersProvider);

    if (scope == _RankedScope.byArm) {
      return _RankedByArmBody(
        money: money,
        all: all,
        arms: arms,
        filters: filters,
      );
    }

    // Ranked once per data change by the provider, not once per rebuild.
    final rows = ref.watch(partnerRankingProvider);

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
        PartnerRankedLedger(rows: rows, money: money),
      ],
    );
  }
}

class _RankedByArmBody extends ConsumerWidget {
  const _RankedByArmBody({
    required this.money,
    required this.all,
    required this.arms,
    required this.filters,
  });

  final String Function(num) money;
  final List<PartnershipEntry> all;
  final List<PartnershipArm> arms;
  final RecordFilters filters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // O(arms x entries), so it is worth never running this twice for one
    // snapshot of the data.
    final sections = ref.watch(armRankingProvider);
    final visible = filters.armId == null
        ? sections
        : sections.where((s) => s.armId == filters.armId).toList();

    return RankedGroupedBody(
      money: money,
      all: all,
      arms: arms,
      filters: filters,
      sections: [
        for (final section in visible)
          RankGroupSection(
            title: section.armName,
            rows: section.rows,
            emptyTitle: 'Nothing ranked yet',
            emptyMessage:
                'Rankings appear once entries are approved for this arm.',
            showWhenEmpty: true,
            trailing: section.rows.isEmpty
                ? 'No approved giving'
                : '${section.rows.length} partners · ${money(section.totalCedis)}',
          ),
      ],
      requireAnyRows: visible.any((s) => s.rows.isNotEmpty),
    );
  }
}
