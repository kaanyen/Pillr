import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';

class PillrCard extends StatelessWidget {
  const PillrCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.noBorder = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool noBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: noBorder ? null : Border.all(color: AppColors.gray200),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
