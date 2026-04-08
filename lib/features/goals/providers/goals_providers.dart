import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../auth/providers/auth_providers.dart';
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
