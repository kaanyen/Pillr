import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/pillr_layout.dart';
import 'pillr_button.dart';

/// Empty state as an editorial moment.
///
/// An empty screen is the lowest-density surface in the app, so it gets the
/// full treatment: a hairline-ringed icon, display-weight headline, Smoke
/// subtext on a 640px measure, and a single Charcoal action.
class PillrEmptyState extends StatelessWidget {
  const PillrEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.icon = LucideIcons.inbox,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = PillrLayout.isCompact(width);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: PillrLayout.proseMaxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: compact ? AppSpacing.xxl : AppSpacing.section,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon in a hairline ring — the system's only "ornament".
              Container(
                height: 56,
                width: 56,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.fog, width: AppBorders.hairline),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Icon(icon, size: 24, color: AppColors.smoke),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title,
                style: compact
                    ? AppTypography.heading
                    : AppTypography.headingLgFor(width),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(message, style: AppTypography.subheading, textAlign: TextAlign.center),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpacing.xl),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  alignment: WrapAlignment.center,
                  children: [
                    PillrButton(
                      label: actionLabel!,
                      onPressed: onAction,
                    ),
                    if (secondaryActionLabel != null && onSecondaryAction != null)
                      PillrButton(
                        label: secondaryActionLabel!,
                        onPressed: onSecondaryAction,
                        variant: PillrButtonVariant.secondary,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
