import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../design/seline.dart';
import '../../../screens/arm_palette.dart';
import '../../arms/domain/partnership_arm.dart';
import 'bulk_import_autofix.dart';
import 'bulk_import_columns.dart';
import 'bulk_import_mapping.dart';
import 'bulk_import_models.dart';

/// Which column an issue belongs to, so the mark lands on the cell that is
/// actually wrong rather than colouring the whole row.
BulkImportColumn? columnForIssue(BulkImportIssueCode code) => switch (code) {
  BulkImportIssueCode.missingName ||
  BulkImportIssueCode.nameMismatch => BulkImportColumn.name,
  BulkImportIssueCode.missingFellowship ||
  BulkImportIssueCode.fellowshipMismatch => BulkImportColumn.fellowship,
  BulkImportIssueCode.missingAmount ||
  BulkImportIssueCode.invalidAmount => BulkImportColumn.amount,
  BulkImportIssueCode.missingDate ||
  BulkImportIssueCode.invalidDate => BulkImportColumn.date,
  BulkImportIssueCode.missingArm ||
  BulkImportIssueCode.armNotFound => BulkImportColumn.category,
  BulkImportIssueCode.ambiguousPhone => BulkImportColumn.contact,
  BulkImportIssueCode.memberIdNotFound ||
  BulkImportIssueCode.memberIdConflict => BulkImportColumn.memberId,
  BulkImportIssueCode.staffPastorYesPending => BulkImportColumn.pastorConfirmed,
  BulkImportIssueCode.duplicateInFile ||
  BulkImportIssueCode.duplicateInDatabase ||
  BulkImportIssueCode.periodNotFound => null,
};

/// Plain-English name and explanation for a problem.
///
/// The people who run an import are not engineers. "armNotFound" and
/// "Partner name · 1 row" tell them nothing; "We don't have an arm with this
/// name" tells them what to do next.
({String title, String help}) describeIssue(BulkImportIssueCode code) =>
    switch (code) {
      BulkImportIssueCode.missingName => (
        title: 'No name',
        help:
            'These rows have no name, so there is nobody to record the '
            'giving against. Type the name in, or drop the row.',
      ),
      BulkImportIssueCode.nameMismatch => (
        title: 'Spelled differently from the saved profile',
        help:
            'We matched these people by phone or member ID, but the '
            'spelling here is not the spelling on their profile. Fix it if '
            'it is a typo — leave it if the name really changed.',
      ),
      BulkImportIssueCode.missingFellowship => (
        title: 'No fellowship',
        help:
            'These rows have no fellowship. Fill it in so the partner '
            'lands in the right group.',
      ),
      BulkImportIssueCode.fellowshipMismatch => (
        title: 'Different fellowship from the saved profile',
        help:
            'The fellowship here is not the one on the partner profile. '
            'Fix whichever is out of date.',
      ),
      BulkImportIssueCode.missingAmount => (
        title: 'No amount',
        help: 'These rows have no amount, so there is nothing to record.',
      ),
      BulkImportIssueCode.invalidAmount => (
        title: "Amount isn't a number",
        help:
            'We could not read these as money. Remove any words and type '
            'the figure on its own, like 1500.',
      ),
      BulkImportIssueCode.missingDate => (
        title: 'No date',
        help: 'These rows have no date given.',
      ),
      BulkImportIssueCode.invalidDate => (
        title: "Date can't be read",
        help: 'Type these as year-month-day, like 2026-03-04.',
      ),
      BulkImportIssueCode.missingArm => (
        title: 'No partnership arm',
        help: 'Every entry needs an arm. Pick one for each row.',
      ),
      BulkImportIssueCode.armNotFound => (
        title: "We don't have an arm with this name",
        help:
            'The sheet uses a name your church has not set up. Point it at '
            'one of your arms — every row using that spelling changes at '
            'once, and Pillr remembers it for next time.',
      ),
      BulkImportIssueCode.periodNotFound => (
        title: 'No active giving period',
        help: 'Set an active period in Configuration, then come back.',
      ),
      BulkImportIssueCode.ambiguousPhone => (
        title: 'This phone number belongs to more than one partner',
        help:
            'We cannot tell who gave. Open the row and pick the right '
            'person, or correct the number.',
      ),
      BulkImportIssueCode.memberIdNotFound => (
        title: 'No partner with this member ID',
        help: 'Check the ID, or clear it and let us match on name and phone.',
      ),
      BulkImportIssueCode.memberIdConflict => (
        title: 'Member ID belongs to somebody else',
        help: 'The ID and the name point at two different partners.',
      ),
      BulkImportIssueCode.staffPastorYesPending => (
        title: 'Marked as with the pastor',
        help:
            'These will still go to a pastor for review — staff cannot '
            'confirm on the pastor\'s behalf.',
      ),
      BulkImportIssueCode.duplicateInFile ||
      BulkImportIssueCode.duplicateInDatabase => (
        title: 'Might already exist',
        help:
            'Keep it if the person really gave twice, or drop it if it is '
            'the same gift recorded twice.',
      ),
    };

double _columnWidth(BulkImportColumn c) => switch (c) {
  BulkImportColumn.date => 118,
  BulkImportColumn.name => 190,
  BulkImportColumn.memberId => 110,
  BulkImportColumn.contact => 132,
  BulkImportColumn.fellowship => 150,
  BulkImportColumn.email => 200,
  BulkImportColumn.amount => 110,
  BulkImportColumn.category => 170,
  BulkImportColumn.givenToNotes => 200,
  BulkImportColumn.pastorConfirmed => 130,
};

const double _rowHeight = 38;
const double _gutterWidth = 56;
const double _panelWidth = 340;

/// Hues used to tie a problem in the panel to its rows in the sheet. Distinct
/// from the arm palette, which is already carrying meaning in its own column.
const List<Color> _groupPalette = [
  Color(0xFFA8453A), // clay
  Color(0xFFB8862B), // ochre
  Color(0xFF4B5FA8), // indigo
  Color(0xFF4D7C5F), // moss
  Color(0xFF7A4B8C), // plum
  Color(0xFF2F7D82), // teal
];

