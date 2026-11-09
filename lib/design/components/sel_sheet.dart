import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../seline_colors.dart';
import '../seline_metrics.dart';
import '../seline_type.dart';

/// A column of a [SelSheet]. Widths are shares of the room left after the
/// mark and row-number columns, so the sheet is even by default; [weight]
/// is this column's share.
class SelSheetColumn {
  const SelSheetColumn(this.label, {this.weight = 1, this.numeric = false});

  final String label;
  final double weight;
  final bool numeric;
}

enum SelSheetCellKind {
  /// Typed into in place.
  text,

  /// A short list, like a spreadsheet's drop-down.
  choice,

  /// Opens something else on Enter or a click (a partner picker, a date).
  action,

  /// Shown, not changed here.
  fixed,
}

class SelSheetCell {
  const SelSheetCell(
    this.text, {
    this.kind = SelSheetCellKind.text,
    this.editText,
    this.options = const [],
    this.onAction,
    this.problem = false,
    this.changed = false,
    this.was,
  });

  /// What the cell shows.
  final String text;

  /// What editing starts from, when it differs from what is shown (the raw
  /// value from the sheet, say, against a formatted one).
  final String? editText;
  final SelSheetCellKind kind;
  final List<String> options;
  final VoidCallback? onAction;

  /// Something is wrong here: tinted, with a mark in the corner.
  final bool problem;

  /// Changed and not saved yet: tinted, bold, with a dot.
  final bool changed;

  /// The value before the change, shown in the cell bar.
  final String? was;
}

class SelSheetRow {
  const SelSheetRow({
    required this.mark,
    required this.number,
    required this.cells,
    this.note,
    this.noteStrong = false,
    this.dimmed = false,
  });

  final Widget mark;
  final String number;
  final List<SelSheetCell> cells;

  /// A line under the row saying what is wrong or what changed.
  final String? note;
  final bool noteStrong;
  final bool dimmed;
}

/// The spreadsheet both Check rows and Correct an import are built on
/// (canvas 27b and 20d): every cell editable in place, a cell bar above the
/// grid naming the selected cell, a narrow mark and number column, and even
/// columns that can be dragged wider or narrower and are remembered on this
/// device.
///
/// Keys, as in a spreadsheet: arrows move, Enter edits, Tab moves on,
/// Escape cancels.
class SelSheet extends StatefulWidget {
  const SelSheet({
    super.key,
    required this.columns,
    required this.rows,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
    this.storageKey,
    this.busy = false,
    this.shrinkWrap = false,
  });

  final List<SelSheetColumn> columns;
  final List<SelSheetRow> rows;

  /// (row index, column index) of the selected cell, if any.
  final (int, int)? selected;
  final void Function(int row, int column) onSelect;
  final void Function(int row, int column, String value) onEdit;

  /// Where column widths are remembered on this device; null keeps them
  /// for this visit only.
  final String? storageKey;
  final bool busy;

  /// Lay the rows out in full rather than scrolling inside the sheet.
  final bool shrinkWrap;

  @override
  State<SelSheet> createState() => _SelSheetState();
}

const double _markW = 34;
const double _numW = 36;
const double _rowH = 38;
const double _minCol = 56;

/// Below this a column is too narrow to read; the grid scrolls sideways instead.
const double _readableCol = 100;

class _SelSheetState extends State<SelSheet> {
  /// Shares of the flexible width, one per column; null means even.
  List<double>? _weights;
  bool _editing = false;
  final _editor = TextEditingController();
  final _editorFocus = FocusNode();
  final _keys = FocusNode(debugLabel: 'sheet');
  int? _dragging;
  double _flexWidth = 600;
  final _sideways = ScrollController();

  List<double> get _even => [for (final c in widget.columns) c.weight];

