import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../arms/providers/arms_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../goals/providers/goals_providers.dart';
import '../../periods/providers/periods_providers.dart';

const _kDismissed = 'pillr_getting_started_dismissed';

final gettingStartedDismissedProvider = FutureProvider<bool>((ref) async {
  final p = await SharedPreferences.getInstance();
  return p.getBool(_kDismissed) ?? false;
});

/// §16.4.11 — checklist for new churches (pastor dashboard).
class GettingStartedBanner extends ConsumerWidget {
  const GettingStartedBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    if (idx == null || !idx.isPastor) return const SizedBox.shrink();

    final dismissed = ref.watch(gettingStartedDismissedProvider);
    final arms = ref.watch(armsStreamProvider).valueOrNull ?? [];
    final periods = ref.watch(periodsStreamProvider).valueOrNull ?? [];
    final goals = ref.watch(goalsListProvider).valueOrNull ?? [];

    return dismissed.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (off) {
        if (off) return const SizedBox.shrink();
        final doneArms = arms.isNotEmpty;
        final donePeriod = periods.isNotEmpty;
        final doneGoals = goals.isNotEmpty;
        final allDone = doneArms && donePeriod && doneGoals;
        if (allDone) return const SizedBox.shrink();

        return Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.lg),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Getting started', style: AppTypography.heading3)),
                    TextButton(
                      onPressed: () async {
                        final p = await SharedPreferences.getInstance();
                        await p.setBool(_kDismissed, true);
                        ref.invalidate(gettingStartedDismissedProvider);
                      },
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                _CheckRow(done: doneArms, label: 'Create at least one partnership arm', onTap: () => context.go('/arms')),
                _CheckRow(done: donePeriod, label: 'Create a partnership period', onTap: () => context.go('/periods')),
                _CheckRow(done: doneGoals, label: 'Set giving goals', onTap: () => context.go('/goals')),
                _CheckRow(
                  done: false,
                  label: 'Invite staff (Invitations) and record your first entry',
                  onTap: () => context.go('/invitations'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.done, required this.label, required this.onTap});

  final bool done;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(done ? LucideIcons.checkCircle : LucideIcons.circle, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(label, style: AppTypography.body)),
            const Icon(LucideIcons.chevronRight, size: 18),
          ],
        ),
      ),
    );
  }
}
