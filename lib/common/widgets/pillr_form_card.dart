import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import 'pillr_surface_card.dart';

/// Section title + optional subtitle + body inside an elevated card (forms / settings).
class PillrFormCard extends StatelessWidget {
  const PillrFormCard({
    super.key,
    this.title,
    this.subtitle,
    this.leading,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final String? title;
  final String? subtitle;
  /// Optional icon in a circle (reference: form header with flag icon).
  final Widget? leading;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return PillrSurfaceCard(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null) ...[
              if (leading != null)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    leading!,
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title!, style: AppTypography.heading3.copyWith(color: AppColors.gray900)),
                          if (subtitle != null && subtitle!.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              subtitle!,
                              style: AppTypography.body.copyWith(
                                color: AppColors.textSecondary,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                )
              else ...[
                Text(title!, style: AppTypography.heading3.copyWith(color: AppColors.gray900)),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(subtitle!, style: AppTypography.caption),
                ],
              ],
              const SizedBox(height: AppSpacing.md),
              Divider(height: 1, color: AppColors.gray200.withValues(alpha: 0.9)),
              const SizedBox(height: AppSpacing.md),
            ],
            child,
          ],
        ),
      ),
    );
  }
}