  @override
  void initState() {
    super.initState();
    _restore();
    _editorFocus.addListener(() {
      if (!_editorFocus.hasFocus && _editing) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant SelSheet old) {
    super.didUpdateWidget(old);
    if (old.columns.length != widget.columns.length) _weights = null;
    if (old.selected != widget.selected && _editing) _commit(move: false);
  }

  @override
  void dispose() {
    _editor.dispose();
    _editorFocus.dispose();
    _keys.dispose();
    _sideways.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final key = widget.storageKey;
    if (key == null) return;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('sheet-widths:$key');
      if (raw == null) return;
      final list = (jsonDecode(raw) as List)
          .map((e) => (e as num).toDouble())
          .toList();
      if (list.length == widget.columns.length && mounted) {
        setState(() => _weights = list);
      }
    } catch (_) {
      // Remembered widths are a convenience; the even ones always work.
    }
  }

  Future<void> _remember() async {
    final key = widget.storageKey;
    if (key == null) return;
    try {
      final p = await SharedPreferences.getInstance();
      if (_weights == null) {
        await p.remove('sheet-widths:$key');
      } else {
        await p.setString('sheet-widths:$key', jsonEncode(_weights));
      }
    } catch (_) {}
  }

  List<double> _widths(double flex) {
    final w = _weights ?? _even;
    final total = w.fold<double>(0, (a, b) => a + b);
    return [
      for (final x in w) (flex * x / total).clamp(_minCol, double.infinity),
    ];
  }

  void _makeEven() {
    setState(() => _weights = null);
    _remember();
  }

  void _resize(int col, double dx) {
    final widths = _widths(_flexWidth);
    if (col >= widths.length - 1) return;
    // Wider here, narrower next door, so the sheet keeps its width.
    final a = (widths[col] + dx).clamp(
      _minCol,
      widths[col] + widths[col + 1] - _minCol,
    );
    final b = widths[col] + widths[col + 1] - a;
    widths[col] = a;
    widths[col + 1] = b;
    setState(() => _weights = widths);
  }

  /// Double-click on an edge: just wide enough for the longest value.
  void _fit(int col) {
    final style = SelType.bodySm.copyWith(fontWeight: FontWeight.w700);
    var widest = _textWidth(widget.columns[col].label, style);
    for (final r in widget.rows) {
      if (col < r.cells.length) {
        final t = _textWidth(r.cells[col].text, style);
        if (t > widest) widest = t;
      }
    }
    final widths = _widths(_flexWidth);
    final want = (widest + 34).clamp(_minCol, _flexWidth * .6);
    final give = want - widths[col];
    final next = col + 1 < widths.length ? col + 1 : col - 1;
    if (next < 0) return;
    widths[col] = want;
    widths[next] = (widths[next] - give).clamp(_minCol, double.infinity);
    setState(() => _weights = widths);
    _remember();
  }

  double _textWidth(String s, TextStyle style) {
    final p = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return p.width;
  }

  // ------------------------------------------------------------ editing

  SelSheetCell? get _cell {
    final s = widget.selected;
    if (s == null || s.$1 >= widget.rows.length) return null;
    final cells = widget.rows[s.$1].cells;
    return s.$2 < cells.length ? cells[s.$2] : null;
  }

  void _begin([String? typed]) {
    final c = _cell;
    if (c == null || widget.busy) return;
    switch (c.kind) {
      case SelSheetCellKind.fixed:
        return;
      case SelSheetCellKind.action:
        c.onAction?.call();
        return;
      case SelSheetCellKind.choice:
        _pickChoice(c);
        return;
      case SelSheetCellKind.text:
        _editor.text = typed ?? c.editText ?? c.text;
        _editor.selection = typed == null
            ? TextSelection(baseOffset: 0, extentOffset: _editor.text.length)
            : TextSelection.collapsed(offset: _editor.text.length);
        setState(() => _editing = true);
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _editorFocus.requestFocus(),
        );
    }
  }

