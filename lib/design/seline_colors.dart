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
  // Semantic state.
  //
  // Seline's own reference spends its whole chromatic budget on one cyan, and
  // that holds for an analytics marketing page. It does not hold for a product
  // whose core loop is approve / send back / blocked: a row the user must fix
  // has to be distinguishable from one they need not look at.
  //
  // So state gets colour — but warm, desaturated tones drawn toward the stone
  // base rather than off-the-shelf semantic hues. They read as considered
  // beside #fafaf9, and none of them is a *fill* for an action, so the cyan
  // button is still the loudest thing on any screen.
  // -------------------------------------------------------------------

  /// Settled, correct, complete. Moss.
  static const Color success = Color(0xFF4D7C5F);

  /// Waiting, in progress, needs a decision. Ochre.
  static const Color warning = Color(0xFFB8862B);

  /// Failed, blocked, rejected. Clay.
  static const Color danger = Color(0xFFA8453A);

  /// Neutral information. Reuses the brand cyan edge.
  static const Color info = cyanEdge;

  /// Chip and banner backgrounds for the four states above. Low-chroma so a
  /// column of them stays calm; the text and icon carry the signal.
  static const Color successWash = Color(0xFFE8F0EA);
  static const Color warningWash = Color(0xFFF7EFDC);
  static const Color dangerWash = Color(0xFFF5E6E3);
  static const Color infoWash = skyWash;

  // -------------------------------------------------------------------
  // Categorical — partnership arms.
  //
  // Arms are the one genuinely categorical dimension in the product: a church
  // has a handful, they are stable, and they appear across ledgers, goals and
  // charts. A stable colour per arm makes Missions and Media separable at a
  // glance without reading.
  //
  // Same warm, desaturated register as the state colours, chosen to stay
  // distinguishable from one another and from the semantic set.
  // -------------------------------------------------------------------

  static const List<Color> armPalette = <Color>[
    Color(0xFF4C5C8A), // indigo
    Color(0xFF4D7C5F), // moss
    Color(0xFF9C5F3C), // rust
    Color(0xFF7D4F6D), // plum
    Color(0xFF3F7D80), // teal
    Color(0xFFB8862B), // ochre
    Color(0xFF6B7F5C), // sage
    Color(0xFF8A5A4C), // umber
  ];

  /// Stable colour for an arm.
  ///
  /// Prefers the arm's own stored `colorHex` when a church has set one;
  /// otherwise derives an index from the id so the same arm always lands on
  /// the same swatch, on every screen and every device, without needing a
  /// migration to assign colours.
  static Color armColor(String armId, {Color? stored}) {
    if (stored != null) return stored;
    if (armId.isEmpty) return armPalette.first;
    var h = 0;
    for (final unit in armId.codeUnits) {
      h = (h * 31 + unit) & 0x7FFFFFFF;
    }
    return armPalette[h % armPalette.length];
  }

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
