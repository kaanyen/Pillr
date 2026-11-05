import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../design/seline.dart';
import '../features/arms/domain/partnership_arm.dart';
import '../features/arms/providers/arms_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/entries/domain/partnership_entry.dart';
import '../features/entries/providers/entries_providers.dart';
import '../features/entries/providers/record_filters.dart';
import '../features/leaderboard/leaderboard_providers.dart';
import '../features/periods/providers/periods_providers.dart';
import 'export_actions.dart';
import 'ranked_views.dart';
import 'record_filter_bar.dart';

enum _RankedScope { overall, byArm }

/// Ranked — partners ordered by approved giving in the active period.
///
/// It used to be a second view inside Partners. People asked for it by name
/// often enough that it is its own destination now, straight after Partners.
/// `/leaderboard` and `/partners?view=ranked` both land here.
class RankedScreen extends ConsumerStatefulWidget {
  const RankedScreen({super.key});

  @override
  ConsumerState<RankedScreen> createState() => _RankedScreenState();
}

class _RankedScreenState extends ConsumerState<RankedScreen> {
  _RankedScope _scope = _RankedScope.overall;

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(churchMoneyFormatProvider);
    return SelPageBody(
      onRefresh: () async {
        ref.invalidate(rankingEntriesProvider);
        invalidateEntryDerivedData(ref);
      },
      children: [
        SelPageTitle(
          title: 'Ranked',
          subtitle: switch (_scope) {
            _RankedScope.overall =>
              'Partners by approved giving · ${ref.watch(activePeriodProvider)?.name ?? 'the active period'}',
            _RankedScope.byArm =>
              'Partners by approved giving within each arm',
          },
          actions: [
            EntryExportButtons(
              entriesLoader: () => loadEntriesForExport(ref),
              title: switch (_scope) {
                _RankedScope.overall => 'Partner ranking',
                _RankedScope.byArm => 'Partner ranking by arm',
              },
              subtitle: switch (_scope) {
                _RankedScope.overall => 'Ranked by approved giving',
                _RankedScope.byArm => 'Ranked by approved giving per arm',
              },
            ),
          ],
        ),
        SelLabeledPillGroup<_RankedScope>(
          label: 'Group by',
          selected: _scope,
          onChanged: (v) => setState(() => _scope = v),
          options: const [
            (_RankedScope.overall, 'All partners'),
            (_RankedScope.byArm, 'Arm'),
          ],
        ),
        const SizedBox(height: SelSpace.x6),
        _RankedView(money: money, scope: _scope),
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
        PartnerRankedLedger(rows: rows, money: money, entries: all),
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
