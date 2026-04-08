import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../auth/providers/auth_providers.dart';
import '../../entries/domain/partnership_entry.dart';
import '../../entries/providers/entries_providers.dart';
import '../../goals/providers/goals_providers.dart';
import '../../leaderboard/leaderboard_models.dart';
import '../../partners/providers/partners_providers.dart';
import '../../periods/providers/periods_providers.dart';

/// Live aggregates for pastor dashboard (all church entries).
class PastorEntryStats {
  const PastorEntryStats({
    required this.pendingCount,
    required this.approvedCount,
    required this.declinedCount,
    required this.totalApprovedCedis,
  });

  final int pendingCount;
  final int approvedCount;
  final int declinedCount;
  final double totalApprovedCedis;

  int get totalEntries => pendingCount + approvedCount + declinedCount;

  static PastorEntryStats fromEntries(List<PartnershipEntry> entries) {
    var pending = 0;
    var approved = 0;
    var declined = 0;
    var sum = 0.0;
    for (final e in entries) {
      switch (e.status) {
        case 'pending':
          pending++;
          break;
        case 'approved':
          approved++;
          sum += e.amountCedis;
          break;
        case 'declined':
          declined++;
          break;
      }
    }
    return PastorEntryStats(
      pendingCount: pending,
      approvedCount: approved,
      declinedCount: declined,
      totalApprovedCedis: sum,
    );
  }
}

final pastorEntryStatsProvider = Provider<PastorEntryStats>((ref) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null || !idx.isPastor) {
    return const PastorEntryStats(
      pendingCount: 0,
      approvedCount: 0,
      declinedCount: 0,
      totalApprovedCedis: 0,
    );
  }
  final entries = ref.watch(entriesListProvider).valueOrNull ?? [];
  return PastorEntryStats.fromEntries(entries);
});

/// Active partners count (excludes inactive).
final activePartnerCountProvider = Provider<int>((ref) {
  return ref.watch(partnersStreamProvider(false)).maybeWhen(
        data: (p) => p.length,
        orElse: () => 0,
      );
});

/// Staff: own entries only (from [entriesListProvider]).
class StaffEntryStats {
  const StaffEntryStats({
    required this.totalCount,
    required this.approvedCount,
    required this.approvedTotalCedis,
  });

  final int totalCount;
  final int approvedCount;
  final double approvedTotalCedis;

  static StaffEntryStats fromEntries(List<PartnershipEntry> entries) {
    var approved = 0;
    var sum = 0.0;
    for (final e in entries) {
      if (e.status == 'approved') {
        approved++;
        sum += e.amountCedis;
      }
    }
    return StaffEntryStats(
      totalCount: entries.length,
      approvedCount: approved,
      approvedTotalCedis: sum,
    );
  }
}

final staffMyEntryStatsProvider = Provider<StaffEntryStats>((ref) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null || !idx.isStaff) {
    return const StaffEntryStats(totalCount: 0, approvedCount: 0, approvedTotalCedis: 0);
  }
  final entries = ref.watch(entriesListProvider).valueOrNull ?? [];
  return StaffEntryStats.fromEntries(entries);
});

/// Weighted goal progress for the **active** period (all arms), or null if no targets.
final pastorGoalProgressPercentProvider = Provider<double?>((ref) {
  final goals = ref.watch(activePeriodGoalsProvider);
  if (goals.isEmpty) return null;
  var target = 0.0;
  var current = 0.0;
  for (final g in goals) {
    target += g.targetAmountCedis;
    current += g.currentAmountCedis;
  }
  if (target <= 0) return null;
  return (current / target * 100).clamp(0, 100);
});

/// Top 5 partners by approved amount in the **active** period (all arms).
final pastorLeaderboardPreviewProvider = Provider<List<LeaderboardRow>>((ref) {
  final entries = ref.watch(entriesListProvider).valueOrNull ?? [];
  final active = ref.watch(activePeriodProvider);
  if (active == null) return [];
  final rows = LeaderboardRow.fromEntries(
    entries,
    periodId: active.id,
    armId: null,
  );
  if (rows.length <= 5) return rows;
  return rows.sublist(0, 5);
});
