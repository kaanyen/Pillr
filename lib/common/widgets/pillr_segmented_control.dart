import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import 'pillr_icon.dart';

/// Linear / Untitled-style segmented control: white surface, 1px border, inner pill selection.
class PillrSegment<T extends Object> {
  const PillrSegment({
    required this.value,
    required this.label,
    this.icon,
  });

  final T value;
  final String label;
  final IconData? icon;
}

class PillrSegmentedControl<T extends Object> extends StatelessWidget {
  const PillrSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.accentSelection = true,
  });

  final List<PillrSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  /// When true, selected chip uses primary @ 10% fill; otherwise neutral gray tint.
  final bool accentSelection;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            _SegmentChip<T>(
              segment: segments[i],
              selected: segments[i].value == selected,
              onTap: () => onChanged(segments[i].value),
              accentSelection: accentSelection,
            ),
          ],
        ],
      ),
    );
  }
}

class _SegmentChip<T extends Object> extends StatelessWidget {
  const _SegmentChip({
    required this.segment,
    required this.selected,
    required this.onTap,
    required this.accentSelection,
  });

  final PillrSegment<T> segment;
  final bool selected;
  final VoidCallback onTap;
  final bool accentSelection;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    if (selected) {
      if (accentSelection) {
        bg = AppColors.primaryColor.withValues(alpha: 0.1);
        fg = AppColors.primaryDark;
      } else {
        bg = AppColors.gray900.withValues(alpha: 0.06);
        fg = AppColors.gray900;
      }
    } else {
      bg = Colors.transparent;
      fg = AppColors.textSecondary;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (segment.icon != null) ...[
                PillrIcon(segment.icon!, size: 16, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                segment.label,
                style: AppTypography.label.copyWith(
                  color: fg,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
