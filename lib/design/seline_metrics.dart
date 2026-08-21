/// Seline spacing — 4px base, compact density.
///
/// Note the two ends of this scale: UI internals are tight (4/8/12/16) while
/// section rhythm is generous (64/96). Compact controls, wide breathing room
/// between blocks — that contrast is what makes the layout read as editorial
/// rather than merely dense.
abstract final class SelSpace {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x10 = 40;
  static const double x12 = 48;
  static const double x16 = 64;
  static const double x20 = 80;

  /// Section rhythm — the editorial pacing value.
  static const double section = 96;

  /// Card padding — the reference value.
  static const double cardPad = 24;

  /// Default gap between inline elements.
  static const double gap = 8;
}

/// Seline radii.
///
/// Buttons and tags are fully round; cards are a restrained 10px. The
/// pill/card contrast is a deliberate part of the language — do not round
/// cards further to "match" the buttons.
abstract final class SelRadius {
  /// Icons, small decorative chips, highlight-span backgrounds.
  static const double icon = 4;

  /// Inputs and form fields.
  static const double input = 6;

  /// Cards, panels, list containers.
  static const double card = 10;

  /// Hero/feature surfaces only.
  static const double feature = 16;

  /// Buttons, tags, avatars — fully round.
  static const double pill = 9999;
}

/// Seline layout constraints.
abstract final class SelLayout {
  /// Page max-width.
  static const double maxWidth = 1200;

  /// Reading measure for prose and hero subtext.
  static const double prose = 640;

  /// Form column width.
  static const double form = 560;

  /// Width of the bare nav rail. It has no fill or border — this is just the
  /// column the links occupy.
  static const double railWidth = 200;

  static const double compact = 600;
  static const double medium = 1024;

  static bool isCompact(double w) => w < compact;
  static bool isExpanded(double w) => w >= medium;

  /// Section gap: the full 96px on desktop, tightened on small screens.
  static double sectionGap(double w) => isExpanded(w) ? 96 : 64;

  /// Card padding: 24px, relaxing to 16px on phones.
  static double cardPadding(double w) => isCompact(w) ? 16 : 24;
}
