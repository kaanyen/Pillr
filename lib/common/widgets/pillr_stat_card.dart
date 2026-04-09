import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';

/// Stat tile — white or soft-tint surface, large value, optional delta row.
class PillrStatCard extends StatelessWidget {
  const PillrStatCard({
    super.key,
    required this.label,
    required this.valueText,
    this.deltaPercent,
    this.deltaPositive,
    this.periodLabel = 'Last 30 days',
    this.icon,
    this.backgroundColor,
    this.iconCircleColor,
    this.iconColor,
  });

  final String label;
  final String valueText;
  final double? deltaPercent;
  final bool? deltaPositive;
  final String periodLabel;
  final IconData? icon;
  /// Soft wash behind the card (modern SaaS summary tiles).
  final Color? backgroundColor;
  final Color? iconCircleColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? AppColors.white;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md + 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.gray200),
        boxShadow: AppTheme.cardShadow,
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
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (icon != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconCircleColor ?? AppColors.white.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: iconColor ?? AppColors.gray600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            valueText,
            style: AppTypography.display.copyWith(
              fontSize: 28,
              color: AppColors.gray900,
              letterSpacing: -0.5,
            ),
          ),
          if (deltaPercent != null && deltaPositive != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(
                  deltaPositive!
                      ? LucideIcons.trendingUp
                      : LucideIcons.trendingDown,
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
          ] else if (periodLabel.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              periodLabel,
              style: AppTypography.caption.copyWith(color: AppColors.gray400),
            ),
          ],
        ],
      ),
    );
  }
}
