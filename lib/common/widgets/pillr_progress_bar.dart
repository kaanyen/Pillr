import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// Thin progress bar — 4px radius, Ash track, Ink fill.
///
/// Progress is monochrome by default. Pass [foregroundColor] only inside a
/// product-timeline context, where [AppColors.timelineBar] hues are the one
/// sanctioned use of saturation.
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
      borderRadius: BorderRadius.circular(AppRadius.bar),
      child: LinearProgressIndicator(
        value: v,
        minHeight: height,
        backgroundColor: backgroundColor ?? AppColors.ash,
        color: foregroundColor ?? AppColors.ink,
      ),
    );
  }
}