  Future<void> _pickChoice(SelSheetCell c) async {
    final s = widget.selected!;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset(box.size.width / 2, 120));
    final picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        for (final o in c.options) PopupMenuItem(value: o, child: Text(o)),
      ],
    );
    if (picked != null && picked != c.text) widget.onEdit(s.$1, s.$2, picked);
    _keys.requestFocus();
  }

  void _commit({bool move = true}) {
    final s = widget.selected;
    final c = _cell;
    final value = _editor.text.trim();
    setState(() => _editing = false);
    if (s != null && c != null && value != (c.editText ?? c.text).trim()) {
      widget.onEdit(s.$1, s.$2, value);
    }
    _keys.requestFocus();
  }

  void _cancel() {
    setState(() => _editing = false);
    _keys.requestFocus();
  }

  void _move(int dr, int dc) {
    if (widget.rows.isEmpty) return;
    final s = widget.selected ?? (0, 0);
    final cols = widget.columns.length;
    var r = s.$1 + dr;
    var c = s.$2 + dc;
    if (c >= cols) {
      c = 0;
      r++;
    } else if (c < 0) {
      c = cols - 1;
      r--;
    }
    r = r.clamp(0, widget.rows.length - 1);
    widget.onSelect(r, c);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_editing) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) {
      _move(1, 0);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _move(-1, 0);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _move(0, 1);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _move(0, -1);
    } else if (k == LogicalKeyboardKey.tab) {
      _move(0, HardwareKeyboard.instance.isShiftPressed ? -1 : 1);
    } else if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.f2) {
      _begin();
    } else if (e.character != null &&
        e.character!.length == 1 &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed &&
        RegExp(r'[\w\d.,₵$€£ -]').hasMatch(e.character!) &&
        _cell?.kind == SelSheetCellKind.text) {
      // Typing on a selected cell starts editing it, as in a spreadsheet.
      _begin(e.character);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // -------------------------------------------------------------- build

  String _ref() {
    final s = widget.selected;
    if (s == null || s.$1 >= widget.rows.length) return 'No cell';
    return 'Row ${widget.rows[s.$1].number} · ${widget.columns[s.$2].label}';
  }

  @override
  Widget build(BuildContext context) {
    final cell = _cell;
    final bar = Row(
      children: [
        Expanded(
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: Sel.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _editing ? Sel.ink : Sel.border,
                width: 1.5,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF3F8FD),
                    border: Border(
                      right: BorderSide(color: Sel.border, width: 1.5),
                    ),
                  ),
                  child: Text(
                    _ref(),
                    style: SelType.small.copyWith(
                      color: Sel.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  child: _editing
                      ? CallbackShortcuts(
                          bindings: {
                            const SingleActivator(LogicalKeyboardKey.escape):
                                _cancel,
                          },
                          child: TextField(
                            controller: _editor,
                            focusNode: _editorFocus,
                            style: SelType.body.copyWith(color: Sel.text),
                            onSubmitted: (_) {
                              _commit();
                              _move(1, 0);
                            },
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                            ),
                          ),
                        )
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _begin(),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Text(
                              cell?.text ?? '',
                              overflow: TextOverflow.ellipsis,
                              style: SelType.body.copyWith(color: Sel.text),
                            ),
                          ),
                        ),
                ),
                if (cell?.was != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text(
                      'was ${cell!.was}',
                      style: SelType.small.copyWith(color: Sel.warm),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: SelSpace.x2),
        _PillButton(
          label: 'Make columns even',
          onTap: _weights == null ? null : _makeEven,
        ),
      ],
    );

    return Focus(
      focusNode: _keys,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, c) {
          // Many columns on a small screen: keep each one readable and let
          // the grid scroll sideways rather than squeeze them all.
          _flexWidth = (c.maxWidth - _markW - _numW - 2).clamp(
            _readableCol * widget.columns.length,
            double.infinity,
          );
          final gridWidth = _flexWidth + _markW + _numW + 2;
          final scrolls = gridWidth > c.maxWidth + .5;
          final widths = _widths(_flexWidth);
          final head = Container(
            height: 34,
            decoration: const BoxDecoration(
              color: Color(0xFFF3F8FD),
              border: Border(bottom: BorderSide(color: Sel.border)),
            ),
            child: Row(
              children: [
                const SizedBox(width: _markW),
                _headCell('#', _numW, center: true),
                for (var i = 0; i < widget.columns.length; i++)
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _headCell(
                        widget.columns[i].label,
                        widths[i],
                        numeric: widget.columns[i].numeric,
                      ),
                      if (i < widget.columns.length - 1)
                        Positioned(
                          right: -4,
                          top: 0,
                          bottom: 0,
                          width: 8,
                          child: _Handle(
                            active: _dragging == i,
                            label: widget.columns[i].label,
                            onStart: () => setState(() => _dragging = i),
                            onDrag: (dx) => _resize(i, dx),
                            onEnd: () {
                              setState(() => _dragging = null);
                              _remember();
                            },
                            onFit: () => _fit(i),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          );
          Widget body(int r) => _row(r, widths);
          final rows = widget.shrinkWrap
              ? Column(
                  children: [
                    for (var r = 0; r < widget.rows.length; r++) body(r),
                  ],
                )
              : Expanded(
                  child: ListView.builder(
                    itemCount: widget.rows.length,
                    itemBuilder: (_, r) => body(r),
                  ),
                );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: widget.shrinkWrap
                ? MainAxisSize.min
                : MainAxisSize.max,
            children: [
              bar,
              const SizedBox(height: SelSpace.x2),
              Flexible(
                fit: widget.shrinkWrap ? FlexFit.loose : FlexFit.tight,
                child: Container(
                  decoration: BoxDecoration(
                    color: Sel.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Sel.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: () {
                    final grid = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: widget.shrinkWrap
                          ? MainAxisSize.min
                          : MainAxisSize.max,
                      children: [head, rows],
                    );
                    if (!scrolls) return grid;
                    return Scrollbar(
                      controller: _sideways,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _sideways,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(width: gridWidth, child: grid),
                      ),
                    );
                  }(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _headCell(
    String t,
    double w, {
    bool numeric = false,
    bool center = false,
  }) => Container(
    width: w,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    alignment: center
        ? Alignment.center
        : (numeric ? Alignment.centerRight : Alignment.centerLeft),
    decoration: const BoxDecoration(
      border: Border(left: BorderSide(color: Sel.border)),
    ),
    child: Text(
      t,
      overflow: TextOverflow.ellipsis,
      style: SelType.small.copyWith(
        color: Sel.warm,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _row(int r, List<double> widths) {
    final row = widget.rows[r];
    final s = widget.selected;
    final current = s != null && s.$1 == r;
    const line = BorderSide(color: Sel.rowLine);
    final cells = Row(
      children: [
        Container(
          width: _markW,
          height: _rowH,
          alignment: Alignment.center,
          color: current ? const Color(0xFFD9EBFC) : const Color(0xFFF8FAFC),
          child: row.mark,
        ),
        Container(
          width: _numW,
          height: _rowH,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: current ? const Color(0xFFD9EBFC) : const Color(0xFFF8FAFC),
            border: const Border(left: line),
          ),
          child: Text(
            row.number,
            style: SelType.small.copyWith(
              color: current ? Sel.ink : Sel.warm,
              fontWeight: current ? FontWeight.w800 : FontWeight.w400,
            ),
          ),
        ),
        for (var c = 0; c < widget.columns.length && c < row.cells.length; c++)
          _cell2(r, c, row.cells[c], widths[c]),
      ],
    );
    return Opacity(
      opacity: row.dimmed ? .5 : 1,
      child: Container(
        decoration: const BoxDecoration(border: Border(bottom: line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cells,
            if (row.note != null)
              Container(
                padding: EdgeInsets.fromLTRB(_markW + _numW + 10, 4, 10, 7),
                color: const Color(0xFFFBFDFF),
                child: Text(
                  row.note!,
                  style: SelType.small.copyWith(
                    color: Sel.ink,
                    fontWeight: row.noteStrong
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cell2(int r, int c, SelSheetCell cell, double w) {
    final s = widget.selected;
    final on = s != null && s.$1 == r && s.$2 == c;
    final numeric = widget.columns[c].numeric;
    final tint = cell.problem
        ? Sel.skyTint
        : cell.changed
        ? const Color(0xFFF3F8FD)
        : Sel.card;
    final strong = cell.problem || cell.changed;
    final text = Text(
      cell.text.isEmpty ? '—' : cell.text,
      textAlign: numeric ? TextAlign.right : TextAlign.left,
      overflow: TextOverflow.ellipsis,
      style: SelType.bodySm.copyWith(
        color: strong || numeric ? Sel.ink : Sel.text,
        fontWeight: cell.changed
            ? FontWeight.w800
            : (strong || numeric ? FontWeight.w700 : FontWeight.w400),
        fontFeatures: numeric ? const [FontFeature.tabularFigures()] : null,
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (on && !_editing) {
          _begin();
        } else {
          widget.onSelect(r, c);
          _keys.requestFocus();
        }
      },
      onDoubleTap: () {
        widget.onSelect(r, c);
        WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
      },
      child: Container(
        width: w,
        height: _rowH,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          color: tint,
          border: on
              ? Border.all(color: Sel.ink, width: 2)
              : const Border(left: BorderSide(color: Sel.rowLine)),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Row(
              children: [
                Expanded(child: text),
                if (cell.kind == SelSheetCellKind.choice)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.expand_more,
                      size: 16,
                      color: Color(0xFF8AA7C4),
                    ),
                  ),
              ],
            ),
            if (cell.problem)
              Positioned(
                top: 0,
                right: -10,
                child: CustomPaint(size: const Size(9, 9), painter: _Corner()),
              ),
            if (cell.changed)
              Positioned(
                top: 5,
                right: -5,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Sel.ink,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Corner extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(p, Paint()..color = Sel.ink);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Handle extends StatefulWidget {
  const _Handle({
    required this.active,
    required this.label,
    required this.onStart,
    required this.onDrag,
    required this.onEnd,
    required this.onFit,
  });

  final bool active;
  final String label;
  final VoidCallback onStart;
  final ValueChanged<double> onDrag;
  final VoidCallback onEnd;
  final VoidCallback onFit;

  @override
  State<_Handle> createState() => _HandleState();
}

class _HandleState extends State<_Handle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Drag to resize ${widget.label} · double-click to fit',
    waitDuration: const Duration(milliseconds: 500),
    child: MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => widget.onStart(),
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        onHorizontalDragEnd: (_) => widget.onEnd(),
        onDoubleTap: widget.onFit,
        child: Center(
          child: Container(
            width: 2,
            margin: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: widget.active || _hover
                  ? Sel.ink
                  : const Color(0xFFC9D6E3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    ),
  );
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Sel.card,
    shape: const StadiumBorder(side: BorderSide(color: Sel.border, width: 1.5)),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Text(
          label,
          style: SelType.small.copyWith(
            color: onTap == null ? Sel.warm : Sel.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}

/// One slim row of count pills above a sheet (canvas 27b): the chosen one
/// navy, every count always in view.
class SelPillTabs<T> extends StatelessWidget {
  const SelPillTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelect,
  });

  final List<(T, String, int)> tabs;
  final T selected;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final (value, label, count) in tabs)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Semantics(
              selected: value == selected,
              button: true,
              child: Material(
                color: value == selected ? Sel.ink : Colors.transparent,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => onSelect(value),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '$label  '),
                          TextSpan(
                            text: '$count',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      style: SelType.bodySm.copyWith(
                        color: value == selected ? Sel.card : Sel.warm,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
