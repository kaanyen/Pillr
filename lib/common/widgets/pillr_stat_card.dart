import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

/// Stat tile — the number is the whole point.
///
/// Label sits small and Smoke above; the value drops in at display weight so
/// the size gap does the hierarchy. Deltas are monochrome: direction is an
/// arrow icon, not a green/red hue.
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
    this.emphasized = false,
  });

  final String label;
  final String valueText;
  final double? deltaPercent;
  final bool? deltaPositive;
  final String periodLabel;
  final IconData? icon;

  /// Retained for source compatibility; the system uses Paper or Mist only.
  final Color? backgroundColor;
  final Color? iconCircleColor;
  final Color? iconColor;

  /// Inverts the tile to Charcoal. At most one per row — the "hero" metric.
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final onDark = emphasized;
    final fg = onDark ? AppColors.paper : AppColors.ink;
    final muted = onDark ? AppColors.pewter : AppColors.smoke;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: onDark ? AppColors.charcoal : AppColors.paper,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: onDark
            ? null
            : Border.all(color: AppColors.fog, width: AppBorders.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.caption.copyWith(color: muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (icon != null)
                Icon(icon, size: 18, color: muted),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Display face, tight tracking — the tile's reason to exist.
          Text(
            valueText,
            style: AppTypography.headingLg.copyWith(color: fg),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (deltaPercent != null && deltaPositive != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(
                  deltaPositive! ? LucideIcons.arrowUpRight : LucideIcons.arrowDownRight,
                  size: 14,
                  color: fg,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '${deltaPercent!.abs().toStringAsFixed(1)}%',
                  style: AppTypography.caption.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (periodLabel.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      periodLabel,
                      style: AppTypography.caption.copyWith(color: muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ] else if (periodLabel.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              periodLabel,
              style: AppTypography.caption.copyWith(color: muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
