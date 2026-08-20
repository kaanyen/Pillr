import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Hellotime type system.
///
/// Two optical sizes of Inter, bundled locally (no runtime CDN fetch):
///
/// * [displayFamily] — `InterDisplay`, the SF Pro Display stand-in. Headlines
///   and display sizes (24px and up). Weight 700 at extreme size is the
///   signature of this system: massive bold sans against empty white carries
///   all the visual weight that color would elsewhere.
/// * [textFamily] — `Inter`, the SF Pro Text stand-in. The workhorse for body,
///   labels, buttons, nav links, table cells and form fields.
///
/// The size gap *is* the hierarchy. Headlines run 40–80px at weight 600–700
/// with negative tracking; body stays 16px at weight 400. Resist the urge to
/// fill the gap with intermediate sizes.
abstract final class AppTypography {
  static const String displayFamily = 'InterDisplay';
  static const String textFamily = 'Inter';

  // ---------------------------------------------------------------------
  // Display — InterDisplay. Hero and section titles.
  // ---------------------------------------------------------------------

  /// 80 / 700 / -1.6 — the hero. One per screen, at most.
  static const TextStyle displayLg = TextStyle(
    fontFamily: displayFamily,
    fontSize: 80,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: -1.6,
    color: AppColors.ink,
  );

  /// 64 / 700 / -1.2 — primary screen headline.
  static const TextStyle display = TextStyle(
    fontFamily: displayFamily,
    fontSize: 64,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: -1.2,
    color: AppColors.ink,
  );

  /// 48 / 600 / -0.8 — section title.
  static const TextStyle headingXl = TextStyle(
    fontFamily: displayFamily,
    fontSize: 48,
    fontWeight: FontWeight.w600,
    height: 1.14,
    letterSpacing: -0.8,
    color: AppColors.ink,
  );

  /// 40 / 600 / -0.4 — subsection title, dense-screen hero.
  static const TextStyle headingLg = TextStyle(
    fontFamily: displayFamily,
    fontSize: 40,
    fontWeight: FontWeight.w600,
    height: 1.14,
    letterSpacing: -0.4,
    color: AppColors.ink,
  );

  /// 24 / 600 — the ceiling for high-density screens (tables, forms).
  static const TextStyle heading = TextStyle(
    fontFamily: displayFamily,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: AppColors.ink,
  );

  /// 20 / 600 — card titles, dialog titles.
  static const TextStyle headingSm = TextStyle(
    fontFamily: displayFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.33,
    color: AppColors.ink,
  );

  // ---------------------------------------------------------------------
  // Text — Inter. Body and UI.
  // ---------------------------------------------------------------------

  /// 18 / 400 / 1.6 — hero subtext and lead paragraphs. Smoke by default.
  static const TextStyle subheading = TextStyle(
    fontFamily: textFamily,
    fontSize: 18,
    fontWeight: FontWeight.w400,
    height: 1.6,
    color: AppColors.smoke,
  );

  /// 18 / 600 — emphasized body.
  static const TextStyle subheadingStrong = TextStyle(
    fontFamily: textFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.6,
    color: AppColors.ink,
  );

  /// 16 / 400 / 1.5 — the default rhythm. Ink, because body reads first.
  static const TextStyle body = TextStyle(
    fontFamily: textFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.ink,
  );

  /// 16 / 500 — body with emphasis.
  static const TextStyle bodyStrong = TextStyle(
    fontFamily: textFamily,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.5,
    color: AppColors.ink,
  );

  /// 16 / 400 — secondary body copy.
  static const TextStyle bodyMuted = TextStyle(
    fontFamily: textFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.smoke,
  );

  /// 14 / 400 / 1.5 — captions and helper text.
  static const TextStyle caption = TextStyle(
    fontFamily: textFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.smoke,
  );

  /// 14 / 500 — metadata, labels, nav links, button text.
  static const TextStyle label = TextStyle(
    fontFamily: textFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.2,
    color: AppColors.ink,
  );

  /// 14 / 600 — filled button text.
  static const TextStyle labelStrong = TextStyle(
    fontFamily: textFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: AppColors.ink,
  );

