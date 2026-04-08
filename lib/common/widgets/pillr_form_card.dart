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
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final String? title;
  final String? subtitle;
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
              Text(title!, style: AppTypography.heading3.copyWith(color: AppColors.gray900)),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(subtitle!, style: AppTypography.caption),
              ],
              const SizedBox(height: AppSpacing.md),
              Divider(height: 1, color: AppColors.gray200.withOpacity(0.9)),
              const SizedBox(height: AppSpacing.md),
            ],
            child,
          ],
        ),
      ),
    );
  }
}
