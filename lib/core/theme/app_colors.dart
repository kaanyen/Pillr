import 'package:flutter/material.dart';

/// Hellotime — monochrome editorial command center.
///
/// Near-monochrome surface: white canvas, near-black type, and one electric
/// blue gradient reserved exclusively for inline keyword highlights inside
/// headlines. Hierarchy comes from type weight and hairline borders, never
/// from color or elevation.
///
/// Rules this palette encodes:
/// * Blue is a *text gradient only* — never a fill, never a surface.
/// * Charcoal is the only dark surface, reserved for primary actions.
/// * State is communicated by fill / border / weight, not by hue.
/// * Signal Green is an identity mark only (logo, tenant avatar).
abstract final class AppColors {
  // ---------------------------------------------------------------------
  // Core scale — Ink is the dominant non-background color in the system.
  // ---------------------------------------------------------------------

  /// Primary text, icon strokes, strong hairlines.
  static const Color ink = Color(0xFF151619);

  /// Secondary / muted text, links, placeholders. Recedes so body reads first.
  static const Color smoke = Color(0xFF7F8491);

  /// The default hairline — card borders, dividers, icon outlines at rest.
  static const Color fog = Color(0xFFC8CAD0);

  /// Section dividers, secondary surface tint, resting input borders.
  static const Color ash = Color(0xFFE1E2E5);

  /// Card surfaces, hover wash, input backgrounds, active nav rows.
  static const Color mist = Color(0xFFF3F3F5);

  /// Page canvas, nav background, inverted button text.
  static const Color paper = Color(0xFFFFFFFF);

  /// The only dark surface — primary action fill, inverse CTA blocks.
  static const Color charcoal = Color(0xFF25272D);

  /// Nav link text, lifted slightly from [ink] for a softer navigation feel.
  static const Color graphite = Color(0xFF363940);

  /// Outlined button border at rest, ghost control stroke.
  static const Color pewter = Color(0xFFB0B3BB);

  // ---------------------------------------------------------------------
  // Accents — the only chromatic elements in the system.
  // ---------------------------------------------------------------------

  /// Brand identity marker. Logo mark and tenant identity only — never state.
  static const Color signalGreen = Color(0xFF059669);

  /// Gradient stops for [electricBlue]. Not for direct use as a fill.
  static const Color electricBlueStart = Color(0xFF0560FD);
  static const Color electricBlueMid = Color(0xFF3A8DFF);
  static const Color electricBlueEnd = Color(0xFFC3D9FF);

  /// The single gradient in the system. Applied to inline keyword phrases
  /// inside headlines via [ShaderMask] — never to a background or a button.
  /// Runs left-to-right so the bright end follows reading direction.
  static const LinearGradient electricBlue = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [electricBlueStart, electricBlueMid, electricBlueEnd],
    stops: [0.0, 0.5, 1.0],
  );

  // ---------------------------------------------------------------------
  // Surface levels (see the style reference "Surfaces" table).
  // ---------------------------------------------------------------------

  /// Level 0 — the base layer everything sits on.
  static const Color surface0 = paper;

  /// Level 1 — card surfaces, sidebar rows, hovered/active wash.
  static const Color surface1 = mist;

  /// Level 2 — section dividers, resting input fields.
  static const Color surface2 = ash;

  /// Level 3 — inverse surface for primary actions and footer CTA blocks.
  static const Color surface3 = charcoal;

  // ---------------------------------------------------------------------
  // Product-UI accents.
  //
  // Per the style reference, saturated color survives in exactly one place:
  // timeline / progress bars inside product surfaces. These are the sanctioned
  // hues. Never use them for text, status, or chrome.
  // ---------------------------------------------------------------------

  static const List<Color> timelineBars = <Color>[
    Color(0xFF0560FD), // blue
    Color(0xFF059669), // green
    Color(0xFFF59E0B), // orange
    Color(0xFFE11D48), // magenta
    Color(0xFF14B8A6), // teal
  ];

  /// Deterministic bar color for a series index (arms, projects, categories).
  static Color timelineBar(int index) =>
      timelineBars[index.abs() % timelineBars.length];

  // ---------------------------------------------------------------------
  // Legacy aliases.
  //
  // Retained so the pre-overhaul call sites keep compiling while screens are
  // migrated to the tokens above. Every one of these resolves into the
  // monochrome system — no legacy hue survives.
  // ---------------------------------------------------------------------

  @Deprecated('Use AppColors.charcoal (filled action) or ink (text).')
  static const Color primaryColor = charcoal;
  @Deprecated('Use AppColors.mist.')
  static const Color primaryLight = mist;
  @Deprecated('Use AppColors.ink.')
  static const Color primaryDark = ink;
  @Deprecated('Use AppColors.ink.')
  static const Color onAccent = ink;

  @Deprecated('State is monochrome — use PillrStatusStyle.')
  static const Color successColor = ink;
  @Deprecated('State is monochrome — use PillrStatusStyle.')
  static const Color successLight = mist;
  @Deprecated('State is monochrome — use PillrStatusStyle.')
  static const Color warningColor = smoke;
  @Deprecated('State is monochrome — use PillrStatusStyle.')
  static const Color warningLight = mist;
  @Deprecated('State is monochrome — use PillrStatusStyle.')
  static const Color dangerColor = ink;
  @Deprecated('State is monochrome — use PillrStatusStyle.')
  static const Color dangerLight = mist;
  @Deprecated('State is monochrome — use PillrStatusStyle.')
  static const Color infoColor = smoke;

  @Deprecated('Use AppColors.mist.')
  static const Color gray50 = mist;
  @Deprecated('Use AppColors.mist.')
  static const Color gray100 = mist;
  @Deprecated('Use AppColors.ash.')
  static const Color gray200 = ash;
  @Deprecated('Use AppColors.pewter.')
  static const Color gray400 = pewter;
  @Deprecated('Use AppColors.smoke.')
  static const Color gray600 = smoke;
  @Deprecated('Use AppColors.smoke.')
  static const Color textSecondary = smoke;
  @Deprecated('Use AppColors.ink.')
  static const Color gray900 = ink;

  @Deprecated('Use AppColors.paper.')
  static const Color white = paper;
  @Deprecated('Use AppColors.paper — the canvas is pure white.')
  static const Color surfaceColor = paper;

  @Deprecated('Use AppColors.mist.')
  static const Color navActiveBackground = mist;
  @Deprecated('Use AppColors.ink.')
  static const Color navActiveForeground = ink;

  @Deprecated('Use AppColors.timelineBar(index).')
  static const Color progressTeal = Color(0xFF14B8A6);
  @Deprecated('Use AppColors.timelineBar(index).')
  static const Color progressOrange = Color(0xFFF59E0B);
  @Deprecated('Use AppColors.timelineBar(index).')
  static const Color progressRed = Color(0xFFE11D48);
}
