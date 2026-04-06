import 'package:flutter/material.dart';

import '../../../common/widgets/pillr_stat_card.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Admin console', style: AppTypography.heading2),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'User management and audit trails. Financial dashboards stay hidden per your role.',
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
                  PillrStatCard(
                    label: 'Workspace users',
                    valueText: '14',
                    deltaPercent: null,
                    deltaPositive: null,
                    periodLabel: 'active accounts',
                  ),
                  PillrStatCard(
                    label: 'Pending invites',
                    valueText: '2',
                    deltaPercent: null,
                    deltaPositive: null,
                  ),
                  PillrStatCard(
                    label: 'Events (24h)',
                    valueText: '156',
                    deltaPercent: 1.2,
                    deltaPositive: true,
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
