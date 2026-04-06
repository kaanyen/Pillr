import 'package:flutter/material.dart';

import '../../../common/widgets/pillr_card.dart';
import '../../../common/widgets/pillr_stat_card.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_utils.dart';

/// Reference 2 stat row + Reference 3 segmented progress header.
class PastorDashboardScreen extends StatelessWidget {
  const PastorDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Overview', style: AppTypography.heading2),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Partnership health for the active period — live data arrives in Phase 3.',
            style: AppTypography.body,
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
                  PillrStatCard(
                    label: 'Total collected',
                    valueText: formatCedis(148250),
                    deltaPercent: 12.4,
                    deltaPositive: true,
                  ),
                  PillrStatCard(
                    label: 'Pending approvals',
                    valueText: '8',
                    deltaPercent: 3.1,
                    deltaPositive: false,
                  ),
                  PillrStatCard(
                    label: 'Active partners',
                    valueText: '128',
                    deltaPercent: 4.2,
                    deltaPositive: true,
                  ),
                  PillrStatCard(
                    label: 'Goal progress',
                    valueText: '64%',
                    deltaPercent: 8.0,
                    deltaPositive: true,
                    periodLabel: 'vs last period',
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
                      '34 entries · ${formatCedis(48200)}',
                      style: AppTypography.caption,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _SegmentBar(
                  segments: const [
                    _Seg(0.45, AppColors.progressTeal),
                    _Seg(0.28, AppColors.progressOrange),
                    _Seg(0.27, AppColors.progressRed),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.sm,
                  children: [
                    _LegendDot(color: AppColors.progressTeal, label: 'Approved'),
                    _LegendDot(color: AppColors.progressOrange, label: 'Pending'),
                    _LegendDot(color: AppColors.progressRed, label: 'Declined'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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
