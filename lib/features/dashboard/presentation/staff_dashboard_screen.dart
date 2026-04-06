import 'package:flutter/material.dart';

import '../../../common/widgets/pillr_stat_card.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_utils.dart';

class StaffDashboardScreen extends StatelessWidget {
  const StaffDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('My dashboard', style: AppTypography.heading2),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Track your submitted entries. Approval workflow arrives in Phase 2.',
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
                    valueText: '12',
                    deltaPercent: 5.0,
                    deltaPositive: true,
                  ),
                  PillrStatCard(
                    label: 'My approved total',
                    valueText: formatCedis(4200),
                    deltaPercent: 2.1,
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
