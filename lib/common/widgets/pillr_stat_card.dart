import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

/// Reference 2 (Brightly) style stat tile — label, large number, delta + period.
class PillrStatCard extends StatelessWidget {
  const PillrStatCard({
    super.key,
    required this.label,
    required this.valueText,
    this.deltaPercent,
    this.deltaPositive,
    this.periodLabel = 'Last 30 days',
    this.icon,
  });

  final String label;
  final String valueText;
  final double? deltaPercent;
  final bool? deltaPositive;
  final String periodLabel;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md + 4),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.gray200),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.gray600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (icon != null)
                Icon(icon, size: 20, color: AppColors.gray400),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            valueText,
            style: AppTypography.display.copyWith(fontSize: 28),
          ),
          if (deltaPercent != null && deltaPositive != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(
                  deltaPositive!
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  size: 18,
                  color: deltaPositive! ? AppColors.successColor : AppColors.dangerColor,
                ),
                const SizedBox(width: 4),
                Text(
                  '${deltaPositive! ? '▲' : '▼'} ${deltaPercent!.abs().toStringAsFixed(2)}%',
                  style: AppTypography.caption.copyWith(
                    color: deltaPositive! ? AppColors.successColor : AppColors.dangerColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  periodLabel,
                  style: AppTypography.caption,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
