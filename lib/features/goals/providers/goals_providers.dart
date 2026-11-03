import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../arms/providers/arms_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../entries/providers/entries_providers.dart';
import '../../periods/providers/periods_providers.dart';
import '../data/goals_repository.dart';
import '../domain/partnership_goal.dart';

final goalsRepositoryProvider = Provider<GoalsRepository>((ref) {
  return GoalsRepository(ref.watch(firestoreProvider));
});

final goalsListProvider = StreamProvider.autoDispose<List<PartnershipGoal>>((ref) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null || !idx.isPastor) return Stream.value([]);
  return ref.watch(goalsRepositoryProvider).watchGoals(idx.churchId);
});

/// Goals for the active partnership period (empty if none).
final activePeriodGoalsProvider = Provider<List<PartnershipGoal>>((ref) {
  final goals = ref.watch(goalsListProvider).valueOrNull ?? [];
  final active = ref.watch(activePeriodProvider);
  if (active == null) return [];
  return goals.where((g) => g.partnershipPeriodId == active.id).toList();
});

/// Approved giving in a period to a main arm and its sub-arms.
///
/// Keyed by period and the family's arm ids (sorted, comma-joined) so the
/// same family is read once. Re-read whenever that period's approved total
/// moves, which is every approval, undo or void in it.
final armFamilyApprovedCedisProvider = FutureProvider.autoDispose
    .family<double, ({String periodId, String armIds})>((ref, key) async {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null) return 0;
  ref.watch(periodsStreamProvider.select((v) => v.valueOrNull
      ?.where((p) => p.id == key.periodId)
      .firstOrNull
      ?.totalApprovedAmount));
  return ref.watch(entriesRepositoryProvider).fetchApprovedCedisForArms(
        idx.churchId,
        periodId: key.periodId,
        armIds: key.armIds.split(','),
      );
});

/// How much a goal has reached.
///
/// A goal on a main arm with sub-arms counts the whole family's approved
/// giving in its period. Any other goal reads its stored total, as before.
/// While the family's figure loads, the stored total stands in.
final goalReachedCedisProvider =
    Provider.autoDispose.family<double, PartnershipGoal>((ref, goal) {
  final tree = ref.watch(armTreeProvider);
  if (!tree.hasChildren(goal.partnershipArmId)) return goal.currentAmountCedis;
  final ids = tree.familyOf(goal.partnershipArmId).toList()..sort();
  return ref
          .watch(armFamilyApprovedCedisProvider(
              (periodId: goal.partnershipPeriodId, armIds: ids.join(','))))
          .valueOrNull ??
      goal.currentAmountCedis;
});

/// Active-period goals that count toward the overall figure.
///
/// A sub-arm's own goal is still shown, but when its main arm has a goal too,
/// that sub-arm's giving is already inside the main arm's figure, so adding
/// both would count it twice.
final countedActivePeriodGoalsProvider = Provider.autoDispose<List<PartnershipGoal>>((ref) {
  final goals = ref.watch(activePeriodGoalsProvider);
  final tree = ref.watch(armTreeProvider);
  final goaled = {for (final g in goals) g.partnershipArmId};
  return [
    for (final g in goals)
      if (!goaled.contains(tree.mainOf(g.partnershipArmId)?.id)) g,
  ];
});
