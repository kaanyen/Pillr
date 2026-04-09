import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import 'pillr_icon.dart';

enum PillrButtonVariant { primary, secondary, danger, ghost }

class PillrButton extends StatelessWidget {
  const PillrButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = PillrButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.expanded = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final PillrButtonVariant variant;
  final IconData? icon;
  final bool loading;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final primaryFg = AppColors.white;
    final secondaryFg = AppColors.gray900;
    final dangerFg = AppColors.white;
    final ghostFg = AppColors.primaryColor;

    final child = loading
        ? SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: variant == PillrButtonVariant.primary ||
                      variant == PillrButtonVariant.danger
                  ? Colors.white
                  : AppColors.primaryColor,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                PillrIcon(
                  icon!,
                  size: 20,
                  color: switch (variant) {
                    PillrButtonVariant.primary => primaryFg,
                    PillrButtonVariant.secondary => secondaryFg,
                    PillrButtonVariant.danger => dangerFg,
                    PillrButtonVariant.ghost => ghostFg,
                  },
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Text(
                label,
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: switch (variant) {
                    PillrButtonVariant.primary => primaryFg,
                    PillrButtonVariant.secondary => secondaryFg,
                    PillrButtonVariant.danger => dangerFg,
                    PillrButtonVariant.ghost => ghostFg,
                  },
                ),
              ),
            ],
          );

    final button = switch (variant) {
      PillrButtonVariant.primary => ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.onAccent,
            foregroundColor: AppColors.white,
            disabledBackgroundColor: AppColors.gray200,
            elevation: 0,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
          ),
          child: child,
        ),
      PillrButtonVariant.secondary => OutlinedButton(
          onPressed: loading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.gray900,
            side: const BorderSide(color: AppColors.gray200),
            backgroundColor: AppColors.white,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
          ),
          child: child,
        ),
      PillrButtonVariant.danger => ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.dangerColor,
            foregroundColor: AppColors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
          ),
          child: child,
        ),
      PillrButtonVariant.ghost => TextButton(
          onPressed: loading ? null : onPressed,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primaryColor,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
          ),
          child: child,
        ),
    };

    if (expanded) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}
