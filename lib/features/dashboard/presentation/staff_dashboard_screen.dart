import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../common/widgets/pillr_stat_card.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_utils.dart';
import '../providers/dashboard_stats_providers.dart';

class StaffDashboardScreen extends ConsumerWidget {
  const StaffDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(staffMyEntryStatsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('My dashboard', style: AppTypography.heading2),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Live totals from your submitted entries.',
            style: AppTypography.body,
          ),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, c) {
              final cross = c.maxWidth > 700 ? 2 : 1;
              return GridView.count(
                crossAxisCount: cross,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpacing.md,
                crossAxisSpacing: AppSpacing.md,
                childAspectRatio: 1.45,
                children: [
                  PillrStatCard(
                    label: 'My entries',
                    valueText: '${s.totalCount}',
                    periodLabel: 'All statuses',
                  ),
                  PillrStatCard(
                    label: 'My approved total',
                    valueText: formatCedis(s.approvedTotalCedis),
                    periodLabel: '${s.approvedCount} approved',
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
