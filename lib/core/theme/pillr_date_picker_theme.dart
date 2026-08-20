import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Date picker in the Hellotime idiom.
///
/// Selection is a Charcoal fill; "today" is a hairline ring. No hue, no
/// elevation — the same two devices the rest of the system uses.
DatePickerThemeData buildPillrDatePickerTheme() {
  return DatePickerThemeData(
    backgroundColor: AppColors.paper,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shadowColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
      side: BorderSide(color: AppColors.fog, width: AppBorders.hairline),
    ),

    headerBackgroundColor: AppColors.paper,
    headerForegroundColor: AppColors.ink,
    headerHeadlineStyle: AppTypography.headingSm,
    headerHelpStyle: AppTypography.caption,

    weekdayStyle: AppTypography.micro.copyWith(fontWeight: FontWeight.w500),
    dayStyle: AppTypography.label.copyWith(fontWeight: FontWeight.w400),

    dayForegroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return AppColors.pewter;
      if (states.contains(WidgetState.selected)) return AppColors.paper;
      return AppColors.ink;
    }),
    dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return AppColors.charcoal;
      if (states.contains(WidgetState.hovered)) return AppColors.mist;
      return Colors.transparent;
    }),
    dayOverlayColor: const WidgetStatePropertyAll(Colors.transparent),
    dayShape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.button)),
      ),
    ),

    todayForegroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return AppColors.paper;
      return AppColors.ink;
    }),
    todayBackgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return AppColors.charcoal;
      return Colors.transparent;
    }),
    todayBorder: const BorderSide(color: AppColors.ink, width: AppBorders.hairline),

    yearForegroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return AppColors.pewter;
      if (states.contains(WidgetState.selected)) return AppColors.paper;
      return AppColors.ink;
    }),
    yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return AppColors.charcoal;
      if (states.contains(WidgetState.hovered)) return AppColors.mist;
      return Colors.transparent;
    }),
    yearOverlayColor: const WidgetStatePropertyAll(Colors.transparent),
    yearStyle: AppTypography.label.copyWith(fontWeight: FontWeight.w400),

    rangePickerBackgroundColor: AppColors.paper,
    rangePickerSurfaceTintColor: Colors.transparent,
    rangePickerElevation: 0,
    rangePickerShadowColor: Colors.transparent,
    rangePickerHeaderBackgroundColor: AppColors.paper,
    rangePickerHeaderForegroundColor: AppColors.ink,
    rangePickerHeaderHeadlineStyle: AppTypography.headingSm,
    rangePickerHeaderHelpStyle: AppTypography.caption,
    rangeSelectionBackgroundColor: AppColors.mist,
    rangeSelectionOverlayColor: const WidgetStatePropertyAll(Colors.transparent),

    dividerColor: AppColors.fog,
    confirmButtonStyle: _dialogButton(filled: true),
    cancelButtonStyle: _dialogButton(filled: false),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.mist,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
        borderSide: const BorderSide(color: AppColors.ash),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
        borderSide: const BorderSide(color: AppColors.ash),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
        borderSide: const BorderSide(color: AppColors.ink, width: 1.5),
      ),
      labelStyle: AppTypography.body.copyWith(color: AppColors.smoke),
      hintStyle: AppTypography.body.copyWith(color: AppColors.pewter),
    ),
  );
}

ButtonStyle _dialogButton({required bool filled}) {
  return ButtonStyle(
    foregroundColor: WidgetStatePropertyAll(
      filled ? AppColors.paper : AppColors.ink,
    ),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (!filled) {
        return states.contains(WidgetState.hovered)
            ? AppColors.mist
            : Colors.transparent;
      }
      return states.contains(WidgetState.hovered)
          ? AppColors.ink
          : AppColors.charcoal;
    }),
    side: filled
        ? null
        : const WidgetStatePropertyAll(
            BorderSide(color: AppColors.pewter, width: AppBorders.hairline),
          ),
    elevation: const WidgetStatePropertyAll(0),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    ),
    textStyle: WidgetStatePropertyAll(
      filled ? AppTypography.labelStrong : AppTypography.label,
    ),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.button)),
      ),
    ),
  );
}
