import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

enum PillrBadgeKind {
  approved,
  pending,
  declined,
  active,
  inactive,
}

class PillrBadge extends StatelessWidget {
  const PillrBadge({
    super.key,
    required this.label,
    required this.kind,
    this.compact = false,
  });

  final String label;
  final PillrBadgeKind kind;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (kind) {
      PillrBadgeKind.approved => (
          AppColors.successColor.withValues(alpha: 0.1),
          AppColors.successColor,
          LucideIcons.checkCircle,
        ),
      PillrBadgeKind.pending => (
          AppColors.warningColor.withValues(alpha: 0.1),
          AppColors.warningColor,
          LucideIcons.clock,
        ),
      PillrBadgeKind.declined => (
          AppColors.dangerColor.withValues(alpha: 0.1),
          AppColors.dangerColor,
          LucideIcons.x,
        ),
      PillrBadgeKind.active => (
          AppColors.successColor.withValues(alpha: 0.1),
          AppColors.successColor,
          LucideIcons.circle,
        ),
      PillrBadgeKind.inactive => (
          AppColors.gray600.withValues(alpha: 0.1),
          AppColors.gray600,
          LucideIcons.circleDashed,
        ),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 14 : 16, color: fg),
          SizedBox(width: compact ? 4 : 6),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: compact ? 11 : 12,
            ),
          ),
        ],
      ),
    );
  }
}