enum _GroupKind { fix, problem, duplicate }

/// One problem, with every row it touches.
class _Group {
  _Group({
    required this.id,
    required this.kind,
    required this.title,
    required this.help,
    required this.color,
    required this.rows,
    required this.blocking,
    this.column,
    this.proposals = const [],
    this.byValue = const {},
  });

  final String id;
  final _GroupKind kind;
  final String title;
  final String help;
  final Color color;
  final List<int> rows;
  final bool blocking;
  final BulkImportColumn? column;
  final List<AutoFixProposal> proposals;

  /// For arm mismatches: the offending sheet text → the rows using it.
  final Map<String, List<int>> byValue;
}

/// The full-sheet editing surface: every row on screen, wrong cells marked in
/// the same colour as the problem that named them, and any cell editable in
/// place.
///
/// Edits go back to the *raw* rows, not the resolved ones, because resolution
/// (arm matching, partner matching, duplicate detection) has to run again
/// after any change — a corrected name can turn a new partner into an
/// existing one.
class BulkImportGrid extends ConsumerStatefulWidget {
  const BulkImportGrid({
    super.key,
    required this.rawRows,
    required this.resolved,
    required this.columns,
    required this.arms,
    required this.dayFirst,
    required this.busy,
    required this.money,
    required this.keptSheetRows,
    required this.droppedSheetRows,
    required this.onEditCell,
    required this.onApplyFixes,
    required this.onDayFirstChanged,
    required this.onKeepRow,
    required this.onDropRow,
    required this.onUndoDecision,
    this.onBulkMapArm,
  });

  final List<BulkRawRow> rawRows;

  /// Resolution output, index-aligned with [rawRows].
  final List<BulkResolvedRow> resolved;

  /// The mapped columns, in sheet order.
  final List<BulkImportColumn> columns;

  final List<PartnershipArm> arms;
  final bool dayFirst;
  final bool busy;
  final String Function(double) money;

  /// Rows confirmed as intentional, and rows set aside. A suspected duplicate
  /// is only ever a suspicion, so it holds up the import until somebody says
  /// which it is — but either answer can be taken back.
  final Set<int> keptSheetRows;
  final Set<int> droppedSheetRows;

  final void Function(int rowIndex, BulkImportColumn column, String value)
  onEditCell;
  final void Function(List<AutoFixProposal> proposals) onApplyFixes;
  final void Function(bool dayFirst) onDayFirstChanged;
  final void Function(int sheetRow) onKeepRow;
  final void Function(int sheetRow) onDropRow;
  final void Function(int sheetRow) onUndoDecision;

  /// Maps every row whose arm text is [sourceTexts] onto one arm at once.
  final Future<void> Function(List<String> sourceTexts, PartnershipArm arm)?
  onBulkMapArm;

  @override
  ConsumerState<BulkImportGrid> createState() => _BulkImportGridState();
}

class _BulkImportGridState extends ConsumerState<BulkImportGrid> {
  final ScrollController _vertical = ScrollController();
  final ScrollController _horizontal = ScrollController();

  int? _editingRow;
  BulkImportColumn? _editingColumn;
  TextEditingController? _editor;
  FocusNode? _editorFocus;

  /// Row the panel last pointed at — lit so the eye can find it.
  int? _flashRow;

  /// Problem the pointer is over, so its rows stand out in the sheet.
  String? _hoverGroup;

  bool _panelOpen = true;

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    _editor?.dispose();
    _editorFocus?.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ groups

