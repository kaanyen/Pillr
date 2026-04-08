import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../common/widgets/fade_in_once.dart';
import '../../../common/widgets/pillr_button.dart';
import '../../../common/widgets/pillr_card.dart';
import '../../../common/widgets/pillr_stat_card.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_utils.dart';
import '../../activity/domain/activity_log_row.dart';
import '../../arms/providers/arms_providers.dart';
import '../../entries/providers/entries_providers.dart';
import '../../goals/providers/goals_providers.dart';
import '../../logs/providers/activity_logs_providers.dart';
import '../../partners/providers/partners_providers.dart';
import '../providers/dashboard_stats_providers.dart';
import '../widgets/getting_started_banner.dart';

/// Reference 2 stat row — live entry aggregates + Phase 3 dashboard (§15.3.1).
class PastorDashboardScreen extends ConsumerWidget {
  const PastorDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(pastorEntryStatsProvider);
    final partnerCount = ref.watch(activePartnerCountProvider);
    final goalPct = ref.watch(pastorGoalProgressPercentProvider);
    final preview = ref.watch(pastorLeaderboardPreviewProvider);
    final activityAsync = ref.watch(activityLogsPreviewProvider);
    final activeGoals = ref.watch(activePeriodGoalsProvider);
    final arms = ref.watch(armsStreamProvider).valueOrNull ?? [];

    String armName(String id) {
      for (final a in arms) {
        if (a.id == id) return a.name;
      }
      return id;
    }

