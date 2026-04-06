import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

/// Phase 2 will wire Firestore search. Shell API matches build doc §2.
class PillrSearchableDropdownTile<T> extends StatelessWidget {
  const PillrSearchableDropdownTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTypography.body.copyWith(color: AppColors.gray900)),
            if (subtitle != null)
              Text(subtitle!, style: AppTypography.caption),
          ],
        ),
      ),
    );
  }
}
