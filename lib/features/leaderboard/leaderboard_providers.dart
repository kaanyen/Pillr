import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/extensions/async_value_ext.dart';
import '../arms/domain/partnership_arm.dart';
import '../arms/providers/arms_providers.dart';
import '../church/providers/church_settings_providers.dart';
import '../entries/domain/partnership_entry.dart';
import '../entries/providers/entries_providers.dart';
import '../entries/providers/record_filters.dart';
import '../partners/providers/partners_providers.dart';
import '../periods/providers/periods_providers.dart';
import 'leaderboard_models.dart';

/// Ranking aggregates, computed once per data change rather than once per frame.
///
/// These used to run inside `build()` on the Partners and Fellowships screens.
/// That meant a full pass over every entry on every rebuild — and because a
/// ledger row calls `setState` on mouse enter and exit, moving the pointer down
/// a 450-row list re-ranked the whole church once per row. `ArmLeaderboard` was
/// the worst of them: it ranks once per arm, so it is O(arms x entries) each
/// time.
///
/// As Riverpod providers they recompute only when the entries, the filters, the
/// active period or the arms actually change. Every one is `autoDispose`, so a
/// screen that is not on the stack holds nothing.

/// Entries after the filter set shared by Records, Partners and Fellowships.
///
/// Sourced from [rankingEntriesProvider] — approved entries in the active
/// period — rather than the church's whole collection. Every consumer below
/// discards non-approved rows and rows outside the period anyway, so this is
/// the same set arrived at without downloading the rest.
final filteredEntriesProvider =
    Provider.autoDispose<List<PartnershipEntry>>((ref) {
  final scoped = ref.watch(rankingEntriesProvider).valueOrNull ?? const [];
  final filters = ref.watch(recordFiltersProvider);
  final byPartner = ref.watch(partnerFellowshipByIdProvider);
  return applyRecordFilters(
    scoped,
    filters,
    now: DateTime.now(),
    fellowshipByPartnerId: byPartner,
    armFamilyOf: ref.watch(armTreeProvider).familyOf,
  );
});

/// Partners ranked by approved giving in the active period, filters applied.
final partnerRankingProvider = Provider.autoDispose<List<LeaderboardRow>>((ref) {
  final entries = ref.watch(filteredEntriesProvider);
  final period = ref.watch(activePeriodProvider);
  return LeaderboardRow.fromEntries(entries, periodId: period?.id);
});

/// One ranked partner list per active arm, in the church's arm sort order.
final armRankingProvider = Provider.autoDispose<List<ArmLeaderboard>>((ref) {
  final entries = ref.watch(filteredEntriesProvider);
  final period = ref.watch(activePeriodProvider);
  final arms =
      ref.watch(armsStreamProvider).valueOrNull ?? const <PartnershipArm>[];
  return ArmLeaderboard.fromEntriesAndArms(
    entries,
    arms.where((a) => a.isActive).toList(),
    periodId: period?.id,
    armFamilyOf: ref.watch(armTreeProvider).familyOf,
  );
});

/// Fellowships ranked against each other by total approved giving.
final fellowshipRankingProvider =
    Provider.autoDispose<List<FellowshipRankRow>>((ref) {
  final entries = ref.watch(filteredEntriesProvider);
  final period = ref.watch(activePeriodProvider);
  final byPartner = ref.watch(partnerFellowshipByIdProvider);
  return FellowshipRankRow.fromEntries(
    entries,
    periodId: period?.id,
    fellowshipByPartnerId: byPartner,
  );
});

/// One ranked partner list per fellowship that has approved giving.
final fellowshipSectionsProvider =
    Provider.autoDispose<List<FellowshipLeaderboard>>((ref) {
  final entries = ref.watch(filteredEntriesProvider);
  final period = ref.watch(activePeriodProvider);
  final byPartner = ref.watch(partnerFellowshipByIdProvider);
  return FellowshipLeaderboard.fromEntries(
    entries,
    periodId: period?.id,
    fellowshipByPartnerId: byPartner,
  );
});

/// Fellowship directory rows — headcount from the partner list, giving from the
/// filtered entries. The filter set is shared app-wide, so a window narrowed on
/// the ranked view still applies here, as it did before this moved off `build`.
final fellowshipDirectoryProvider =
    Provider.autoDispose.family<List<FellowshipDirectoryRow>, bool>((
  ref,
  includeInactive,
) {
  final partners =
      ref.watch(visiblePartnersProvider(includeInactive)).valueOrNull ?? const [];
  final entries = ref.watch(filteredEntriesProvider);
  final period = ref.watch(activePeriodProvider);
  final catalog =
      ref.watch(churchSettingsProvider).valueOrNull?.fellowshipNames ??
          const [];
  return FellowshipDirectoryRow.fromPartnersAndEntries(
    partners.map((p) => p.fellowship),
    entries,
    periodId: period?.id,
    fellowshipByPartnerId: {for (final p in partners) p.id: p.fellowship},
    catalog: catalog,
  );
});