  List<_Group> _buildGroups() {
    final groups = <_Group>[];
    var colorIndex = 0;
    Color nextColor() => _groupPalette[colorIndex++ % _groupPalette.length];

    // Work the fixes out first. A blocking problem that Pillr already knows
    // how to repair — 'GHS 1,000' is not a number, but it obviously means
    // 1000 — has to offer the repair on the problem itself. Listing the error
    // at the top and the cure further down is how someone ends up editing
    // eighteen cells by hand.
    final allFixes = detectAutoFixes(widget.rawRows, dayFirst: widget.dayFirst);
    final claimed = <String>{};
    String fixKey(AutoFixProposal p) => '${p.rowIndex}|${p.column.name}';

    // Problems first — they are what stops the import.
    final byCode = <BulkImportIssueCode, List<int>>{};
    final severityOf = <BulkImportIssueCode, BulkImportSeverity>{};
    for (var i = 0; i < widget.resolved.length; i++) {
      if (widget.droppedSheetRows.contains(widget.resolved[i].sheetRowNumber)) {
        continue;
      }
      for (final issue in widget.resolved[i].issues) {
        if (_isDuplicateCode(issue.code)) continue;
        final list = byCode.putIfAbsent(issue.code, () => []);
        if (!list.contains(i)) list.add(i);
        if (issue.severity == BulkImportSeverity.error) {
          severityOf[issue.code] = BulkImportSeverity.error;
        } else {
          severityOf.putIfAbsent(issue.code, () => issue.severity);
        }
      }
    }

    final orderedCodes = byCode.keys.toList()
      ..sort((a, b) {
        final aErr = severityOf[a] == BulkImportSeverity.error ? 0 : 1;
        final bErr = severityOf[b] == BulkImportSeverity.error ? 0 : 1;
        return aErr.compareTo(bErr);
      });

    for (final code in orderedCodes) {
      final rows = byCode[code]!;
      final column = columnForIssue(code);
      final described = describeIssue(code);
      final byValue = <String, List<int>>{};
      if (column != null) {
        for (final i in rows) {
          final v = widget.rawRows[i].valuesByColumn[column] ?? '';
          byValue.putIfAbsent(v, () => []).add(i);
        }
      }
      // Repairs that land on exactly these cells belong to this problem.
      final repairs = <AutoFixProposal>[];
      if (column != null) {
        for (final g in allFixes) {
          for (final p in g.proposals) {
            if (p.column == column && rows.contains(p.rowIndex)) {
              repairs.add(p);
              claimed.add(fixKey(p));
            }
          }
        }
      }

      groups.add(
        _Group(
          id: 'code:${code.name}',
          kind: _GroupKind.problem,
          title: described.title,
          help: described.help,
          color: nextColor(),
          rows: rows,
          blocking: severityOf[code] == BulkImportSeverity.error,
          column: column,
          byValue: byValue,
          proposals: repairs,
        ),
      );
    }

    // Duplicates: one group, every undecided row inside it.
    final duplicates = <int>[];
    for (var i = 0; i < widget.resolved.length; i++) {
      if (widget.resolved[i].issues.any((x) => _isDuplicateCode(x.code))) {
        duplicates.add(i);
      }
    }
    if (duplicates.isNotEmpty) {
      final described = describeIssue(BulkImportIssueCode.duplicateInFile);
      groups.add(
        _Group(
          id: 'duplicates',
          kind: _GroupKind.duplicate,
          title: described.title,
          help: described.help,
          color: nextColor(),
          rows: duplicates,
          blocking: duplicates.any(
            (i) => !_decided(widget.rawRows[i].sheetRowNumber),
          ),
        ),
      );
    }

    // Tidying last: it never blocks anything.
    for (final g in allFixes) {
      final proposals = <AutoFixProposal>[];
      final rows = <int>[];
      for (final p in g.proposals) {
        if (widget.droppedSheetRows.contains(p.sheetRow)) continue;
        // Already offered on the problem it repairs — don't ask twice.
        if (claimed.contains(fixKey(p))) continue;
        proposals.add(p);
        if (!rows.contains(p.rowIndex)) rows.add(p.rowIndex);
      }
      if (rows.isEmpty) continue;
      groups.add(
        _Group(
          id: 'fix:${g.kind.name}',
          kind: _GroupKind.fix,
          title: switch (g.kind) {
            AutoFixKind.nameCasing => 'Names we can tidy up',
            AutoFixKind.amount => 'Amounts we can clean up',
            AutoFixKind.date => 'Dates we can rewrite',
            AutoFixKind.phone => 'Phone numbers we can tidy up',
          },
          help: switch (g.kind) {
            AutoFixKind.nameCasing =>
              'Capitalisation and stray spaces. Nothing about the giving changes.',
            AutoFixKind.amount =>
              'Currency signs and commas removed so the figure reads as money.',
            AutoFixKind.date => 'Rewritten as year-month-day.',
            AutoFixKind.phone =>
              'Written one way, so the same person is recognised as one partner.',
          },
          color: nextColor(),
          rows: rows,
          blocking: false,
          column: g.kind.column,
          proposals: proposals,
        ),
      );
    }

    return groups;
  }

  bool _isDuplicateCode(BulkImportIssueCode c) =>
      c == BulkImportIssueCode.duplicateInFile ||
      c == BulkImportIssueCode.duplicateInDatabase;

  bool _decided(int sheetRow) =>
      widget.keptSheetRows.contains(sheetRow) ||
      widget.droppedSheetRows.contains(sheetRow);

  /// Brings a row into view and marks it.
  ///
  /// Scrolling to `index * rowHeight` puts the row at the top of the viewport,
  /// which is impossible for anything near the end of the sheet — every one of
  /// those clamps to the same maximum offset, so clicking row 50, 75 and 76 in
  /// the panel all landed in exactly the same place. This scrolls the minimum
  /// distance needed instead, and leaves the row alone if it is already on
  /// screen.
  void _jumpToRow(int rowIndex) {
    if (_vertical.hasClients) {
      const margin = _rowHeight * 2;
      final position = _vertical.position;
      final rowTop = rowIndex * _rowHeight;
      final rowBottom = rowTop + _rowHeight;
      final viewTop = _vertical.offset;
      final viewBottom = viewTop + position.viewportDimension;

      double? target;
      if (rowTop < viewTop + margin) {
        target = rowTop - margin;
      } else if (rowBottom > viewBottom - margin) {
        target = rowBottom - position.viewportDimension + margin;
      }

      if (target != null) {
        _vertical.animateTo(
          target.clamp(0.0, position.maxScrollExtent),
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        );
      }
    }
    setState(() => _flashRow = rowIndex);
  }

  // ------------------------------------------------------------------ editing

