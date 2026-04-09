import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

/// Modal form shell: circular header icon, title, subtitle, scrollable body, footer actions.
class PillrFormDialog extends StatelessWidget {
  const PillrFormDialog({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.maxWidth = 560,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final double maxWidth;
  final Widget child;

  /// Gray circle + icon (reference form header).
  static Widget leadingIcon(IconData icon, {Color? backgroundColor, Color? iconColor}) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.gray100,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: 22,
        color: iconColor ?? AppColors.gray600,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final contentWidth = math.min(maxWidth, w - 48);
    return AlertDialog(
      backgroundColor: AppColors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.gray200),
      ),
      titlePadding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.heading3.copyWith(color: AppColors.gray900)),
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
      ),
      contentPadding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
      content: SizedBox(
        width: contentWidth,
        child: SingleChildScrollView(
          child: child,
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
      actions: actions,
    );
  }
}
