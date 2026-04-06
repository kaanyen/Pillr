import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import 'pillr_card.dart';

class FeaturePlaceholderScaffold extends StatelessWidget {
  const FeaturePlaceholderScaffold({
    super.key,
    required this.title,
    required this.message,
    this.phaseLabel = 'Phase 2',
  });

  final String title;
  final String message;
  final String phaseLabel;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: PillrCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTypography.heading2),
            const SizedBox(height: AppSpacing.sm),
            Text('$phaseLabel — $message', style: AppTypography.body),
          ],
        ),
      ),
    );
  }
}
