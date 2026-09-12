import 'package:flutter/material.dart';

import '../seline_colors.dart';
import '../seline_metrics.dart';
import '../seline_type.dart';

/// How a ledger column sizes itself.
enum SelColFit {
  /// Takes a share of the leftover width. [SelColumn.flex] sets the share.
  flex,

  /// Fixed pixel width. Use for amounts, dates and status so they align down
  /// the page regardless of how long the names are.
  fixed,
}

@immutable
class SelColumn {
  const SelColumn(
    this.label, {
    this.fit = SelColFit.flex,
    this.flex = 1,
    this.width = 120,
    this.align = TextAlign.left,
  });

  /// Fixed-width column, right-aligned — the money/date shape.
  const SelColumn.numeric(this.label, {this.width = 120})
    : fit = SelColFit.fixed,
      flex = 1,
      align = TextAlign.right;

  /// Caption text. Rendered small, uppercase and letterspaced — the one place
  /// in this system where caps are correct.
  final String label;

  final SelColFit fit;
  final int flex;
  final double width;
  final TextAlign align;
}

/// A ledger row's cells, plus optional per-row behaviour.
@immutable
class SelRow {
  const SelRow({
    required this.cells,
    this.onTap,
    this.selected = false,
    this.leading,
    this.cursor = false,
  });

  final List<Widget> cells;
  final VoidCallback? onTap;
  final bool selected;

  /// The row the keyboard is on. Distinct from [selected], which is a choice
  /// the user has made: this only says where the next keystroke will land, so
  /// it is drawn as an edge rather than a fill.
  final bool cursor;

  /// Optional leading widget (checkbox, avatar) rendered before the first cell.
  final Widget? leading;
}

/// Fixed row height for virtualized ledgers (padding + one line of body text).
const double kSelLedgerRowExtent = 46;

/// Row height for virtualized ledgers whose rows carry a [SelCell.stacked]
/// two-line cell. At [kSelLedgerRowExtent] the second line has 22px of a ~39px
/// need: it overflowed by 17px and was clipped away in release builds.
const double kSelLedgerStackedRowExtent = 64;

/// The ledger — Seline's answer to a data table.
///
/// One white card holds the whole list. A quiet 10px caption row stands in for
/// a header band, then rows at the system's native 14/1.64 rhythm separated by
/// stone hairlines. Columns stay aligned so amounts remain comparable down the
/// page, but there is no grid chrome, no zebra striping, no header fill and no
/// per-row borders. The card's own hairline is the only enclosure.
///
/// It scrolls horizontally below [minWidth] rather than crushing columns.
class SelLedger extends StatelessWidget {
  const SelLedger({
    super.key,
    required this.columns,
    required this.rows,
    this.minWidth = 640,
    this.showCaptions = true,
    this.emptyState,
    this.virtualized = false,
    this.maxVirtualHeight = 520,
    this.rowExtent = kSelLedgerRowExtent,
    this.scrollController,
  })  : itemBuilder = null,
        _itemCount = null,
        _explicitHasLeading = null;

  /// Rows built on demand rather than handed over as a finished list.
  ///
  /// [SelLedger.new] takes `List<SelRow>`, so every row's widgets are
  /// constructed before the ledger sees them — `virtualized: true` then only
  /// saves layout and paint, not construction. On a 450-partner directory that
  /// is thousands of widgets per rebuild. This constructor defers row
  /// construction to the viewport, which is what makes the saving real.
  ///
  /// Always virtualized, so the list scrolls inside the card at up to
  /// [maxVirtualHeight]. [hasLeading] must be stated up front: with no row list
  /// to scan, the ledger cannot discover a leading column on its own.
  const SelLedger.builder({
    super.key,
    required this.columns,
    required int itemCount,
    required SelRow Function(BuildContext, int) this.itemBuilder,
    bool hasLeading = false,
    this.minWidth = 640,
    this.showCaptions = true,
    this.emptyState,
    this.maxVirtualHeight = 520,
    this.rowExtent = kSelLedgerRowExtent,
    this.scrollController,
  })  : rows = const [],
        virtualized = true,
        _itemCount = itemCount,
        _explicitHasLeading = hasLeading;

