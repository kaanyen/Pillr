import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// Thin progress bar — table cells & stats (Reference 1 / 3).
class PillrProgressBar extends StatelessWidget {
  const PillrProgressBar({
    super.key,
    required this.value,
    this.height = 6,
    this.backgroundColor,
    this.foregroundColor,
  });

  /// 0..1
  final double value;
  final double height;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: LinearProgressIndicator(
        value: v,
        minHeight: height,
        backgroundColor: backgroundColor ?? AppColors.gray200,
        color: foregroundColor ?? AppColors.primaryColor,
      ),
    );
  }
}
