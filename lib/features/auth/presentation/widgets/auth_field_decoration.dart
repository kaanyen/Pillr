import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Outlined fields on white — matches reference card inputs (no filled gray blocks).
InputDecoration authCardInputDecoration({
  String? hintText,
  Widget? suffixIcon,
}) {
  const radius = 10.0;
  const borderSide = BorderSide(color: AppColors.gray200);
  return InputDecoration(
    hintText: hintText,
    filled: true,
    fillColor: AppColors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(radius)),
      borderSide: borderSide,
    ),
    enabledBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(radius)),
      borderSide: borderSide,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(radius)),
      borderSide: BorderSide(color: AppColors.primaryColor.withValues(alpha: 0.9)),
    ),
    suffixIcon: suffixIcon,
  );
}
