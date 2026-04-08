import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../common/widgets/fade_in_once.dart';
import '../../../common/widgets/pillr_card.dart';
import '../../../common/widgets/pillr_stat_card.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../activity/domain/activity_log_row.dart';
import '../../logs/providers/activity_logs_providers.dart';
import '../providers/admin_dashboard_providers.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersCount = ref.watch(churchUsersCountProvider);
    final pendingInvites = ref.watch(pendingInvitesCountProvider);
    final activityAsync = ref.watch(activityLogsPreviewProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(activityLogsPreviewProvider);
        ref.invalidate(invitesListForAdminProvider);
        ref.invalidate(churchUsersCountProvider);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Admin console', style: AppTypography.heading2),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'People, invitations, and audit activity. Financial routes stay hidden for this role.',
            style: AppTypography.body,
          ),
          const SizedBox(height: AppSpacing.lg),
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
                    ),
                  ),
                  FadeInOnce(
                    delay: const Duration(milliseconds: 50),
                    child: PillrStatCard(
                      label: 'Pending invites',
                      valueText: '$pendingInvites',
                      periodLabel: 'awaiting acceptance',
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
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Text('Quick links', style: AppTypography.heading3),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              TextButton(onPressed: () => context.go('/users'), child: const Text('Users')),
              TextButton(onPressed: () => context.go('/invitations'), child: const Text('Invitations')),
              TextButton(onPressed: () => context.go('/logs'), child: const Text('Activity logs')),
              TextButton(onPressed: () => context.go('/settings'), child: const Text('Settings')),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Recent activity', style: AppTypography.heading3),
          const SizedBox(height: AppSpacing.sm),
          activityAsync.when(
            loading: () => const Text('Loading…'),
            error: (e, _) => Text('$e'),
            data: (logs) {
              final slice = logs.take(10).toList();
              if (slice.isEmpty) {
                return Text('No activity yet.', style: AppTypography.caption);
              }
              return PillrCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final row in slice) _AdminActivityLine(row: row),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      ),
    );
  }
}

class _AdminActivityLine extends StatelessWidget {
  const _AdminActivityLine({required this.row});

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
          SizedBox(width: 120, child: Text(when, style: AppTypography.caption)),
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
