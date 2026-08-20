import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import 'pillr_icon.dart';

/// Button variants in the Hellotime system.
///
/// There is **one** filled button per section — the Charcoal [primary].
/// Everything else is a Pewter-outlined ghost. That restraint is what makes
/// the filled button read as "the action" without needing color.
enum PillrButtonVariant {
  /// Charcoal fill, Paper text. The single primary action. Hover lifts to Ink.
  primary,

  /// Pewter hairline, Ink text, Mist wash on hover.
  secondary,

  /// Destructive. Also Ink-filled — this system does not signal danger with
  /// red. The weight of the fill plus an explicit confirmation dialog carries
  /// the warning instead.
  danger,

  /// Text-only. Lowest priority; no border, Mist wash on hover.
  ghost,
}

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

  bool get _isFilled =>
      variant == PillrButtonVariant.primary || variant == PillrButtonVariant.danger;

  Color get _foreground => switch (variant) {
        PillrButtonVariant.primary => AppColors.paper,
        PillrButtonVariant.danger => AppColors.paper,
        PillrButtonVariant.secondary => AppColors.ink,
        PillrButtonVariant.ghost => AppColors.ink,
      };

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _foreground,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                PillrIcon(icon!, size: 16, color: _foreground),
                const SizedBox(width: AppSpacing.sm),
              ],
              Text(
                label,
                style: (_isFilled
                        ? AppTypography.labelStrong
                        : AppTypography.label)
                    .copyWith(color: _foreground),
              ),
            ],
          );

    // 10px vertical × 20px horizontal — the reference button box.
    const padding = EdgeInsets.symmetric(horizontal: 20, vertical: 10);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.button),
    );

    final button = switch (variant) {
      PillrButtonVariant.primary || PillrButtonVariant.danger => FilledButton(
          onPressed: loading ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.charcoal,
            foregroundColor: AppColors.paper,
            disabledBackgroundColor: AppColors.pewter,
            disabledForegroundColor: AppColors.paper,
            elevation: 0,
            shadowColor: Colors.transparent,
            padding: padding,
            minimumSize: const Size(0, 40),
            shape: shape,
          ).copyWith(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) return AppColors.pewter;
              if (states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.pressed)) {
                return AppColors.ink;
              }
              return AppColors.charcoal;
            }),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
          child: child,
        ),
      PillrButtonVariant.secondary => OutlinedButton(
          onPressed: loading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.ink,
            padding: padding,
            minimumSize: const Size(0, 40),
            shape: shape,
          ).copyWith(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.pressed)) {
                return AppColors.mist;
              }
              return Colors.transparent;
            }),
            side: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return const BorderSide(color: AppColors.ash);
              }
              return BorderSide(
                color: states.contains(WidgetState.hovered)
                    ? AppColors.ink
                    : AppColors.pewter,
                width: AppBorders.hairline,
              );
            }),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
          child: child,
        ),
      PillrButtonVariant.ghost => TextButton(
          onPressed: loading ? null : onPressed,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.ink,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            minimumSize: const Size(0, 40),
            shape: shape,
          ).copyWith(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered)) return AppColors.mist;
              return Colors.transparent;
            }),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
          child: child,
        ),
    };

    if (expanded) return SizedBox(width: double.infinity, child: button);
    return button;
  }
}

/// The eyebrow pill — a 9999px-radius link that sits above hero headlines as a
/// contextual cue. Ink hairline, 12/500 text, optional trailing chevron.
class PillrPillLink extends StatelessWidget {
  const PillrPillLink({
    super.key,
    required this.label,
    this.onTap,
    this.trailingIcon,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.full),
        hoverColor: AppColors.mist,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.ink, width: AppBorders.hairline),
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: AppTypography.pill),
              if (trailingIcon != null) ...[
                const SizedBox(width: AppSpacing.xs),
                PillrIcon(trailingIcon!, size: 14, color: AppColors.ink),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
