/// Max-width and layout constraints for shell + key flows (aligned with UI refresh plan).
abstract final class PillrLayout {
  static const double contentMaxWidth = 1200;
  static const double formMaxWidth = 560;
  static const double bulkImportMaxWidth = 960;

  /// Below this width, list screens prefer card rows over [PillrDataTable].
  static const double cardListBreakpoint = 900;

  static bool useCardListLayout(double width) => width < cardListBreakpoint;
}
