import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../auth/providers/auth_providers.dart';
import '../../entries/data/entries_repository.dart';
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
    this.totalsFailed = false,
  });

  final int pendingCount;
  final int approvedCount;
  final int declinedCount;
  final double totalApprovedCedis;

  /// The aggregate query behind the counts threw — a missing index, a rules
  /// change, no network. The numbers above are then placeholders, not zeros,
  /// and the dashboard has to say so: in production this once read ₵0.00 for
  /// a church with ₵2m approved, and nothing on screen hinted it was wrong.
  final bool totalsFailed;

  int get totalEntries => pendingCount + approvedCount + declinedCount;

  static const zero = PastorEntryStats(
    pendingCount: 0,
    approvedCount: 0,
    declinedCount: 0,
    totalApprovedCedis: 0,
  );
}

/// The totals, or [EntryStatusTotals.empty] plus whether that is a failure.
///
/// Loading is not a failure — the tiles briefly read zero, as they always
/// have. An error is logged so it shows in the browser console with the
/// Firestore message (which, for a missing index, carries the link to make it).
(EntryStatusTotals, bool) _readTotals(Ref ref) {
  final async = ref.watch(entryStatusTotalsProvider);
  if (async.hasError) {
    debugPrint('Dashboard totals failed: ${async.error}');
    return (EntryStatusTotals.empty, true);
  }
  return (async.valueOrNull ?? EntryStatusTotals.empty, false);
}

/// Counted by Firestore rather than by walking every entry in the church.
///
/// The pending count is the one figure a pastor watches move, so it stays live
/// off [pendingEntriesProvider] — a query over a queue that gets drained, not
/// over the whole archive. The approved and declined counts and the approved
/// total come from aggregate queries, which read the index and never download
/// a document; they refresh when the app writes an entry.
final pastorEntryStatsProvider = Provider<PastorEntryStats>((ref) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null || !idx.isPastor) return PastorEntryStats.zero;

  final (totals, failed) = _readTotals(ref);
  final livePending = ref.watch(pendingEntriesProvider).valueOrNull;

  return PastorEntryStats(
    pendingCount: livePending?.length ?? totals.pendingCount,
    approvedCount: totals.approvedCount,
    declinedCount: totals.declinedCount,
    totalApprovedCedis: totals.approvedTotalCedis,
    totalsFailed: failed,
  );
});

/// Active partners count (excludes inactive).
final activePartnerCountProvider = Provider<int>((ref) {
  return ref.watch(partnersStreamProvider(false)).maybeWhen(
        data: (p) => p.length,
        orElse: () => 0,
      );
});

/// Staff: own submissions only.
class StaffEntryStats {
  const StaffEntryStats({
    required this.totalCount,
    required this.approvedCount,
    required this.approvedTotalCedis,
    this.totalsFailed = false,
  });

  final int totalCount;
  final int approvedCount;
  final double approvedTotalCedis;

  /// See [PastorEntryStats.totalsFailed].
  final bool totalsFailed;

  static const zero =
      StaffEntryStats(totalCount: 0, approvedCount: 0, approvedTotalCedis: 0);
}

/// Same aggregates as the pastor view, narrowed to what this user submitted.
final staffMyEntryStatsProvider = Provider<StaffEntryStats>((ref) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null || !idx.isStaff) return StaffEntryStats.zero;

  final (totals, failed) = _readTotals(ref);
  return StaffEntryStats(
    totalCount: totals.totalEntries,
    approvedCount: totals.approvedCount,
    approvedTotalCedis: totals.approvedTotalCedis,
    totalsFailed: failed,
  );
});

/// Weighted goal progress for the **active** period (all arms), or null if no targets.
final pastorGoalProgressPercentProvider = Provider<double?>((ref) {
  final goals = ref.watch(countedActivePeriodGoalsProvider);
  if (goals.isEmpty) return null;
  var target = 0.0;
  var current = 0.0;
  for (final g in goals) {
    target += g.targetAmountCedis;
    current += ref.watch(goalReachedCedisProvider(g));
  }
  if (target <= 0) return null;
  return (current / target * 100).clamp(0, 100);
});

/// Top 5 partners by approved amount in the **active** period (all arms).
final pastorLeaderboardPreviewProvider = Provider<List<LeaderboardRow>>((ref) {
  final active = ref.watch(activePeriodProvider);
  if (active == null) return [];
  // Already scoped to this period by the query behind it.
  final entries = ref.watch(rankingEntriesProvider).valueOrNull ?? const [];
  final rows = LeaderboardRow.fromEntries(
    entries,
    periodId: active.id,
    armId: null,
  );
  if (rows.length <= 5) return rows;
  return rows.sublist(0, 5);
});
