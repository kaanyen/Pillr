import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';

/// Monochrome state vocabulary.
///
/// The style reference is explicit: *do not use color for status or state*.
/// State is carried by **fill, border, weight and icon** instead — which also
/// happens to be more legible to colorblind users than the amber/green/red
/// badges this replaces.
///
/// The four levels, from loudest to quietest:
///
/// | Level     | Fill      | Border  | Text   | Reads as        |
/// |-----------|-----------|---------|--------|-----------------|
/// | [solid]   | Charcoal  | —       | Paper  | settled, final  |
/// | [wash]    | Mist      | Fog     | Ink    | in progress     |
/// | [outline] | —         | Pewter  | Smoke  | closed, negative|
/// | [quiet]   | —         | —       | Smoke  | ambient         |
enum PillrStatusLevel { solid, wash, outline, quiet }

/// A resolved monochrome status appearance.
@immutable
class PillrStatusStyle {
  const PillrStatusStyle({
    required this.level,
    required this.icon,
    required this.background,
    required this.border,
    required this.foreground,
    required this.fontWeight,
  });

  final PillrStatusLevel level;
  final IconData icon;
  final Color background;
  final Color? border;
  final Color foreground;
  final FontWeight fontWeight;

  static const PillrStatusStyle approved = PillrStatusStyle(
    level: PillrStatusLevel.solid,
    icon: LucideIcons.check,
    background: AppColors.charcoal,
    border: null,
    foreground: AppColors.paper,
    fontWeight: FontWeight.w600,
  );

  static const PillrStatusStyle pending = PillrStatusStyle(
    level: PillrStatusLevel.wash,
    icon: LucideIcons.clock,
    background: AppColors.mist,
    border: AppColors.fog,
    foreground: AppColors.ink,
    fontWeight: FontWeight.w500,
  );

  static const PillrStatusStyle declined = PillrStatusStyle(
    level: PillrStatusLevel.outline,
    icon: LucideIcons.x,
    background: Colors.transparent,
    border: AppColors.pewter,
    foreground: AppColors.smoke,
    fontWeight: FontWeight.w500,
  );

  static const PillrStatusStyle active = PillrStatusStyle(
    level: PillrStatusLevel.wash,
    icon: LucideIcons.circle,
    background: AppColors.mist,
    border: AppColors.fog,
    foreground: AppColors.ink,
    fontWeight: FontWeight.w500,
  );

  static const PillrStatusStyle inactive = PillrStatusStyle(
    level: PillrStatusLevel.quiet,
    icon: LucideIcons.circleDashed,
    background: Colors.transparent,
    border: AppColors.ash,
    foreground: AppColors.smoke,
    fontWeight: FontWeight.w400,
  );

  /// Maps a raw Firestore `status` string to its appearance.
  /// Unknown values fall through to [pending] rather than throwing.
  static PillrStatusStyle forStatus(String? status) {
    switch (status?.trim().toLowerCase()) {
      case 'approved':
        return approved;
      case 'declined':
      case 'rejected':
      case 'expired':
        return declined;
      case 'active':
        return active;
      case 'inactive':
      case 'suspended':
        return inactive;
      case 'pending':
      default:
        return pending;
    }
  }
}
