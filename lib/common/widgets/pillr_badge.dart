import 'package:flutter/material.dart';

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
          AppColors.successLight,
          AppColors.successColor,
          Icons.check_rounded,
        ),
      PillrBadgeKind.pending => (
          AppColors.warningLight,
          AppColors.warningColor,
          Icons.schedule_rounded,
        ),
      PillrBadgeKind.declined => (
          AppColors.dangerLight,
          AppColors.dangerColor,
          Icons.close_rounded,
        ),
      PillrBadgeKind.active => (
          AppColors.successLight,
          AppColors.successColor,
          Icons.circle,
        ),
      PillrBadgeKind.inactive => (
          AppColors.gray100,
          AppColors.gray400,
          Icons.circle_outlined,
        ),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
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
