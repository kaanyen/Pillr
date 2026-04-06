import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

class PillrLoadingShimmer extends StatelessWidget {
  const PillrLoadingShimmer({
    super.key,
    this.height = 56,
    this.borderRadius = AppRadius.md,
  });

  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.gray100,
      highlightColor: AppColors.white,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: AppColors.gray100,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}