  /// 14 / 500 — table column headers. Sentence case, not uppercase: this
  /// system leans on weight and color, never on letter-spaced small caps.
  static const TextStyle tableHeader = TextStyle(
    fontFamily: textFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.2,
    color: AppColors.smoke,
  );

  /// 14 / 400 / 1.2 — compact table cell. Tighter leading is the one place
  /// the 1.5 default is relaxed.
  static const TextStyle tableCell = TextStyle(
    fontFamily: textFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.2,
    color: AppColors.ink,
  );

  /// 12 / 500 — pill tags, eyebrow links, timeline bar labels.
  static const TextStyle pill = TextStyle(
    fontFamily: textFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.2,
    color: AppColors.ink,
  );

  /// 12 / 400 — the smallest supported size. Sidebar sub-labels only.
  static const TextStyle micro = TextStyle(
    fontFamily: textFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.33,
    color: AppColors.smoke,
  );

  // ---------------------------------------------------------------------
  // Responsive display sizing.
  //
  // The 64–80px scale is a desktop instrument. On a phone it becomes three
  // words per line, so display styles step down while keeping the weight and
  // negative tracking that make the system recognisable.
  // ---------------------------------------------------------------------

  static const double _compactBreakpoint = 600;
  static const double _mediumBreakpoint = 1024;

  /// Hero headline sized for [width]: 80 → 48 → 34.
  static TextStyle heroFor(double width) {
    if (width >= _mediumBreakpoint) return displayLg;
    if (width >= _compactBreakpoint) {
      return displayLg.copyWith(fontSize: 48, letterSpacing: -0.9, height: 1.05);
    }
    return displayLg.copyWith(fontSize: 34, letterSpacing: -0.6, height: 1.1);
  }

  /// Screen headline sized for [width]: 64 → 40 → 30.
  static TextStyle displayFor(double width) {
    if (width >= _mediumBreakpoint) return display;
    if (width >= _compactBreakpoint) {
      return display.copyWith(fontSize: 40, letterSpacing: -0.7, height: 1.08);
    }
    return display.copyWith(fontSize: 30, letterSpacing: -0.5, height: 1.15);
  }

  /// Section title sized for [width]: 48 → 34 → 26.
  static TextStyle headingXlFor(double width) {
    if (width >= _mediumBreakpoint) return headingXl;
    if (width >= _compactBreakpoint) {
      return headingXl.copyWith(fontSize: 34, letterSpacing: -0.5);
    }
    return headingXl.copyWith(fontSize: 26, letterSpacing: -0.3);
  }

  /// Dense-screen title sized for [width]: 40 → 30 → 24.
  static TextStyle headingLgFor(double width) {
    if (width >= _mediumBreakpoint) return headingLg;
    if (width >= _compactBreakpoint) {
      return headingLg.copyWith(fontSize: 30, letterSpacing: -0.3);
    }
    return headingLg.copyWith(fontSize: 24, letterSpacing: -0.2);
  }

  static TextTheme textTheme() {
    return const TextTheme(
      displayLarge: displayLg,
      displayMedium: display,
      displaySmall: headingXl,
      headlineLarge: headingLg,
      headlineMedium: heading,
      headlineSmall: headingSm,
      titleLarge: headingSm,
      titleMedium: subheadingStrong,
      titleSmall: labelStrong,
      bodyLarge: body,
      bodyMedium: body,
      bodySmall: caption,
      labelLarge: labelStrong,
      labelMedium: label,
      labelSmall: pill,
    );
  }

  // ---------------------------------------------------------------------
  // Legacy aliases — retained so pre-overhaul call sites keep compiling
  // while screens migrate. All resolve into the scale above.
  // ---------------------------------------------------------------------

  @Deprecated('Use AppTypography.displayFor(width) or display.')
  static TextStyle get heading1 => headingLg;
  @Deprecated('Use AppTypography.heading.')
  static TextStyle get heading2 => heading;
  @Deprecated('Use AppTypography.headingSm.')
  static TextStyle get heading3 => headingSm;
  @Deprecated('Use AppTypography.subheading.')
  static TextStyle get bodyLarge => subheading;
  @Deprecated('Use AppTypography.pill or micro.')
  static TextStyle get overline => pill.copyWith(color: AppColors.smoke);
}
