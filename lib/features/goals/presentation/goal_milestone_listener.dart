import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pillr/l10n/app_localizations.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../auth/providers/auth_providers.dart';
import '../../settings/presentation/settings_screen.dart';
import '../providers/goals_providers.dart';

const _kPrefPrefix = 'pillr_goal_milestone_';

/// Detects 50% / 75% / 100% goal crossings; dedupes with [SharedPreferences].
class GoalMilestoneListener extends ConsumerStatefulWidget {
  const GoalMilestoneListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<GoalMilestoneListener> createState() => _GoalMilestoneListenerState();
}

class _GoalMilestoneListenerState extends ConsumerState<GoalMilestoneListener> {
  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    ref.listen(goalsListProvider, (prev, next) {
      if (idx == null || !idx.isPastor) return;
      final allowMilestones = ref.read(notificationGoalsProvider).valueOrNull ?? true;
      if (!allowMilestones) return;
      next.whenData((goals) {
        final prevGoals = prev?.valueOrNull;
        if (prevGoals == null) return;

        final prevMap = {for (final g in prevGoals) g.id: g.progressFraction};
        SharedPreferences.getInstance().then((prefs) {
          if (!context.mounted) return;
          final messenger = ScaffoldMessenger.maybeOf(context);
          if (messenger == null) return;
          final l10n = AppLocalizations.of(context);

          for (final g in goals) {
            final before = prevMap[g.id] ?? 0.0;
            final after = g.progressFraction;
            if (after <= before) continue;
            const milestones = [0.5, 0.75, 1.0];
            for (final m in milestones) {
              if (before < m && after >= m) {
                final key = '$_kPrefPrefix${g.id}_${(m * 100).round()}';
                if (prefs.getBool(key) == true) continue;
                prefs.setBool(key, true);
                final msg = m == 1.0
                    ? l10n.goalMilestone100
                    : m == 0.75
                        ? l10n.goalMilestone75
                        : l10n.goalMilestone50;
                messenger.showSnackBar(SnackBar(content: Text(msg)));
              }
            }
          }
        });
      });
    });

    return widget.child;
  }
}
