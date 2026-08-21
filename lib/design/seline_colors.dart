import 'package:flutter/material.dart';

/// Seline — quiet analyst's desk on warm paper.
///
/// The whole palette is the Tailwind stone scale plus exactly one cyan. That
/// restraint is the design: because nothing else is chromatic, the cyan CTA
/// reads as "switched on" without needing size or weight to shout.
///
/// Two rules that are easy to break and expensive to fix:
/// * The page is [canvas] (warm), cards are [card] (pure white). Never invert.
/// * Cyan is for **actions and links only**. State never gets colour.
abstract final class Sel {
  // -------------------------------------------------------------------
  // Neutrals — warm-tinted, from stone.
  // -------------------------------------------------------------------

  /// Page background. Warm off-white that reads as paper, not screen-white.
  static const Color canvas = Color(0xFFFAFAF9);

  /// Card surfaces, nav fills, input fills. One elevation step above canvas.
  static const Color card = Color(0xFFFFFFFF);

  /// The primary structural device — hairline borders on cards and inputs.
  static const Color border = Color(0xFFE8E6E5);

  /// Secondary borders, subtle tints, decorative separators.
  static const Color borderMuted = Color(0xFFD6D3D1);

  /// Muted helper text, icon strokes, disabled states. Recessive but readable.
  static const Color ash = Color(0xFFA8A29E);

  /// Body text, nav links, secondary copy. Warm neutral that softens body type.
  static const Color warm = Color(0xFF78716C);

  /// Primary headings, emphasised body, strong icons.
  static const Color ink = Color(0xFF0C0A09);

  /// Inverted surfaces — active tab pills, dark panels. Used sparingly.
  static const Color soot = Color(0xFF1C1917);

  // -------------------------------------------------------------------
  // The single chromatic voice.
  // -------------------------------------------------------------------

  /// Primary CTA fill, active links, brand strokes. The only filled colour.
  static const Color cyan = Color(0xFF3BA6F1);

  /// Outlined action borders, linked labels, lightweight emphasis.
  /// Never promote this to a primary CTA fill.
  static const Color cyanEdge = Color(0xFF3398E1);

  /// Soft wash behind highlighted text spans. Pairs with [cyanEdge] text.
  static const Color skyWash = Color(0xFFC1E1F7);

  // -------------------------------------------------------------------
  // Surface levels.
  // -------------------------------------------------------------------

  /// Level 0 — the warm page.
  static const Color surface0 = canvas;

  /// Level 1 — flat white cards.
  static const Color surface1 = card;

  /// Level 3 — inverted panels and active pills.
  static const Color surface3 = soot;
}

/// Seline elevation.
///
/// Unusually for a flat-looking system, shadows *are* used here — but softly,
/// and with a strict hierarchy. [card] is the everyday lift; [floating] is
/// reserved for one element per screen at most.
abstract final class SelShadow {
  /// Content cards. Soft 16px blur at 5% — lift without weight.
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x0D000000),
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ];

  /// Nav strips and buttons — barely there.
  static const List<BoxShadow> hairline = [
    BoxShadow(
      color: Color(0x0D000000),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  /// Small chips and decorative icons.
  static const List<BoxShadow> chip = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 4), spreadRadius: -1),
    BoxShadow(color: Color(0x1A000000), blurRadius: 4, offset: Offset(0, 2), spreadRadius: -2),
  ];

  /// The one deep shadow in the system. Hero surfaces only — at most one per
  /// screen, and never on a list row or an ordinary card.
  static const List<BoxShadow> floating = [
    BoxShadow(
      color: Color(0x1F110C2E),
      blurRadius: 45,
      offset: Offset(0, 12),
    ),
  ];
}