  void _beginEdit(int rowIndex, BulkImportColumn column) {
    if (widget.busy) return;
    _commitEdit();
    final value = widget.rawRows[rowIndex].valuesByColumn[column] ?? '';
    final editor = TextEditingController(text: value);
    editor.selection = TextSelection(baseOffset: 0, extentOffset: value.length);
    final focus = FocusNode();
    // Clicking away commits. Losing a typed correction because you clicked the
    // next cell is the kind of thing that makes people give up on an importer.
    focus.addListener(() {
      if (!focus.hasFocus) _commitEdit();
    });
    setState(() {
      _editingRow = rowIndex;
      _editingColumn = column;
      _editor = editor;
      _editorFocus = focus;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
  }

  void _commitEdit() {
    final row = _editingRow;
    final column = _editingColumn;
    final editor = _editor;
    if (row == null || column == null || editor == null) return;

    final before = widget.rawRows[row].valuesByColumn[column] ?? '';
    final after = editor.text.trim();

    _editor = null;
    _editorFocus?.dispose();
    _editorFocus = null;
    _editingRow = null;
    _editingColumn = null;
    editor.dispose();

    if (after != before) widget.onEditCell(row, column, after);
    if (mounted) setState(() {});
  }

  void _cancelEdit() {
    _editor?.dispose();
    _editorFocus?.dispose();
    setState(() {
      _editor = null;
      _editorFocus = null;
      _editingRow = null;
      _editingColumn = null;
    });
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final groups = _buildGroups();

    // A cell is marked by the first problem that names it; a row by the first
    // problem that touches it. Same colour in both places, so a group in the
    // panel and its rows in the sheet read as one thing.
    final rowColor = <int, Color>{};
    final cellColor = <int, Map<BulkImportColumn, Color>>{};
    final cellIsProblem = <int, Set<BulkImportColumn>>{};
    for (final g in groups) {
      for (final i in g.rows) {
        rowColor.putIfAbsent(i, () => g.color);
        if (g.column != null) {
          cellColor
              .putIfAbsent(i, () => {})
              .putIfAbsent(g.column!, () => g.color);
          if (g.kind != _GroupKind.fix) {
            cellIsProblem.putIfAbsent(i, () => {}).add(g.column!);
          }
        }
      }
    }

    final gridWidth =
        _gutterWidth +
        widget.columns.fold<double>(0, (a, c) => a + _columnWidth(c)) +
        _gutterWidth;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_panelOpen)
          SizedBox(
            width: _panelWidth,
            child: _IssuesPanel(
              groups: groups,
              rawRows: widget.rawRows,
              resolved: widget.resolved,
              arms: widget.arms,
              dayFirst: widget.dayFirst,
              busy: widget.busy,
              money: widget.money,
              keptSheetRows: widget.keptSheetRows,
              droppedSheetRows: widget.droppedSheetRows,
              onJumpToRow: _jumpToRow,
              onApplyFixes: widget.onApplyFixes,
              onDayFirstChanged: widget.onDayFirstChanged,
              onKeepRow: widget.onKeepRow,
              onDropRow: widget.onDropRow,
              onUndoDecision: widget.onUndoDecision,
              onBulkMapArm: widget.onBulkMapArm,
              onHoverGroup: (id) => setState(() => _hoverGroup = id),
              onCollapse: () => setState(() => _panelOpen = false),
            ),
          )
        else
          _CollapsedPanel(
            groups: groups,
            onExpand: () => setState(() => _panelOpen = true),
          ),
        const SizedBox(width: SelSpace.x4),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Sel.card,
              border: Border.all(color: Sel.border),
              borderRadius: BorderRadius.circular(SelRadius.card),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(SelRadius.card),
              child: Scrollbar(
                controller: _horizontal,
                child: SingleChildScrollView(
                  controller: _horizontal,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: gridWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _header(groups),
                        Expanded(
                          child: ListView.builder(
                            controller: _vertical,
                            itemExtent: _rowHeight,
                            itemCount: widget.rawRows.length,
                            itemBuilder: (context, i) => _row(
                              i,
                              rowColor[i],
                              cellColor[i] ?? const {},
                              cellIsProblem[i] ?? const {},
                              groups,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(List<_Group> groups) {
    final counts = <BulkImportColumn, int>{};
    final colors = <BulkImportColumn, Color>{};
    for (final g in groups) {
      if (g.column == null || g.kind == _GroupKind.fix) continue;
      counts[g.column!] = (counts[g.column!] ?? 0) + g.rows.length;
      colors.putIfAbsent(g.column!, () => g.color);
    }

    return Container(
      height: _rowHeight + 6,
      decoration: const BoxDecoration(
        color: Sel.canvas,
        border: Border(bottom: BorderSide(color: Sel.border)),
      ),
      child: Row(
        children: [
          const SizedBox(width: _gutterWidth),
          for (final c in widget.columns)
            Container(
              width: _columnWidth(c),
              padding: const EdgeInsets.symmetric(horizontal: SelSpace.x3),
              alignment: Alignment.centerLeft,
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: Sel.borderMuted)),
              ),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      bulkImportFieldLabel(c),
                      style: SelType.small.copyWith(color: Sel.soot),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if ((counts[c] ?? 0) > 0) ...[
                    const SizedBox(width: SelSpace.x2),
                    _CountBadge(count: counts[c]!, color: colors[c]!),
                  ],
                ],
              ),
            ),
          const SizedBox(width: _gutterWidth),
        ],
      ),
    );
  }

  Widget _row(
    int i,
    Color? rowColor,
    Map<BulkImportColumn, Color> cellColor,
    Set<BulkImportColumn> problemColumns,
    List<_Group> groups,
  ) {
    final raw = widget.rawRows[i];
    final resolved = i < widget.resolved.length ? widget.resolved[i] : null;
    final dropped = widget.droppedSheetRows.contains(raw.sheetRowNumber);
    final flashed = _flashRow == i;
    final highlighted =
        _hoverGroup != null &&
        groups.any((g) => g.id == _hoverGroup && g.rows.contains(i));

    return Opacity(
      opacity: dropped ? 0.4 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: highlighted
              ? (rowColor ?? Sel.cyan).withValues(alpha: 0.08)
              : (flashed ? Sel.skyWash : null),
          border: const Border(bottom: BorderSide(color: Sel.borderMuted)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: _gutterWidth,
              child: Row(
                children: [
                  // The colour bar is the link back to the panel: same hue,
                  // same problem.
                  Container(
                    width: 3,
                    height: _rowHeight,
                    color: rowColor ?? Colors.transparent,
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${raw.sheetRowNumber}',
                        style: SelType.small.copyWith(color: Sel.ash),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            for (final c in widget.columns)
              _cell(
                i,
                c,
                raw.valuesByColumn[c] ?? '',
                cellColor[c],
                problemColumns.contains(c),
                resolved,
                dropped,
              ),
            SizedBox(
              width: _gutterWidth,
              child: Center(
                child: dropped
                    ? IconButton(
                        icon: const Icon(
                          LucideIcons.undo2,
                          size: 14,
                          color: Sel.ash,
                        ),
                        tooltip: 'Put row ${raw.sheetRowNumber} back',
                        splashRadius: 14,
                        onPressed: widget.busy
                            ? null
                            : () => widget.onUndoDecision(raw.sheetRowNumber),
                      )
                    : IconButton(
                        icon: const Icon(
                          LucideIcons.x,
                          size: 14,
                          color: Sel.ash,
                        ),
                        tooltip: 'Leave row ${raw.sheetRowNumber} out',
                        splashRadius: 14,
                        onPressed: widget.busy
                            ? null
                            : () => widget.onDropRow(raw.sheetRowNumber),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(
    int rowIndex,
    BulkImportColumn column,
    String value,
    Color? mark,
    bool isProblem,
    BulkResolvedRow? resolved,
    bool dropped,
  ) {
    final width = _columnWidth(column);
    final editing = _editingRow == rowIndex && _editingColumn == column;

    if (editing) {
      return SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SelSpace.x1),
          child: Center(
            child: _EscapeToCancel(
              onCancel: _cancelEdit,
              child: TextField(
                controller: _editor,
                focusNode: _editorFocus,
                style: SelType.small.copyWith(color: Sel.ink),
                decoration: const InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: Sel.card,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: SelSpace.x2,
                    vertical: SelSpace.x2,
                  ),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: Sel.cyan),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Sel.cyan),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Sel.cyan, width: 1.5),
                  ),
                ),
                onSubmitted: (_) => _commitEdit(),
                onTapOutside: (_) => _commitEdit(),
              ),
            ),
          ),
        ),
      );
    }

    Widget content;
    if (column == BulkImportColumn.category && resolved?.armId != null) {
      content = ArmLabel(
        armId: resolved!.armId!,
        name: value.isEmpty ? resolved.armName : value,
        style: SelType.small.copyWith(color: Sel.ink),
      );
    } else {
      content = Text(
        value.isEmpty ? '—' : value,
        style: SelType.small.copyWith(
          color: value.isEmpty ? Sel.ash : (isProblem ? mark! : Sel.ink),
          decoration: dropped ? TextDecoration.lineThrough : null,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      );
    }

    final picker = _isPickerColumn(column);

    return SizedBox(
      width: width,
      child: Builder(
        // The menu anchors to this cell, not to the grid — a dropdown that
        // opens somewhere else is worse than no dropdown.
        builder: (cellContext) => InkWell(
          onTap: widget.busy || dropped
              ? null
              : () => picker
                    ? _openPicker(cellContext, rowIndex, column)
                    : _beginEdit(rowIndex, column),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: SelSpace.x3),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              // A problem is underlined; a tidy-up is only tinted, so
              // "capitalisation" never looks as loud as "this will not import".
              color: mark?.withValues(alpha: isProblem ? 0.07 : 0.04),
              border: Border(
                left: const BorderSide(color: Sel.borderMuted),
                bottom: isProblem && mark != null
                    ? BorderSide(color: mark, width: 1.5)
                    : BorderSide.none,
              ),
            ),
            child: Row(
              children: [
                Expanded(child: content),
                if (picker && !dropped)
                  const Icon(LucideIcons.chevronDown, size: 12, color: Sel.ash),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isPickerColumn(BulkImportColumn c) =>
      (c == BulkImportColumn.category && widget.arms.isNotEmpty) ||
      c == BulkImportColumn.pastorConfirmed;

  Future<void> _openPicker(
    BuildContext cellContext,
    int rowIndex,
    BulkImportColumn column,
  ) async {
    _commitEdit();
    final options = column == BulkImportColumn.pastorConfirmed
        ? const ['Yes', 'No']
        : [for (final a in widget.arms) a.name];
    final current = widget.rawRows[rowIndex].valuesByColumn[column] ?? '';

    final picked = await _anchoredMenu<String>(cellContext, [
      for (final o in options) (o, o),
    ], selected: current);
    if (picked != null && picked != current) {
      widget.onEditCell(rowIndex, column, picked);
    }
  }
}

/// Opens a menu directly under [anchor].
Future<T?> _anchoredMenu<T>(
  BuildContext anchor,
  List<(T, String)> options, {
  String? selected,
}) {
  if (options.isEmpty) return Future<T?>.value();
  final overlay = Overlay.of(anchor).context.findRenderObject() as RenderBox?;
  final box = anchor.findRenderObject() as RenderBox?;
  if (overlay == null || box == null) return Future<T?>.value();

  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  final position = RelativeRect.fromLTRB(
    topLeft.dx,
    topLeft.dy + box.size.height,
    overlay.size.width - topLeft.dx - box.size.width,
    overlay.size.height - topLeft.dy,
  );

  return showMenu<T>(
    context: anchor,
    color: Sel.card,
    position: position,
    constraints: const BoxConstraints(minWidth: 180),
    items: [
      for (final (value, label) in options)
        PopupMenuItem<T>(
          value: value,
          height: 36,
          child: Row(
            children: [
              if (selected != null &&
                  label.toLowerCase() == selected.toLowerCase())
                const Icon(LucideIcons.check, size: 13, color: Sel.cyan)
              else
                const SizedBox(width: 13),
              const SizedBox(width: SelSpace.x2),
              Flexible(
                child: Text(
                  label,
                  style: SelType.small.copyWith(color: Sel.ink),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// Escape abandons an in-progress cell edit.
class _EscapeToCancel extends StatelessWidget {
  const _EscapeToCancel({required this.onCancel, required this.child});

  final VoidCallback onCancel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          onCancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: SelType.small.copyWith(color: color, height: 1.2),
      ),
    );
  }
}

/// The panel folded away, so the sheet can have the whole window.
class _CollapsedPanel extends StatelessWidget {
  const _CollapsedPanel({required this.groups, required this.onExpand});

  final List<_Group> groups;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final blocking = groups.where((g) => g.blocking).length;
    return SizedBox(
      width: 44,
      child: Tooltip(
        message: blocking == 0
            ? 'Show what can be tidied'
            : '$blocking still to sort out — click to show',
        child: InkWell(
          onTap: onExpand,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Sel.card,
              border: Border.all(color: Sel.border),
              borderRadius: BorderRadius.circular(SelRadius.card),
            ),
            child: Column(
              children: [
                const SizedBox(height: SelSpace.x4),
                const Icon(LucideIcons.panelLeftOpen, size: 15, color: Sel.ash),
                const SizedBox(height: SelSpace.x3),
                for (final g in groups)
                  Padding(
                    padding: const EdgeInsets.only(bottom: SelSpace.x2),
                    child: Container(
                      height: 8,
                      width: 8,
                      decoration: BoxDecoration(
                        color: g.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                const Spacer(),
                if (blocking > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: SelSpace.x4),
                    child: Text('$blocking', style: SelType.small),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The docked panel: what is wrong, in plain words, grouped so one correction
/// covers every row that shares the problem.
///
/// The old importer listed problems row by row, which meant fixing the same
/// misspelt arm forty times, and named them in the app's own vocabulary.
class _IssuesPanel extends StatefulWidget {
  const _IssuesPanel({
    required this.groups,
    required this.rawRows,
    required this.resolved,
    required this.arms,
    required this.dayFirst,
    required this.busy,
    required this.money,
    required this.keptSheetRows,
    required this.droppedSheetRows,
    required this.onJumpToRow,
    required this.onApplyFixes,
    required this.onDayFirstChanged,
    required this.onKeepRow,
    required this.onDropRow,
    required this.onUndoDecision,
    required this.onBulkMapArm,
    required this.onHoverGroup,
    required this.onCollapse,
  });

  final List<_Group> groups;
  final List<BulkRawRow> rawRows;
  final List<BulkResolvedRow> resolved;
  final List<PartnershipArm> arms;
  final bool dayFirst;
  final bool busy;
  final String Function(double) money;
  final Set<int> keptSheetRows;
  final Set<int> droppedSheetRows;
  final void Function(int rowIndex) onJumpToRow;
  final void Function(List<AutoFixProposal>) onApplyFixes;
  final void Function(bool) onDayFirstChanged;
  final void Function(int sheetRow) onKeepRow;
  final void Function(int sheetRow) onDropRow;
  final void Function(int sheetRow) onUndoDecision;
  final Future<void> Function(List<String>, PartnershipArm)? onBulkMapArm;
  final void Function(String?) onHoverGroup;
  final VoidCallback onCollapse;

  @override
  State<_IssuesPanel> createState() => _IssuesPanelState();
}

class _IssuesPanelState extends State<_IssuesPanel> {
  final Set<String> _collapsed = {};

  bool _isOpen(String key) => !_collapsed.contains(key);
  void _toggle(String key) => setState(() {
    if (!_collapsed.remove(key)) _collapsed.add(key);
  });

  @override
  Widget build(BuildContext context) {
    final blocking = widget.groups.where((g) => g.blocking).toList();
    final undecided = _undecidedDuplicates();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Sel.card,
        border: Border.all(color: Sel.border),
        borderRadius: BorderRadius.circular(SelRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(SelSpace.x4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _headline(blocking, undecided),
                        style: SelType.subtitle,
                      ),
                      const SizedBox(height: SelSpace.x1),
                      Text(_subline(blocking, undecided), style: SelType.small),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    LucideIcons.panelLeftClose,
                    size: 15,
                    color: Sel.ash,
                  ),
                  tooltip: 'Hide this panel',
                  splashRadius: 15,
                  onPressed: widget.onCollapse,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Sel.borderMuted),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: SelSpace.x2),
              children: [
                for (final g in widget.groups) _group(g),
                if (widget.groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(SelSpace.x4),
                    child: Text(
                      'Nothing to fix. Every row is ready to import.',
                      style: SelType.small,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<int> _undecidedDuplicates() {
    for (final g in widget.groups) {
      if (g.kind != _GroupKind.duplicate) continue;
      return [
        for (final i in g.rows)
          if (!widget.keptSheetRows.contains(
                widget.rawRows[i].sheetRowNumber,
              ) &&
              !widget.droppedSheetRows.contains(
                widget.rawRows[i].sheetRowNumber,
              ))
            i,
      ];
    }
    return const [];
  }

  String _headline(List<_Group> blocking, List<int> undecided) {
    final problems = blocking
        .where((g) => g.kind != _GroupKind.duplicate)
        .length;
    if (problems == 0 && undecided.isEmpty) return 'Ready to import';
    if (problems == 0) {
      return '${undecided.length} ${undecided.length == 1 ? "row needs" : "rows need"} '
          'a yes or no';
    }
    return '$problems ${problems == 1 ? "thing" : "things"} to fix first';
  }

  String _subline(List<_Group> blocking, List<int> undecided) {
    final problems = blocking
        .where((g) => g.kind != _GroupKind.duplicate)
        .length;
    if (problems == 0 && undecided.isEmpty) {
      return 'Anything left below is optional tidying.';
    }
    if (problems == 0) {
      return 'These look like giving you have already recorded. Say keep or '
          'drop for each one — you can change your mind after.';
    }
    return 'Click a row to find it in the sheet, then click the cell to change it.';
  }

  // ------------------------------------------------------------------ groups

  Widget _group(_Group g) {
    final open = _isOpen(g.id);
    return MouseRegion(
      onEnter: (_) => widget.onHoverGroup(g.id),
      onExit: (_) => widget.onHoverGroup(null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HoverRow(
            tint: g.color,
            strength: 0.08,
            onTap: () => _toggle(g.id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                SelSpace.x4,
                SelSpace.x3,
                SelSpace.x3,
                SelSpace.x3,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Icon(
                      open ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                      size: 13,
                      color: Sel.ash,
                    ),
                  ),
                  const SizedBox(width: SelSpace.x2),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      height: 7,
                      width: 7,
                      decoration: BoxDecoration(
                        color: g.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: SelSpace.x2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          g.title,
                          style: SelType.small.copyWith(color: Sel.ink),
                        ),
                        Text(
                          '${g.rows.length} ${g.rows.length == 1 ? "row" : "rows"}',
                          style: SelType.small,
                        ),
                      ],
                    ),
                  ),
                  if (g.proposals.isNotEmpty)
                    SelButton(
                      label: g.kind == _GroupKind.fix
                          ? 'Fix all'
                          : 'Fix ${g.proposals.length}',
                      kind: SelButtonKind.quiet,
                      onPressed: widget.busy
                          ? null
                          : () => widget.onApplyFixes(g.proposals),
                    )
                  else if (g.kind == _GroupKind.duplicate &&
                      _undecidedDuplicates().isNotEmpty)
                    SelButton(
                      label: 'Keep all',
                      kind: SelButtonKind.quiet,
                      onPressed: widget.busy
                          ? null
                          : () {
                              for (final i in _undecidedDuplicates()) {
                                widget.onKeepRow(
                                  widget.rawRows[i].sheetRowNumber,
                                );
                              }
                            },
                    ),
                ],
              ),
            ),
          ),
          if (open) ...[
            if (g.help.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SelSpace.x10,
                  0,
                  SelSpace.x4,
                  SelSpace.x3,
                ),
                child: Text(g.help, style: SelType.small),
              ),
            ...switch (g.kind) {
              _GroupKind.fix => _fixBody(g),
              _GroupKind.duplicate => _duplicateBody(g),
              _GroupKind.problem => _problemBody(g),
            },
          ],
          const Divider(height: 1, color: Sel.borderMuted),
        ],
      ),
    );
  }

  List<Widget> _fixBody(_Group g) => [
    for (final p in g.proposals.take(6))
      _FixPreview(
        proposal: p,
        tint: g.color,
        onTap: () => widget.onJumpToRow(p.rowIndex),
      ),
    if (g.proposals.length > 6)
      Padding(
        padding: const EdgeInsets.fromLTRB(
          SelSpace.x10,
          SelSpace.x1,
          SelSpace.x4,
          SelSpace.x2,
        ),
        child: Text('and ${g.proposals.length - 6} more', style: SelType.small),
      ),
    if (g.column == BulkImportColumn.date)
      Padding(
        padding: const EdgeInsets.fromLTRB(
          SelSpace.x10,
          SelSpace.x2,
          SelSpace.x4,
          SelSpace.x3,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                // 4/3/2026 is 4 March or 3 April depending on who typed
                // it; the sheet cannot say which.
                widget.dayFirst
                    ? 'Reading 4/3 as 4 March'
                    : 'Reading 4/3 as 3 April',
                style: SelType.small,
              ),
            ),
            Switch(
              value: widget.dayFirst,
              activeThumbColor: Sel.cyan,
              onChanged: widget.busy ? null : widget.onDayFirstChanged,
            ),
          ],
        ),
      ),
  ];

  List<Widget> _problemBody(_Group g) {
    final canBulkMapArm =
        g.column == BulkImportColumn.category &&
        widget.onBulkMapArm != null &&
        widget.arms.isNotEmpty;

    // When we can repair it, show what the repair would do — the decision is
    // "does this look right", not "trust me".
    if (g.proposals.isNotEmpty && !canBulkMapArm) {
      return [
        for (final p in g.proposals.take(8))
          _FixPreview(
            proposal: p,
            tint: g.color,
            onTap: () => widget.onJumpToRow(p.rowIndex),
          ),
        if (g.proposals.length > 8)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SelSpace.x10,
              SelSpace.x1,
              SelSpace.x4,
              SelSpace.x2,
            ),
            child: Text(
              'and ${g.proposals.length - 8} more',
              style: SelType.small,
            ),
          ),
        if (g.rows.length > g.proposals.length)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SelSpace.x10,
              SelSpace.x1,
              SelSpace.x4,
              SelSpace.x2,
            ),
            child: Text(
              '${g.rows.length - g.proposals.length} of these we cannot work '
              'out — click the cell and type it in.',
              style: SelType.small,
            ),
          ),
        const SizedBox(height: SelSpace.x2),
      ];
    }

    // Grouping inside a problem by the offending value turns thirty
    // corrections back into one.
    if (g.byValue.length > 1 || canBulkMapArm) {
      return [
        for (final entry in g.byValue.entries)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SelSpace.x10,
              0,
              SelSpace.x4,
              SelSpace.x3,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.key.isEmpty ? '(empty)' : '"${entry.key}"',
                  style: SelType.small.copyWith(color: Sel.ink),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: SelSpace.x1),
                for (final i in entry.value.take(6)) _rowLine(i, g.color),
                if (entry.value.length > 6)
                  Text(
                    'and ${entry.value.length - 6} more',
                    style: SelType.small,
                  ),
                if (canBulkMapArm) ...[
                  const SizedBox(height: SelSpace.x2),
                  _ArmAssign(
                    arms: widget.arms,
                    busy: widget.busy,
                    onPick: (arm) => widget.onBulkMapArm!([entry.key], arm),
                  ),
                ],
              ],
            ),
          ),
      ];
    }

    return [
      for (final i in g.rows.take(12))
        Padding(
          padding: const EdgeInsets.only(
            left: SelSpace.x10,
            right: SelSpace.x4,
          ),
          child: _rowLine(i, g.color),
        ),
      if (g.rows.length > 12)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SelSpace.x10,
            0,
            SelSpace.x4,
            SelSpace.x2,
          ),
          child: Text('and ${g.rows.length - 12} more', style: SelType.small),
        ),
      const SizedBox(height: SelSpace.x2),
    ];
  }

  List<Widget> _duplicateBody(_Group g) => [
    for (final i in g.rows)
      _DuplicateRow(
        tint: g.color,
        sheetRow: widget.rawRows[i].sheetRowNumber,
        summary: _rowSummary(i),
        message: _duplicateMessage(i),
        kept: widget.keptSheetRows.contains(widget.rawRows[i].sheetRowNumber),
        dropped: widget.droppedSheetRows.contains(
          widget.rawRows[i].sheetRowNumber,
        ),
        busy: widget.busy,
        onTap: () => widget.onJumpToRow(i),
        onKeep: () => widget.onKeepRow(widget.rawRows[i].sheetRowNumber),
        onDrop: () => widget.onDropRow(widget.rawRows[i].sheetRowNumber),
        onUndo: () => widget.onUndoDecision(widget.rawRows[i].sheetRowNumber),
      ),
  ];

  String _duplicateMessage(int i) {
    if (i >= widget.resolved.length) return '';
    for (final issue in widget.resolved[i].issues) {
      if (issue.code == BulkImportIssueCode.duplicateInFile) {
        return 'Appears twice in this file';
      }
      if (issue.code == BulkImportIssueCode.duplicateInDatabase) {
        return 'Already recorded in Pillr';
      }
    }
    return '';
  }

  /// "Marian Gasinu · ₵1,000 · 4 Mar" — how a person recognises their own row.
  String _rowSummary(int i) {
    if (i >= widget.resolved.length) {
      return 'Row ${widget.rawRows[i].sheetRowNumber}';
    }
    final r = widget.resolved[i];
    final name = r.fullName.trim().isEmpty ? '(no name)' : r.fullName.trim();
    final date = '${r.dateGiven.day} ${_monthName(r.dateGiven.month)}';
    // A row whose amount would not parse resolves to zero; showing "₵0" reads
    // as a real figure, so show what the sheet actually says instead.
    final rawAmount =
        widget.rawRows[i].valuesByColumn[BulkImportColumn.amount]?.trim() ?? '';
    final amount = r.amountCedis == 0 && rawAmount.isNotEmpty
        ? rawAmount
        : widget.money(r.amountCedis);
    return '$name · $amount · $date';
  }

  Widget _rowLine(int i, Color color) {
    return _HoverRow(
      tint: color,
      onTap: () => widget.onJumpToRow(i),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SelSpace.x1),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text(
                '${widget.rawRows[i].sheetRowNumber}',
                style: SelType.small.copyWith(color: color),
              ),
            ),
            Expanded(
              child: Text(
                _rowSummary(i),
                style: SelType.small.copyWith(color: Sel.ink),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _monthName(int m) => const [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][(m - 1).clamp(0, 11)];

class _FixPreview extends StatelessWidget {
  const _FixPreview({
    required this.proposal,
    required this.onTap,
    required this.tint,
  });

  final AutoFixProposal proposal;
  final VoidCallback onTap;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return _HoverRow(
      tint: tint,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          SelSpace.x10,
          SelSpace.x1,
          SelSpace.x4,
          SelSpace.x1,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text(
                '${proposal.sheetRow}',
                style: SelType.small.copyWith(color: Sel.ash),
              ),
            ),
            Expanded(
              child: Text(
                proposal.before,
                style: SelType.small.copyWith(
                  color: Sel.ash,
                  decoration: TextDecoration.lineThrough,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: SelSpace.x2),
              child: Icon(LucideIcons.arrowRight, size: 11, color: Sel.ash),
            ),
            Expanded(
              child: Text(
                proposal.after,
                style: SelType.small.copyWith(color: Sel.ink),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A suspected duplicate: keep it or drop it — and change your mind after.
class _DuplicateRow extends StatelessWidget {
  const _DuplicateRow({
    required this.tint,
    required this.sheetRow,
    required this.summary,
    required this.message,
    required this.kept,
    required this.dropped,
    required this.busy,
    required this.onTap,
    required this.onKeep,
    required this.onDrop,
    required this.onUndo,
  });

  final Color tint;
  final int sheetRow;
  final String summary;
  final String message;
  final bool kept;
  final bool dropped;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onKeep;
  final VoidCallback onDrop;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final decided = kept || dropped;
    return _HoverRow(
      tint: tint,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          SelSpace.x10,
          SelSpace.x2,
          SelSpace.x4,
          SelSpace.x2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Text(
                    '$sheetRow',
                    style: SelType.small.copyWith(color: Sel.ash),
                  ),
                ),
                Expanded(
                  child: Text(
                    summary,
                    style: SelType.small.copyWith(
                      color: Sel.ink,
                      decoration: dropped ? TextDecoration.lineThrough : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 2),
                child: Text(message, style: SelType.small),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: decided
                  ? Row(
                      children: [
                        Icon(
                          kept ? LucideIcons.check : LucideIcons.minus,
                          size: 12,
                          color: kept ? Sel.success : Sel.ash,
                        ),
                        const SizedBox(width: SelSpace.x1),
                        Text(
                          kept ? 'Keeping this one' : 'Leaving this one out',
                          style: SelType.small,
                        ),
                        const Spacer(),
                        SelButton(
                          label: 'Undo',
                          kind: SelButtonKind.quiet,
                          onPressed: busy ? null : onUndo,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        SelButton(
                          label: 'Keep',
                          kind: SelButtonKind.quiet,
                          onPressed: busy ? null : onKeep,
                        ),
                        SelButton(
                          label: 'Drop',
                          kind: SelButtonKind.quiet,
                          onPressed: busy ? null : onDrop,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Assigns one arm to every row sharing an unmatched arm text.
class _ArmAssign extends StatelessWidget {
  const _ArmAssign({
    required this.arms,
    required this.busy,
    required this.onPick,
  });

  final List<PartnershipArm> arms;
  final bool busy;
  final void Function(PartnershipArm) onPick;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (anchor) => InkWell(
        onTap: busy
            ? null
            : () async {
                final picked = await _anchoredMenu<PartnershipArm>(anchor, [
                  for (final a in arms) (a, a.name),
                ]);
                if (picked != null) onPick(picked);
              },
        borderRadius: BorderRadius.circular(SelRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SelSpace.x3,
            vertical: SelSpace.x2,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: Sel.border),
            borderRadius: BorderRadius.circular(SelRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Use one of our arms instead',
                style: SelType.small.copyWith(color: Sel.ink),
              ),
              const SizedBox(width: SelSpace.x2),
              const Icon(LucideIcons.chevronDown, size: 12, color: Sel.ash),
            ],
          ),
        ),
      ),
    );
  }
}

/// A clickable line in the issues panel that says so on hover.
///
/// [InkWell] cannot do this here: ink paints on the nearest [Material], which
/// is behind the opaque panel card, so the tint never reaches the surface you
/// are actually looking at. This paints its own background instead — the same
/// hue as the problem the row belongs to, so hovering also says which group it
/// came from.
class _HoverRow extends StatefulWidget {
  const _HoverRow({
    required this.tint,
    required this.onTap,
    required this.child,
    this.strength = 0.13,
  });

  final Color tint;
  final VoidCallback onTap;
  final Widget child;
  final double strength;

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          decoration: BoxDecoration(
            color: _hovering
                ? widget.tint.withValues(alpha: widget.strength)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(SelRadius.card),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
