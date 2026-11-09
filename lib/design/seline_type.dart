import 'package:flutter/material.dart';

import 'seline_colors.dart';

/// Seline type.
///
/// Two families, bundled locally:
///
/// * [display] — Inter Tight, standing in for Roobert. Used at **weight 400**
///   at every size, including 52px. That is the signature of this system: an
///   anti-convention whisper-weight that gets its authority from size and
///   negative tracking rather than from boldness. Never reach for 600/700 to
///   emphasise a heading — go bigger, or use the highlight span.
/// * [text] — Inter. Everything else. 14px / weight 400 / 1.64 line-height is
///   the dominant rhythm of the entire UI; do not break it without reason.
abstract final class SelType {
  static const String display = 'Manrope';
  static const String text = 'Manrope';

  // -------------------------------------------------------------------
  // Display — Inter Tight, weight 400, tight negative tracking.
  // -------------------------------------------------------------------

  /// 52 / 400 / -1.09 — the hero. One per screen.
  static const TextStyle hero = TextStyle(
    fontFamily: display,
    fontSize: 40,
    fontWeight: FontWeight.w800,
    height: 1.15,
    letterSpacing: -1.4,
    color: Sel.ink,
  );

  /// 32 / 400 / -0.8 — screen and section titles.
  static const TextStyle title = TextStyle(
    fontFamily: display,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.29,
    letterSpacing: -0.96,
    color: Sel.ink,
  );

  /// 20 / 400 / -0.1 — card titles, subsection heads, big list values.
  static const TextStyle subtitle = TextStyle(
    fontFamily: display,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: -0.4,
    color: Sel.ink,
  );

  /// 18 / 400 / -0.017em — the smallest display size. Dialog titles.
  static const TextStyle subtitleSm = TextStyle(
    fontFamily: display,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: -0.3,
    color: Sel.ink,
  );

  // -------------------------------------------------------------------
  // Text — Inter. The 14/400/1.64 rhythm dominates.
  // -------------------------------------------------------------------

  /// 16 / 400 / 1.69 — lead paragraphs and hero subtext. Warm gray.
  static const TextStyle lead = TextStyle(
    fontFamily: text,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.55,
    letterSpacing: -0.29,
    color: Sel.warm,
  );

  /// **14 / 400 / 1.64 — the dominant body size.** Ink.
  static const TextStyle body = TextStyle(
    fontFamily: text,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.55,
    letterSpacing: -0.27,
    color: Sel.text,
  );

  /// 14 / 400 — secondary copy, metadata, nav links at rest.
  static const TextStyle bodyMuted = TextStyle(
    fontFamily: text,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.55,
    letterSpacing: -0.27,
    color: Sel.warm,
  );

  /// 14 / 500 — emphasised body, active nav, names in a list.
  static const TextStyle bodyMedium = TextStyle(
    fontFamily: text,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.5,
    letterSpacing: -0.27,
    color: Sel.ink,
  );

  /// 14 / 500 — button labels. Tighter leading than body.
  static const TextStyle button = TextStyle(
    fontFamily: text,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.2,
    color: Sel.ink,
  );

  /// 13 / 400 — compact rows where 14 will not fit.
  static const TextStyle bodySm = TextStyle(
    fontFamily: text,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.5,
    letterSpacing: -0.2,
    color: Sel.warm,
  );

  /// 12 / 400 — helper text, timestamps, footnotes.
  static const TextStyle small = TextStyle(
    fontFamily: text,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.4,
    letterSpacing: -0.2,
    color: Sel.warm,
  );

  /// 12 / 500 — tag and chip labels.
  static const TextStyle tag = TextStyle(
    fontFamily: text,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.33,
    letterSpacing: 0,
    color: Sel.ink,
  );

  /// 10 / 500 / +0.025em, uppercase — the *one* place letterspaced caps are
  /// correct in this system: the quiet caption row above a ledger, standing in
  /// for a table header band.
  static const TextStyle caption = TextStyle(
    fontFamily: text,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.6,
    letterSpacing: 0,
    color: Sel.warm,
  );

  // -------------------------------------------------------------------
  // Responsive display sizing.
  //
  // 52px is a desktop instrument. Step it down rather than letting a hero
  // headline become four words per line on a phone.
  // -------------------------------------------------------------------

  static TextStyle heroFor(double w) {
    if (w >= 1024) return hero;
    if (w >= 600) return hero.copyWith(fontSize: 34, letterSpacing: -1.1, height: 1.15);
    return hero.copyWith(fontSize: 28, letterSpacing: -0.8, height: 1.18);
  }

  static TextStyle titleFor(double w) {
    if (w >= 1024) return title;
    if (w >= 600) return title.copyWith(fontSize: 26, letterSpacing: -0.6);
    return title.copyWith(fontSize: 22, letterSpacing: -0.4);
  }

  static TextTheme textTheme() => const TextTheme(
        displayLarge: hero,
        displayMedium: title,
        displaySmall: subtitle,
        headlineLarge: title,
        headlineMedium: subtitle,
        headlineSmall: subtitleSm,
        titleLarge: subtitle,
        titleMedium: subtitleSm,
        titleSmall: bodyMedium,
        bodyLarge: lead,
        bodyMedium: body,
        bodySmall: small,
        labelLarge: button,
        labelMedium: bodyMedium,
        labelSmall: caption,
      );
}
