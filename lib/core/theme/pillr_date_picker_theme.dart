import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Modern Minimalist SaaS date picker — white surface, soft border, near-black
/// selection, outlined cancel + solid primary confirm (see design tokens).
DatePickerThemeData buildPillrDatePickerTheme() {
  final baseDay = AppTypography.body.copyWith(fontWeight: FontWeight.w500);
  return DatePickerThemeData(
    backgroundColor: AppColors.white,
    elevation: 6,
    shadowColor: const Color(0x14000000),
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.xl),
      side: const BorderSide(color: AppColors.gray200),
    ),
    headerBackgroundColor: AppColors.white,
    headerForegroundColor: AppColors.gray900,
    headerHelpStyle: AppTypography.caption.copyWith(
      color: AppColors.gray600,
      fontWeight: FontWeight.w500,
    ),
    headerHeadlineStyle: AppTypography.heading2.copyWith(
      color: AppColors.gray900,
      fontSize: 22,
    ),
    weekdayStyle: AppTypography.caption.copyWith(
      color: AppColors.gray600,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    ),
    dayStyle: baseDay,
    dayForegroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return AppColors.gray400;
      if (states.contains(WidgetState.selected)) return AppColors.white;
      return AppColors.gray900;
    }),
    dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return AppColors.gray900;
      return null;
    }),
    dayOverlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return AppColors.gray900.withValues(alpha: 0.12);
      return AppColors.gray900.withValues(alpha: 0.06);
    }),
    dayShape: WidgetStateProperty.resolveWith((states) {
      return RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button));
    }),
    todayForegroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return AppColors.white;
      return AppColors.gray900;
    }),
    todayBackgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return AppColors.gray900;
      return AppColors.gray100;
    }),
    todayBorder: const BorderSide(color: AppColors.gray200),
    yearStyle: baseDay,
    yearForegroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return AppColors.gray400;
      if (states.contains(WidgetState.selected)) return AppColors.white;
      return AppColors.gray900;
    }),
    yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return AppColors.gray900;
      return null;
    }),
    yearOverlayColor: WidgetStateProperty.resolveWith((states) {
      return AppColors.gray900.withValues(alpha: 0.06);
    }),
    yearShape: WidgetStateProperty.all(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
    ),
    dividerColor: AppColors.gray200,
    subHeaderForegroundColor: AppColors.gray900,
    rangeSelectionBackgroundColor: AppColors.gray200.withValues(alpha: 0.45),
    rangeSelectionOverlayColor: WidgetStateProperty.all<Color?>(
      AppColors.gray900.withValues(alpha: 0.08),
    ),
    cancelButtonStyle: ButtonStyle(
      foregroundColor: WidgetStateProperty.all(AppColors.gray900),
      backgroundColor: WidgetStateProperty.all(Colors.transparent),
      side: WidgetStateProperty.all(const BorderSide(color: AppColors.gray200)),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm + 2),
      ),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
      ),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return AppColors.gray900.withValues(alpha: 0.06);
        }
        return AppColors.gray900.withValues(alpha: 0.04);
      }),
      textStyle: WidgetStateProperty.all(
        AppTypography.body.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    confirmButtonStyle: ButtonStyle(
      foregroundColor: WidgetStateProperty.all(AppColors.white),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return AppColors.gray400;
        return AppColors.gray900;
      }),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm + 2),
      ),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
      ),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return AppColors.white.withValues(alpha: 0.14);
        }
        return null;
      }),
      textStyle: WidgetStateProperty.all(
        AppTypography.body.copyWith(fontWeight: FontWeight.w600, color: AppColors.white),
      ),
    ),
  );
}