  final List<SelColumn> columns;

  /// The finished rows. Empty in [SelLedger.builder] — use [_rowAt] instead of
  /// reading this directly.
  final List<SelRow> rows;
  final double minWidth;

  /// Hide the caption row for short embedded lists where it is noise.
  final bool showCaptions;

  /// Shown in place of rows when there are no rows.
  final Widget? emptyState;

  /// Build rows with [ListView.builder] instead of materializing every row.
  /// Always true for [SelLedger.builder].
  final bool virtualized;

  /// Cap height when [virtualized] — the list scrolls inside the card.
  final double maxVirtualHeight;

  /// Height of each row when [virtualized]. Every row is laid out at exactly
  /// this height, so a ledger with two-line cells must pass
  /// [kSelLedgerStackedRowExtent] or its second lines are clipped.
  final double rowExtent;

  /// Optional scroll controller for the virtualized list body.
  final ScrollController? scrollController;

  /// Set by [SelLedger.builder]; null when rows were passed as a list.
  final SelRow Function(BuildContext, int)? itemBuilder;

  final int? _itemCount;
  final bool? _explicitHasLeading;

  int get _rowCount => _itemCount ?? rows.length;

  SelRow _rowAt(BuildContext context, int i) =>
      itemBuilder?.call(context, i) ?? rows[i];

