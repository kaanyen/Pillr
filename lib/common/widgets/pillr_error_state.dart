import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/pillr_layout.dart';
import 'pillr_button.dart';

/// Error state — monochrome, like every other state in this system.
///
/// No red. The failure reads through an Ink-filled icon block and a
/// display-weight headline; the detail message stays Smoke so the recovery
/// action is what the eye lands on.
class PillrErrorState extends StatelessWidget {
  const PillrErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = PillrLayout.isCompact(width);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: PillrLayout.proseMaxWidth),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Inverted block — the one place an error earns extra weight.
              Container(
                height: 56,
                width: 56,
                decoration: BoxDecoration(
                  color: AppColors.charcoal,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: const Icon(
                  LucideIcons.alertCircle,
                  size: 24,
                  color: AppColors.paper,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Something went wrong',
                style: compact ? AppTypography.heading : AppTypography.headingLgFor(width),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(message, style: AppTypography.subheading, textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: AppSpacing.xl),
                PillrButton(label: 'Try again', onPressed: onRetry),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
