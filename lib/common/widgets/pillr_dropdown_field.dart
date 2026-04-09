import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import 'pillr_icon.dart';

/// Bordered, rounded dropdown (no Material underline) for filters and inline selects.
class PillrDropdownButton<T> extends StatelessWidget {
  const PillrDropdownButton({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
    this.isDense = false,
    this.isExpanded = true,
    this.minWidth,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final Widget? hint;
  final bool isDense;
  final bool isExpanded;
  final double? minWidth;

  @override
  Widget build(BuildContext context) {
    final child = DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        items: items,
        onChanged: onChanged,
        hint: hint,
        isDense: isDense,
        isExpanded: isExpanded,
        borderRadius: BorderRadius.circular(AppRadius.button),
        dropdownColor: AppColors.white,
        icon: PillrIcon(
          LucideIcons.chevronDown,
          size: isDense ? 16 : 18,
          color: AppColors.gray600,
        ),
        style: AppTypography.body.copyWith(color: AppColors.gray900, fontWeight: FontWeight.w500),
        underline: const SizedBox.shrink(),
      ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth ?? 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadius.button),
          border: Border.all(color: AppColors.gray200),
        ),
        child: child,
      ),
    );
  }
}
