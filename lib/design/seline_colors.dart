import 'package:flutter/material.dart';

/// Relief — navy and sky on a near-white page (the canvas design).
///
/// The names stay Seline's so every screen picks up the new values at once.
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
  static const Color canvas = Color(0xFFFEFEFD);

  /// The sidebar: a faint baby blue, so navigation reads apart from the page.
  static const Color rail = Color(0xFFF3F8FD);

  /// The sidebar's edge and its quiet dividers.
  static const Color railEdge = Color(0xFFE2EDF8);

  /// The selected sidebar item.
  static const Color railSelected = Color(0xFFD9EBFC);

  /// Hovered sidebar item.
  static const Color railHover = Color(0xFFE7F1FB);

  /// Light grey for tab tracks, pill fills and quiet chips.
  static const Color track = Color(0xFFF1F5F9);

  /// Card surfaces, nav fills, input fills. One elevation step above canvas.
  static const Color card = Color(0xFFFFFFFF);

  /// The primary structural device — hairline borders on cards and inputs.
  static const Color border = Color(0xFFE3E8EE);

  /// Secondary borders, subtle tints, decorative separators.
  static const Color borderMuted = Color(0xFFD0D5DD);

  /// Disabled and decorative strokes only. About 2.4:1 on [canvas] — too
  /// light for captions, chevrons, or any text a person must read. Those
  /// use [warm] (~4.6:1).
  static const Color ash = Color(0xFF9AA6B8);

  /// Body text, nav links, secondary copy. Warm neutral that softens body type.
  static const Color warm = Color(0xFF616C8A);

  /// Primary headings, emphasised body, strong icons.
  static const Color ink = Color(0xFF13426F);

  /// Running text: near-black, softer than navy for long reading.
  static const Color text = Color(0xFF333333);

  /// Inverted surfaces — active tab pills, dark panels. Used sparingly.
  static const Color soot = Color(0xFF13426F);

  // -------------------------------------------------------------------
  // The single chromatic voice.
  // -------------------------------------------------------------------

  /// Primary CTA fill, active links, brand strokes. The only filled colour.
  static const Color cyan = Color(0xFF0F6FD6);

  /// The brand sky: the logo's capital, highlights, the loader.
  static const Color sky = Color(0xFF2E96FF);

  /// Outlined action borders, linked labels, lightweight emphasis.
  /// Never promote this to a primary CTA fill.
  static const Color cyanEdge = Color(0xFF0254A5);

  /// Soft wash behind highlighted text spans. Pairs with [cyanEdge] text.
  static const Color skyWash = Color(0xFFBDE1F9);

  /// Faint sky fill for selected rows, chosen options and icon tiles.
  static const Color skyTint = Color(0xFFEEF6FE);

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
  static const Color success = Color(0xFF1D6B43);

  /// Waiting, in progress, needs a decision. Ochre.
  static const Color warning = Color(0xFFB8862B);

  /// Failed, blocked, rejected. Clay.
  static const Color danger = Color(0xFFA8453A);

  /// Neutral information. Reuses the brand cyan edge.
  static const Color info = cyanEdge;

  /// Chip and banner backgrounds for the four states above. Low-chroma so a
  /// column of them stays calm; the text and icon carry the signal.
  static const Color successWash = Color(0xFFE4F4EA);
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
    BoxShadow(color: Color(0x0A000000), offset: Offset(0, 3)),
  ];

  /// Nav strips and buttons — barely there.
  static const List<BoxShadow> hairline = [
    BoxShadow(color: Color(0x0A000000), offset: Offset(0, 2)),
  ];

  /// Small chips and decorative icons.
  static const List<BoxShadow> chip = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 4), spreadRadius: -1),
    BoxShadow(color: Color(0x1A000000), blurRadius: 4, offset: Offset(0, 2), spreadRadius: -2),
  ];

  /// The one deep shadow in the system. Hero surfaces only — at most one per
  /// screen, and never on a list row or an ordinary card.
  static const List<BoxShadow> floating = [
    BoxShadow(color: Color(0x40000000), blurRadius: 30, offset: Offset(0, 12), spreadRadius: -10),
  ];

  /// The primary button's flat light-sky block underneath.
  static const List<BoxShadow> pop = [
    BoxShadow(color: Color(0x809ACFF6), offset: Offset(0, 6)),
  ];
}
