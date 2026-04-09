import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// App-styled [showDatePicker]: Inter via theme, near-black accents, outlined
/// Cancel + solid OK. Relies on [ThemeData.datePickerTheme] from [AppTheme].
Future<DateTime?> showPillrDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  DatePickerEntryMode initialEntryMode = DatePickerEntryMode.calendar,
  SelectableDayPredicate? selectableDayPredicate,
  String? helpText,
  String? cancelText,
  String? confirmText,
}) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;

  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    initialEntryMode: initialEntryMode,
    selectableDayPredicate: selectableDayPredicate,
    helpText: helpText,
    cancelText: cancelText,
    confirmText: confirmText,
    builder: (context, child) {
      return Theme(
        data: theme.copyWith(
          colorScheme: cs.copyWith(
            primary: AppColors.gray900,
            onPrimary: AppColors.white,
            surface: AppColors.white,
            onSurface: AppColors.gray900,
            surfaceContainerHighest: AppColors.gray100,
          ),
          iconTheme: IconThemeData(color: AppColors.gray600, size: 20),
        ),
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.12),
          ),
          child: child!,
        ),
      );
    },
  );
}
