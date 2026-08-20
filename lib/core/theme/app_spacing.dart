/// Hellotime spacing — 8px base unit, comfortable density.
///
/// The system breathes: 64–80px between sections, 32px inside cards, 16–24px
/// between elements. Values below 8px exist only for inline icon gaps.
abstract final class AppSpacing {
  /// Inline icon/text gap. The only sub-8 value in the system.
  static const double xs = 4;

  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;

  /// Card padding — the reference value.
  static const double xl = 32;

  static const double xxl = 40;
  static const double xxxl = 48;

  /// Section rhythm — the minimum gap between stacked sections.
  static const double section = 64;

  /// Section rhythm — generous variant for low-density editorial screens.
  static const double sectionLg = 80;

  /// Hero top padding on marketing-weight surfaces.
  static const double hero = 120;
}

/// Hellotime radii.
///
/// 16px is the ceiling. Nothing in this system is rounder than a card, and
/// nothing that accepts input is rounder than 12px.
abstract final class AppRadius {
  /// Timeline / progress bars.
  static const double bar = 4;

  /// Buttons, nav elements, small controls.
  static const double button = 8;

  /// Alias of [button] for non-button chrome at the same radius.
  static const double sm = 8;

  /// Inputs and form fields.
  static const double input = 12;

  /// Alias of [input].
  static const double md = 12;

  /// Cards, panels, image frames — the ceiling.
  static const double card = 16;

  /// Alias of [card].
  static const double lg = 16;

  /// Pills, tags, avatars.
  static const double full = 9999;

  @Deprecated('Use AppRadius.bar.')
  static const double xs = bar;
  @Deprecated('Use AppRadius.card — 16px is the ceiling.')
  static const double xl = card;
}

/// Hairline border widths. This system has exactly one.
abstract final class AppBorders {
  static const double hairline = 1;
}
