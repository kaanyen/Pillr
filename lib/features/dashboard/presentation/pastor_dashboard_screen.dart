import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../common/widgets/fade_in_once.dart';
import '../../../common/widgets/pillr_button.dart';
import '../../../common/widgets/pillr_card.dart';
import '../../../common/widgets/pillr_stat_card.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_utils.dart';
import '../../../core/utils/text_case_utils.dart';
import '../../arms/providers/arms_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../church/providers/church_settings_providers.dart';
import '../../entries/providers/entries_providers.dart';
import '../../goals/providers/goals_providers.dart';
import '../../leaderboard/leaderboard_models.dart';
import '../../logs/providers/activity_logs_providers.dart';
import '../../partners/providers/partners_providers.dart';
import '../providers/dashboard_stats_providers.dart';
import '../widgets/dashboard_shared.dart';
import '../widgets/getting_started_banner.dart';

/// Pastor home — modern minimalist SaaS dashboard layout.
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
    final profile = ref.watch(churchUserProfileProvider).valueOrNull;
    final churchName = ref.watch(churchNameProvider) ?? 'your church';

    String armName(String id) {
      for (final a in arms) {
        if (a.id == id) return a.name;
      }
      return id;
    }

    final nameParts = profile?.fullName.trim().split(RegExp(r'\s+')) ?? <String>[];
    final firstName =
        nameParts.isEmpty ? 'there' : TextCaseUtils.toTitleCase(nameParts.first);

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
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const GettingStartedBanner(),
            const SizedBox(height: AppSpacing.sm),
            LayoutBuilder(
              builder: (context, c) {
                final narrow = c.maxWidth < 640;
                final welcome = DashboardWelcomeBlock(
                  firstName: firstName,
                  subtitle:
                      'Here\'s what\'s happening at $churchName — live counts from partnership entries.',
                );
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      welcome,
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          PillrButton(
                            label: 'Open queue',
                            icon: LucideIcons.clipboardList,
                            variant: PillrButtonVariant.secondary,
                            onPressed: () => context.go('/approvals'),
                          ),
                          PillrButton(
                            label: 'Create entry',
                            icon: LucideIcons.plus,
                            variant: PillrButtonVariant.primary,
                            onPressed: () => context.go('/entries/new'),
                          ),
                        ],
                      ),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: welcome),
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: PillrButton(
                        label: 'Open queue',
                        icon: LucideIcons.clipboardList,
                        variant: PillrButtonVariant.secondary,
                        onPressed: () => context.go('/approvals'),
                      ),
                    ),
                    PillrButton(
                      label: 'Create entry',
                      icon: LucideIcons.plus,
                      variant: PillrButtonVariant.primary,
                      onPressed: () => context.go('/entries/new'),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            LayoutBuilder(
              builder: (context, c) {
                final cross = c.maxWidth > 1100 ? 4 : (c.maxWidth > 700 ? 2 : 1);
                return GridView.count(
                  crossAxisCount: cross,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                  childAspectRatio: cross == 4 ? 1.55 : 1.45,
                  children: [
                    FadeInOnce(
                      delay: Duration.zero,
                      child: _AnimatedIntStatCard(
                        label: 'Total collected (approved)',
                        value: stats.totalApprovedCedis,
                        format: formatCedis,
                        periodLabel: 'All approved entries',
                        backgroundColor: DashboardTints.totalBg,
                        iconCircleColor: DashboardTints.totalIconCircle,
                        iconColor: AppColors.primaryColor,
                        icon: LucideIcons.wallet,
                      ),
                    ),
                    FadeInOnce(
                      delay: const Duration(milliseconds: 50),
                      child: _AnimatedIntStatCard(
                        label: 'Pending approvals',
                        value: stats.pendingCount.toDouble(),
                        format: (v) => v.round().toString(),
                        periodLabel: 'Awaiting review',
                        backgroundColor: DashboardTints.pendingBg,
                        iconCircleColor: DashboardTints.pendingIconCircle,
                        iconColor: const Color(0xFFB45309),
                        icon: LucideIcons.clock,
                      ),
                    ),
                    FadeInOnce(
                      delay: const Duration(milliseconds: 100),
                      child: _AnimatedIntStatCard(
                        label: 'Active partners',
                        value: partnerCount.toDouble(),
                        format: (v) => v.round().toString(),
                        periodLabel: 'Giving records',
                        backgroundColor: DashboardTints.partnersBg,
                        iconCircleColor: DashboardTints.partnersIconCircle,
                        iconColor: AppColors.navActiveForeground,
                        icon: LucideIcons.users,
                      ),
                    ),
                    FadeInOnce(
                      delay: const Duration(milliseconds: 150),
                      child: PillrStatCard(
                        label: 'Goal progress',
                        valueText: goalPct == null ? '—' : '${goalPct.round()}%',
                        periodLabel: goalPct == null ? 'Set goals for the active period' : 'Active period (all arms)',
                        backgroundColor: DashboardTints.goalBg,
                        iconCircleColor: DashboardTints.goalIconCircle,
                        iconColor: AppColors.primaryDark,
                        icon: LucideIcons.target,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            PillrCard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text('Partnership mix', style: AppTypography.heading3),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Flexible(
                        child: Text(
                          '${stats.totalEntries} entries · ${formatCedis(stats.totalApprovedCedis)} approved',
                          style: AppTypography.caption,
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
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
                    children: const [
                      _LegendDot(color: AppColors.progressOrange, label: 'Pending'),
                      _LegendDot(color: AppColors.progressTeal, label: 'Approved'),
                      _LegendDot(color: AppColors.progressRed, label: 'Declined'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            DashboardSectionHeader(
              title: 'Goal progress (active period)',
              actionLabel: 'Manage goals',
              onAction: () => context.go('/goals'),
            ),
            const SizedBox(height: AppSpacing.md),
            activeGoals.isEmpty
                ? PillrCard(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      'No goals for the active period yet.',
                      style: AppTypography.body.copyWith(color: AppColors.gray400),
                    ),
                  )
                : Column(
                    children: [
                      for (final g in activeGoals)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: PillrCard(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  armName(g.partnershipArmId),
                                  style: AppTypography.body.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.gray900,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(AppRadius.full),
                                  child: LinearProgressIndicator(
                                    value: g.progressFraction,
                                    minHeight: 10,
                                    backgroundColor: AppColors.gray100,
                                    color: AppColors.primaryColor,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  '${formatCedis(g.currentAmountCedis)} / ${formatCedis(g.targetAmountCedis)}',
                                  style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
            const SizedBox(height: AppSpacing.lg),
            DashboardSectionHeader(
              title: 'Leaderboard preview',
              actionLabel: 'Full leaderboard',
              onAction: () => context.go('/leaderboard'),
            ),
            const SizedBox(height: AppSpacing.md),
            PillrCard(
              padding: EdgeInsets.zero,
              child: preview.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Text(
                        'No approved entries in the active period yet.',
                        style: AppTypography.body.copyWith(color: AppColors.gray400),
                      ),
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < preview.length; i++)
                          _LeaderboardRow(
                            row: preview[i],
                            showDivider: i < preview.length - 1,
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Recent activity', style: AppTypography.heading3),
            const SizedBox(height: AppSpacing.md),
            PillrCard(
              padding: EdgeInsets.zero,
              child: activityAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text('$e', style: AppTypography.caption.copyWith(color: AppColors.dangerColor)),
                ),
                data: (logs) {
                  final slice = logs.take(10).toList();
                  if (slice.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Text(
                        'No activity yet.',
                        style: AppTypography.body.copyWith(color: AppColors.gray400),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (var i = 0; i < slice.length; i++)
                        DashboardActivityLine(
                          row: slice[i],
                          showDivider: i < slice.length - 1,
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({
    required this.row,
    required this.showDivider,
  });

  final LeaderboardRow row;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final name = TextCaseUtils.toTitleCase(row.partnerName);
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Column(
      children: [
        InkWell(
          onTap: () => context.go('/partners/${row.partnerId}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
            child: Row(
              children: [
                Text(
                  '${row.rank}',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.gray400,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.gray100,
                  child: Text(
                    initial,
                    style: AppTypography.label.copyWith(
                      color: AppColors.gray600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    name,
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.gray900,
                    ),
                  ),
                ),
                Text(
                  formatCedis(row.totalCedis),
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.gray900,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(height: 1, thickness: 1, color: AppColors.gray200),
      ],
    );
  }
}

class _AnimatedIntStatCard extends StatelessWidget {
  const _AnimatedIntStatCard({
    required this.label,
    required this.value,
    required this.format,
    required this.periodLabel,
    this.backgroundColor,
    this.iconCircleColor,
    this.iconColor,
    this.icon,
  });

  final String label;
  final double value;
  final String Function(double) format;
  final String periodLabel;
  final Color? backgroundColor;
  final Color? iconCircleColor;
  final Color? iconColor;
  final IconData? icon;

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
          backgroundColor: backgroundColor,
          iconCircleColor: iconCircleColor,
          iconColor: iconColor,
          icon: icon,
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
      borderRadius: BorderRadius.circular(9999),
      child: SizedBox(
        height: 14,
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
        const SizedBox(width: 8),
        Text(
          label,
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
