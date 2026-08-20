/// Hellotime layout constraints.
///
/// Everything stacks and breathes on a 1200px canvas. No sidebars in the
/// content column, no multi-column text, no overlapping elements.
abstract final class PillrLayout {
  /// Page max-width — the reference canvas.
  static const double contentMaxWidth = 1200;

  /// Centered measure for forms and single-field flows.
  static const double formMaxWidth = 560;

  /// Hero subtext measure. Long lines break the editorial rhythm.
  static const double proseMaxWidth = 640;

  static const double bulkImportMaxWidth = 960;

  /// Below this width, list screens prefer card rows over [PillrDataTable].
  static const double cardListBreakpoint = 900;

  /// Below this width, display type steps down and the shell goes bottom-nav.
  static const double compactBreakpoint = 600;

  /// At or above this width, the full 64–80px display scale is in play.
  static const double expandedBreakpoint = 1024;

  static bool useCardListLayout(double width) => width < cardListBreakpoint;

  static bool isCompact(double width) => width < compactBreakpoint;

  static bool isExpanded(double width) => width >= expandedBreakpoint;

  /// Section gap for the given width: 80px on desktop, 64px otherwise.
  static double sectionGap(double width) => isExpanded(width) ? 80 : 64;

  /// Card padding for the given width: 32px, relaxing to 24px on phones.
  static double cardPadding(double width) => isCompact(width) ? 24 : 32;
}