    final total = stats.pendingCount + stats.approvedCount + stats.declinedCount;
    final pFlex = total == 0 ? 1 : stats.pendingCount;
    final aFlex = total == 0 ? 1 : stats.approvedCount;
    final dFlex = total == 0 ? 1 : stats.declinedCount;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(entriesListProvider);
        ref.invalidate(goalsListProvider);
        ref.invalidate(partnersStreamProvider(false));
        ref.invalidate(activityLogsPreviewProvider);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GettingStartedBanner(),
          Text('Overview', style: AppTypography.heading2),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Live counts from partnership entries in your church.',
            style: AppTypography.body,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              PillrButton(
                label: 'Review pending',
                variant: PillrButtonVariant.primary,
                onPressed: () => context.go('/approvals'),
              ),
              PillrButton(
                label: 'New entry',
                variant: PillrButtonVariant.secondary,
                onPressed: () => context.go('/entries/new'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, c) {
              final cross = c.maxWidth > 1100 ? 4 : (c.maxWidth > 700 ? 2 : 1);
              return GridView.count(
                crossAxisCount: cross,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpacing.md,
                crossAxisSpacing: AppSpacing.md,
                childAspectRatio: 1.4,
                children: [
                  FadeInOnce(
                    delay: Duration.zero,
                    child: _AnimatedIntStatCard(
                      label: 'Total collected (approved)',
                      value: stats.totalApprovedCedis,
                      format: (v) => formatCedis(v),
                      periodLabel: 'All approved entries',
                    ),
                  ),
                  FadeInOnce(
                    delay: const Duration(milliseconds: 50),
                    child: _AnimatedIntStatCard(
                      label: 'Pending approvals',
                      value: stats.pendingCount.toDouble(),
                      format: (v) => v.round().toString(),
                      periodLabel: 'Awaiting review',
                    ),
                  ),
                  FadeInOnce(
                    delay: const Duration(milliseconds: 100),
                    child: _AnimatedIntStatCard(
                      label: 'Active partners',
                      value: partnerCount.toDouble(),
                      format: (v) => v.round().toString(),
                      periodLabel: 'Non-inactive partners',
                    ),
                  ),
                  FadeInOnce(
                    delay: const Duration(milliseconds: 150),
                    child: PillrStatCard(
                      label: 'Goal progress',
                      valueText: goalPct == null ? '—' : '${goalPct.round()}%',
                      periodLabel: goalPct == null ? 'Set goals for the active period' : 'Active period (all arms)',
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          PillrCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Partnership mix', style: AppTypography.heading3),
                    const Spacer(),
                    Text(
                      '${stats.totalEntries} entries · ${formatCedis(stats.totalApprovedCedis)} approved',
                      style: AppTypography.caption,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _SegmentBar(
                  segments: [
                    _Seg(pFlex.toDouble(), AppColors.progressOrange),
                    _Seg(aFlex.toDouble(), AppColors.progressTeal),
                    _Seg(dFlex.toDouble(), AppColors.progressRed),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.sm,
                  children: [
                    _LegendDot(color: AppColors.progressOrange, label: 'Pending'),
                    _LegendDot(color: AppColors.progressTeal, label: 'Approved'),
                    _LegendDot(color: AppColors.progressRed, label: 'Declined'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Text('Goal progress (active period)', style: AppTypography.heading3),
              const Spacer(),
              TextButton(onPressed: () => context.go('/goals'), child: const Text('Manage goals')),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          activeGoals.isEmpty
              ? Text('No goals for the active period yet.', style: AppTypography.caption)
              : Column(
                  children: [
                    for (final g in activeGoals)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              armName(g.partnershipArmId),
                              style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.full),
                              child: LinearProgressIndicator(
                                value: g.progressFraction,
                                minHeight: 8,
                                backgroundColor: AppColors.gray100,
                                color: AppColors.primaryColor,
                              ),
                            ),
                            Text(
                              '${formatCedis(g.currentAmountCedis)} / ${formatCedis(g.targetAmountCedis)}',
                              style: AppTypography.caption,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Text('Leaderboard preview', style: AppTypography.heading3),
              const Spacer(),
              TextButton(onPressed: () => context.go('/leaderboard'), child: const Text('Full leaderboard')),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (preview.isEmpty)
            Text('No approved entries in the active period yet.', style: AppTypography.caption)
          else
            ...preview.map(
              (r) => ListTile(
                dense: true,
                leading: Text('${r.rank}', style: AppTypography.label),
                title: Text(r.partnerName),
                trailing: Text(formatCedis(r.totalCedis)),
                onTap: () => context.go('/partners/${r.partnerId}'),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          Text('Recent activity', style: AppTypography.heading3),
          const SizedBox(height: AppSpacing.sm),
          activityAsync.when(
            loading: () => const Text('Loading…'),
            error: (e, _) => Text('$e', style: AppTypography.caption),
            data: (logs) {
              final slice = logs.take(10).toList();
              if (slice.isEmpty) {
                return Text('No activity yet.', style: AppTypography.caption);
              }
              return Column(
                children: [
                  for (final row in slice) _ActivityLine(row: row),
                ],
              );
            },
          ),
        ],
      ),
      ),
    );
  }
}

class _ActivityLine extends StatelessWidget {
  const _ActivityLine({required this.row});

  final ActivityLogRow row;

  @override
  Widget build(BuildContext context) {
    final t = row.createdAt;
    final when =
        '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(when, style: AppTypography.caption),
          ),
          Expanded(
            child: Text(
              '${row.actorName} · ${row.action} · ${row.entityType}',
              style: AppTypography.caption,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedIntStatCard extends StatelessWidget {
  const _AnimatedIntStatCard({
    required this.label,
    required this.value,
    required this.format,
    required this.periodLabel,
  });

  final String label;
  final double value;
  final String Function(double) format;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        return PillrStatCard(
          label: label,
          valueText: format(v),
          periodLabel: periodLabel,
        );
      },
    );
  }
}

class _Seg {
  const _Seg(this.flex, this.color);
  final double flex;
  final Color color;
}

class _SegmentBar extends StatelessWidget {
  const _SegmentBar({required this.segments});

  final List<_Seg> segments;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: SizedBox(
        height: 10,
        child: Row(
          children: [
            for (final s in segments)
              Expanded(
                flex: (s.flex * 100).round().clamp(1, 1000),
                child: Container(color: s.color),
              ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: AppTypography.caption),
      ],
    );
  }
}
