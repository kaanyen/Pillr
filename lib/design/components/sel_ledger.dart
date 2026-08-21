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
  const SelRow({required this.cells, this.onTap, this.selected = false, this.leading});

  final List<Widget> cells;
  final VoidCallback? onTap;
  final bool selected;

  /// Optional leading widget (checkbox, avatar) rendered before the first cell.
  final Widget? leading;
}

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
  });

  final List<SelColumn> columns;
  final List<SelRow> rows;
  final double minWidth;

  /// Hide the caption row for short embedded lists where it is noise.
  final bool showCaptions;

  /// Shown in place of rows when [rows] is empty.
  final Widget? emptyState;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty && emptyState != null) {
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
          final content = SizedBox(
            width: needsScroll ? minWidth : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showCaptions) ...[
                  _CaptionRow(columns: columns, hasLeading: _hasLeading),
                  const Divider(height: 1, color: Sel.border),
                ],
                for (var i = 0; i < rows.length; i++) ...[
                  _LedgerRow(
                    row: rows[i],
                    columns: columns,
                    hasLeading: _hasLeading,
                  ),
                  if (i != rows.length - 1)
                    const Divider(height: 1, color: Sel.border),
                ],
              ],
            ),
          );

          if (!needsScroll) return content;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: content,
          );
        },
      ),
    );
  }

  bool get _hasLeading => rows.any((r) => r.leading != null);
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
      color: bg,
      padding: const EdgeInsets.symmetric(
        horizontal: SelSpace.x6,
        vertical: SelSpace.x3,
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

    if (r.onTap == null) return body;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(onTap: r.onTap, child: body),
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
  static Widget numeric(String text, {bool strong = true}) => Text(
        text,
        textAlign: TextAlign.right,
        style: (strong ? SelType.bodyMedium : SelType.bodyMuted)
            .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );

  /// Two lines in one cell: subject above, detail beneath. For narrow layouts
  /// where two columns must collapse into one.
  static Widget stacked(String top, String bottom) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(top, style: SelType.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(bottom, style: SelType.small, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      );
}
