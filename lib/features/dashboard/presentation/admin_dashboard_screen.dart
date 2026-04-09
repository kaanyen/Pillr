import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../common/widgets/fade_in_once.dart';
import '../../../common/widgets/pillr_card.dart';
import '../../../common/widgets/pillr_stat_card.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/text_case_utils.dart';
import '../../auth/providers/auth_providers.dart';
import '../../church/providers/church_settings_providers.dart';
import '../../logs/providers/activity_logs_providers.dart';
import '../providers/admin_dashboard_providers.dart';
import '../widgets/dashboard_shared.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersCount = ref.watch(churchUsersCountProvider);
    final pendingInvites = ref.watch(pendingInvitesCountProvider);
    final activityAsync = ref.watch(activityLogsPreviewProvider);
    final profile = ref.watch(churchUserProfileProvider).valueOrNull;
    final churchName = ref.watch(churchNameProvider) ?? 'your church';

    final nameParts = profile?.fullName.trim().split(RegExp(r'\s+')) ?? <String>[];
    final firstName =
        nameParts.isEmpty ? 'there' : TextCaseUtils.toTitleCase(nameParts.first);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(activityLogsPreviewProvider);
        ref.invalidate(invitesListForAdminProvider);
        ref.invalidate(churchUsersCountProvider);
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
            DashboardWelcomeBlock(
              firstName: firstName,
              subtitle:
                  'Admin tools for $churchName — people, invitations, and audit. Financial routes stay hidden for this role.',
            ),
            const SizedBox(height: AppSpacing.xl),
            LayoutBuilder(
              builder: (context, c) {
                final cross = c.maxWidth > 900 ? 3 : (c.maxWidth > 520 ? 2 : 1);
                return GridView.count(
                  crossAxisCount: cross,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                  childAspectRatio: 1.35,
                  children: [
                    FadeInOnce(
                      delay: Duration.zero,
                      child: PillrStatCard(
                        label: 'Workspace users',
                        valueText: usersCount.when(
                          data: (n) => '$n',
                          loading: () => '…',
                          error: (_, __) => '—',
                        ),
                        periodLabel: 'accounts in this church',
                        backgroundColor: DashboardTints.totalBg,
                        iconCircleColor: DashboardTints.totalIconCircle,
                        iconColor: AppColors.primaryColor,
                        icon: LucideIcons.users,
                      ),
                    ),
                    FadeInOnce(
                      delay: const Duration(milliseconds: 50),
                      child: PillrStatCard(
                        label: 'Pending invites',
                        valueText: '$pendingInvites',
                        periodLabel: 'awaiting acceptance',
                        backgroundColor: DashboardTints.pendingBg,
                        iconCircleColor: DashboardTints.pendingIconCircle,
                        iconColor: const Color(0xFFB45309),
                        icon: LucideIcons.mail,
                      ),
                    ),
                    FadeInOnce(
                      delay: const Duration(milliseconds: 100),
                      child: PillrStatCard(
                        label: 'Audit events (loaded)',
                        valueText: activityAsync.when(
                          data: (l) => '${l.length}',
                          loading: () => '…',
                          error: (_, __) => '—',
                        ),
                        periodLabel: 'recent log rows',
                        backgroundColor: DashboardTints.goalBg,
                        iconCircleColor: DashboardTints.goalIconCircle,
                        iconColor: AppColors.primaryDark,
                        icon: LucideIcons.scrollText,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Quick links', style: AppTypography.heading3),
            const SizedBox(height: AppSpacing.md),
            PillrCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _AdminQuickLink(
                    label: 'Users',
                    icon: LucideIcons.users,
                    onTap: () => context.go('/users'),
                    showDivider: true,
                  ),
                  _AdminQuickLink(
                    label: 'Invitations',
                    icon: LucideIcons.mail,
                    onTap: () => context.go('/invitations'),
                    showDivider: true,
                  ),
                  _AdminQuickLink(
                    label: 'Activity logs',
                    icon: LucideIcons.scrollText,
                    onTap: () => context.go('/logs'),
                    showDivider: true,
                  ),
                  _AdminQuickLink(
                    label: 'Settings',
                    icon: LucideIcons.settings,
                    onTap: () => context.go('/settings'),
                    showDivider: false,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
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
                  child: Text(
                    '$e',
                    style: AppTypography.caption.copyWith(color: AppColors.dangerColor),
                  ),
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

class _AdminQuickLink extends StatelessWidget {
  const _AdminQuickLink({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.showDivider,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 16),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppColors.gray600),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    label,
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.gray900,
                    ),
                  ),
                ),
                Icon(LucideIcons.chevronRight, size: 18, color: AppColors.gray400),
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