  @override
  Widget build(BuildContext context) {
    if (_rowCount == 0 && emptyState != null) {
      return Container(
        decoration: BoxDecoration(
          color: Sel.card,
          borderRadius: BorderRadius.circular(SelRadius.card),
          border: Border.all(color: Sel.border),
          boxShadow: SelShadow.card,
        ),
        padding: const EdgeInsets.symmetric(vertical: SelSpace.x16),
        child: emptyState,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Sel.card,
        borderRadius: BorderRadius.circular(SelRadius.card),
        border: Border.all(color: Sel.border),
        boxShadow: SelShadow.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, c) {
          final needsScroll = c.maxWidth < minWidth;
          final body = virtualized && _rowCount > 0
              ? _virtualizedBody(context, needsScroll)
              : _staticBody(context, needsScroll);

          if (!needsScroll) return body;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: body,
          );
        },
      ),
    );
  }

  Widget _staticBody(BuildContext context, bool needsScroll) {
    return SizedBox(
      width: needsScroll ? minWidth : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showCaptions) ...[
            _CaptionRow(columns: columns, hasLeading: _hasLeading),
            const Divider(height: 1, color: Sel.border),
          ],
          for (var i = 0; i < _rowCount; i++) ...[
            _LedgerRow(
              row: _rowAt(context, i),
              columns: columns,
              hasLeading: _hasLeading,
            ),
            if (i != _rowCount - 1)
              const Divider(height: 1, color: Sel.border),
          ],
        ],
      ),
    );
  }

  Widget _virtualizedBody(BuildContext context, bool needsScroll) {
    const captionBlock = 36.0;
    final listHeight = (_rowCount * rowExtent)
        .clamp(rowExtent, maxVirtualHeight);
    final totalHeight = (showCaptions ? captionBlock + 1 : 0) + listHeight;

    return SizedBox(
      width: needsScroll ? minWidth : null,
      height: totalHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showCaptions) ...[
            _CaptionRow(columns: columns, hasLeading: _hasLeading),
            const Divider(height: 1, color: Sel.border),
          ],
          Expanded(
            child: ListView.separated(
              controller: scrollController,
              itemCount: _rowCount,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: Sel.border),
              itemBuilder: (context, i) => SizedBox(
                height: rowExtent,
                child: _LedgerRow(
                  row: _rowAt(context, i),
                  columns: columns,
                  hasLeading: _hasLeading,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _hasLeading =>
      _explicitHasLeading ?? rows.any((r) => r.leading != null);
}

const double _leadingWidth = 36;

class _CaptionRow extends StatelessWidget {
  const _CaptionRow({required this.columns, required this.hasLeading});

  final List<SelColumn> columns;
  final bool hasLeading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SelSpace.x6),
      child: Row(
        children: [
          if (hasLeading) const SizedBox(width: _leadingWidth),
          for (final c in columns)
            _cell(
              c,
              Text(
                c.label.toUpperCase(),
                style: SelType.caption,
                textAlign: c.align,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(SelColumn c, Widget child) {
    final padded = Padding(
      padding: const EdgeInsets.only(right: SelSpace.x4),
      child: Align(
        alignment: c.align == TextAlign.right
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: child,
      ),
    );
    return c.fit == SelColFit.fixed
        ? SizedBox(width: c.width, child: padded)
        : Expanded(flex: c.flex, child: padded);
  }
}

class _LedgerRow extends StatefulWidget {
  const _LedgerRow({
    required this.row,
    required this.columns,
    required this.hasLeading,
  });

  final SelRow row;
  final List<SelColumn> columns;
  final bool hasLeading;

  @override
  State<_LedgerRow> createState() => _LedgerRowState();
}

class _LedgerRowState extends State<_LedgerRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    // Hover and selection both wash to canvas — the row lifts off the white
    // card by warming, not by tinting.
    final bg = r.selected || _hover ? Sel.canvas : Sel.card;

    final body = AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          left: BorderSide(
            color: r.cursor ? Sel.cyanEdge : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      padding: const EdgeInsets.only(
        left: SelSpace.x6 - 2,
        right: SelSpace.x6,
        top: SelSpace.x3,
        bottom: SelSpace.x3,
      ),
      child: Row(
        children: [
          if (widget.hasLeading)
            SizedBox(
              width: _leadingWidth,
              child: Align(alignment: Alignment.centerLeft, child: r.leading),
            ),
          for (var i = 0; i < widget.columns.length; i++)
            _cell(
              widget.columns[i],
              i < r.cells.length ? r.cells[i] : const SizedBox.shrink(),
            ),
        ],
      ),
    );

    // Cells are separate widgets but one fact: a screen reader should say
    // "Yaw Darko, Missions, GHS 300, pending" as a single row, not spell it
    // out a column at a time.
    if (r.onTap == null) return MergeSemantics(child: body);

    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: r.selected,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(onTap: r.onTap, child: body),
        ),
      ),
    );
  }

  Widget _cell(SelColumn c, Widget child) {
    final padded = Padding(
      padding: const EdgeInsets.only(right: SelSpace.x4),
      child: Align(
        alignment: c.align == TextAlign.right
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: child,
      ),
    );
    return c.fit == SelColFit.fixed
        ? SizedBox(width: c.width, child: padded)
        : Expanded(flex: c.flex, child: padded);
  }
}

/// Meaning of a figure, for [SelCell.numeric].
enum SelTone {
  /// Counted toward totals.
  positive,

  /// Rejected, reversed, or excluded from totals.
  negative,

  /// No direction — counts, targets, dates.
  neutral;

  Color get color => switch (this) {
    SelTone.positive => Sel.success,
    SelTone.negative => Sel.danger,
    SelTone.neutral => Sel.ink,
  };
}

/// Convenience cells so screens do not restate the type ramp on every row.
abstract final class SelCell {
  /// The row's subject — a person, an arm, a period. Ink at weight 500.
  static Widget primary(String text) => Text(
    text,
    style: SelType.bodyMedium,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );

  /// Supporting fact. Warm gray at weight 400.
  static Widget secondary(String text) => Text(
    text,
    style: SelType.bodyMuted,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );

  /// Money and other figures. Tabular so digits align down the column.
  ///
  /// [tone] tints by meaning: an amount that counted toward totals reads
  /// positive, one that was rejected or reversed reads negative. Neutral
  /// figures — counts, targets, dates — stay Ink.
  static Widget numeric(
    String text, {
    bool strong = true,
    SelTone tone = SelTone.neutral,
  }) => Text(
    text,
    textAlign: TextAlign.right,
    style: (strong ? SelType.bodyMedium : SelType.bodyMuted).copyWith(
      color: tone.color,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );

  /// Two lines in one cell: subject above, detail beneath. For narrow layouts
  /// where two columns must collapse into one.
  static Widget stacked(String top, String bottom) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        top,
        style: SelType.bodyMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      Text(
        bottom,
        style: SelType.small,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ],
  );
}
