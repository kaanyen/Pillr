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

/// Which column an issue belongs to, so the grid can put the highlight on the
/// cell that is actually wrong rather than colouring the whole row.
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
  // Row-level: a duplicate is about the whole row, and a missing period is
  // about church settings, not any cell in the sheet.
  BulkImportIssueCode.duplicateInFile ||
  BulkImportIssueCode.duplicateInDatabase ||
  BulkImportIssueCode.periodNotFound => null,
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
const double _gutterWidth = 52;

/// The full-sheet editing surface: every row on screen, wrong cells marked,
/// any cell editable in place, and a panel that walks through what is wrong.
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
    required this.issueLabel,
    required this.onEditCell,
    required this.onApplyFixes,
    required this.onDayFirstChanged,
    required this.onRemoveRow,
    required this.acknowledgedSheetRows,
    required this.onAcknowledgeDuplicate,
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
  final String Function(BulkImportIssueCode) issueLabel;

  final void Function(int rowIndex, BulkImportColumn column, String value)
  onEditCell;
  final void Function(List<AutoFixProposal> proposals) onApplyFixes;
  final void Function(bool dayFirst) onDayFirstChanged;
  final void Function(int rowIndex) onRemoveRow;

  /// Sheet rows the user has confirmed are intentional, not accidental
  /// double-entry. A duplicate is only ever a suspicion, so it blocks the
  /// import until someone says which it is.
  final Set<int> acknowledgedSheetRows;
  final void Function(int sheetRow) onAcknowledgeDuplicate;

  /// Maps every row whose arm text is [sourceTexts] onto one arm at once.
  final Future<void> Function(List<String> sourceTexts, PartnershipArm arm)?
  onBulkMapArm;

  @override
  ConsumerState<BulkImportGrid> createState() => _BulkImportGridState();
}

class _BulkImportGridState extends ConsumerState<BulkImportGrid> {
  final ScrollController _vertical = ScrollController();
  final ScrollController _horizontal = ScrollController();

  /// The cell currently open for editing, if any.
  int? _editingRow;
  BulkImportColumn? _editingColumn;
  TextEditingController? _editor;
  FocusNode? _editorFocus;

  /// Row the issues panel last jumped to — flashed so the eye can find it.
  int? _flashRow;

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    _editor?.dispose();
    _editorFocus?.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ issues

  /// Columns in error, per row index.
  Map<int, Map<BulkImportColumn, BulkImportIssue>> get _cellIssues {
    final out = <int, Map<BulkImportColumn, BulkImportIssue>>{};
    for (var i = 0; i < widget.resolved.length; i++) {
      for (final issue in widget.resolved[i].issues) {
        final col = columnForIssue(issue.code);
        if (col == null) continue;
        final existing = out.putIfAbsent(i, () => {})[col];
        // An error outranks a warning on the same cell.
        if (existing == null ||
            (existing.severity == BulkImportSeverity.warning &&
                issue.severity == BulkImportSeverity.error)) {
          out[i]![col] = issue;
        }
      }
    }
    return out;
  }

  void _jumpToRow(int rowIndex) {
    final target = (rowIndex * _rowHeight).clamp(
      0.0,
      _vertical.position.maxScrollExtent,
    );
    _vertical.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
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
    // Clicking away is a commit, not a cancel — losing a typed correction
    // because you clicked the next cell is the kind of thing that makes people
    // give up on an importer.
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

  bool get _hasArmColumn => widget.columns.contains(BulkImportColumn.category);

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final cellIssues = _cellIssues;
    final gridWidth =
        _gutterWidth +
        widget.columns.fold<double>(0, (a, c) => a + _columnWidth(c)) +
        _gutterWidth;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 320,
          child: _IssuesPanel(
            rawRows: widget.rawRows,
            resolved: widget.resolved,
            cellIssues: cellIssues,
            columns: widget.columns,
            arms: widget.arms,
            dayFirst: widget.dayFirst,
            busy: widget.busy,
            issueLabel: widget.issueLabel,
            acknowledgedSheetRows: widget.acknowledgedSheetRows,
            onAcknowledgeDuplicate: widget.onAcknowledgeDuplicate,
            onJumpToRow: _jumpToRow,
            onApplyFixes: widget.onApplyFixes,
            onDayFirstChanged: widget.onDayFirstChanged,
            onRemoveRow: widget.onRemoveRow,
            onBulkMapArm: widget.onBulkMapArm,
          ),
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
                        _header(cellIssues),
                        Expanded(
                          child: ListView.builder(
                            controller: _vertical,
                            itemExtent: _rowHeight,
                            itemCount: widget.rawRows.length,
                            itemBuilder: (context, i) =>
                                _row(i, cellIssues[i] ?? const {}),
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

  Widget _header(Map<int, Map<BulkImportColumn, BulkImportIssue>> cellIssues) {
    final counts = <BulkImportColumn, int>{};
    for (final byColumn in cellIssues.values) {
      for (final entry in byColumn.entries) {
        if (entry.value.severity == BulkImportSeverity.error) {
          counts[entry.key] = (counts[entry.key] ?? 0) + 1;
        }
      }
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
                    _CountBadge(count: counts[c]!),
                  ],
                ],
              ),
            ),
          const SizedBox(width: _gutterWidth),
        ],
      ),
    );
  }

  Widget _row(int i, Map<BulkImportColumn, BulkImportIssue> issues) {
    final raw = widget.rawRows[i];
    final resolved = i < widget.resolved.length ? widget.resolved[i] : null;
    final flashed = _flashRow == i;

    return Container(
      decoration: BoxDecoration(
        color: flashed ? Sel.skyWash : null,
        border: const Border(bottom: BorderSide(color: Sel.borderMuted)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _gutterWidth,
            child: Center(
              child: Text(
                '${raw.sheetRowNumber}',
                style: SelType.small.copyWith(color: Sel.ash),
              ),
            ),
          ),
          for (final c in widget.columns)
            _cell(i, c, raw.valuesByColumn[c] ?? '', issues[c], resolved),
          SizedBox(
            width: _gutterWidth,
            child: Center(
              child: IconButton(
                icon: const Icon(LucideIcons.x, size: 14, color: Sel.ash),
                tooltip: 'Remove row ${raw.sheetRowNumber}',
                splashRadius: 14,
                onPressed: widget.busy ? null : () => widget.onRemoveRow(i),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(
    int rowIndex,
    BulkImportColumn column,
    String value,
    BulkImportIssue? issue,
    BulkResolvedRow? resolved,
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
                // Escape backs out without writing, so a mistyped cell can be
                // abandoned rather than saved by clicking away.
                onEditingComplete: _commitEdit,
              ),
            ),
          ),
        ),
      );
    }

    final isError = issue?.severity == BulkImportSeverity.error;
    final isWarning = issue?.severity == BulkImportSeverity.warning;

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
          color: value.isEmpty ? Sel.ash : (isError ? Sel.danger : Sel.ink),
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      );
    }

    final picker = _isPickerColumn(column);

    return SizedBox(
      width: width,
      child: Tooltip(
        message: issue == null
            ? ''
            : (issue.message ?? widget.issueLabel(issue.code)),
        child: InkWell(
          onTap: widget.busy
              ? null
              : () => picker
                    ? _openPicker(rowIndex, column)
                    : _beginEdit(rowIndex, column),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: SelSpace.x3),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: isError
                  ? Sel.danger.withValues(alpha: 0.07)
                  : (isWarning ? Sel.warning.withValues(alpha: 0.07) : null),
              border: Border(
                left: const BorderSide(color: Sel.borderMuted),
                bottom: isError
                    ? const BorderSide(color: Sel.danger, width: 1.5)
                    : BorderSide.none,
              ),
            ),
            child: Row(
              children: [
                Expanded(child: content),
                if (picker)
                  const Icon(LucideIcons.chevronDown, size: 12, color: Sel.ash),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isPickerColumn(BulkImportColumn c) =>
      (c == BulkImportColumn.category &&
          _hasArmColumn &&
          widget.arms.isNotEmpty) ||
      c == BulkImportColumn.pastorConfirmed;

  Future<void> _openPicker(int rowIndex, BulkImportColumn column) async {
    _commitEdit();
    final options = column == BulkImportColumn.pastorConfirmed
        ? const ['Yes', 'No']
        : [for (final a in widget.arms) a.name];
    final current = widget.rawRows[rowIndex].valuesByColumn[column] ?? '';

    final picked = await showMenu<String>(
      context: context,
      position: _menuPositionFor(context),
      color: Sel.card,
      items: [
        for (final o in options)
          PopupMenuItem<String>(
            value: o,
            height: 36,
            child: Row(
              children: [
                if (o.toLowerCase() == current.toLowerCase())
                  const Icon(LucideIcons.check, size: 13, color: Sel.cyan)
                else
                  const SizedBox(width: 13),
                const SizedBox(width: SelSpace.x2),
                Text(o, style: SelType.small.copyWith(color: Sel.ink)),
              ],
            ),
          ),
      ],
    );
    if (picked != null && picked != current) {
      widget.onEditCell(rowIndex, column, picked);
    }
  }

  RelativeRect _menuPositionFor(BuildContext context) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return RelativeRect.fromLTRB(0, 0, 0, 0);
    }
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    return RelativeRect.fromLTRB(
      topLeft.dx,
      topLeft.dy + box.size.height,
      overlay.size.width - topLeft.dx,
      0,
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Sel.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: SelType.small.copyWith(color: Sel.danger, height: 1.2),
      ),
    );
  }
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

/// The docked panel: what is wrong, grouped, with the fixes that can be made
/// in one click.
///
/// The old importer listed problems row by row, which meant fixing the same
/// misspelt arm forty times. Grouping by column — and by the actual offending
/// value inside a column — turns forty corrections into one.
class _IssuesPanel extends StatefulWidget {
  const _IssuesPanel({
    required this.rawRows,
    required this.resolved,
    required this.cellIssues,
    required this.columns,
    required this.arms,
    required this.dayFirst,
    required this.busy,
    required this.issueLabel,
    required this.acknowledgedSheetRows,
    required this.onAcknowledgeDuplicate,
    required this.onJumpToRow,
    required this.onApplyFixes,
    required this.onDayFirstChanged,
    required this.onRemoveRow,
    required this.onBulkMapArm,
  });

  final List<BulkRawRow> rawRows;
  final List<BulkResolvedRow> resolved;
  final Map<int, Map<BulkImportColumn, BulkImportIssue>> cellIssues;
  final List<BulkImportColumn> columns;
  final List<PartnershipArm> arms;
  final bool dayFirst;
  final bool busy;
  final String Function(BulkImportIssueCode) issueLabel;
  final Set<int> acknowledgedSheetRows;
  final void Function(int sheetRow) onAcknowledgeDuplicate;
  final void Function(int rowIndex) onJumpToRow;
  final void Function(List<AutoFixProposal>) onApplyFixes;
  final void Function(bool) onDayFirstChanged;
  final void Function(int rowIndex) onRemoveRow;
  final Future<void> Function(List<String>, PartnershipArm)? onBulkMapArm;

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
    final fixes = detectAutoFixes(widget.rawRows, dayFirst: widget.dayFirst);
    final byColumn = <BulkImportColumn, List<int>>{};
    final rowLevel = <int, BulkImportIssue>{};

    for (var i = 0; i < widget.resolved.length; i++) {
      for (final issue in widget.resolved[i].issues) {
        final col = columnForIssue(issue.code);
        if (col == null) {
          rowLevel.putIfAbsent(i, () => issue);
        } else {
          final list = byColumn.putIfAbsent(col, () => []);
          if (!list.contains(i)) list.add(i);
        }
      }
    }

    final blocking = widget.resolved.where((r) => r.isBlocking).length;

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  blocking == 0
                      ? 'Nothing blocking'
                      : '$blocking rows need attention',
                  style: SelType.subtitle,
                ),
                const SizedBox(height: SelSpace.x1),
                Text(
                  blocking == 0
                      ? 'Every row can be imported. Fix anything else if you want to.'
                      : 'Fix these before importing. Click a row to find it in the sheet.',
                  style: SelType.small,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Sel.borderMuted),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: SelSpace.x2),
              children: [
                if (fixes.isNotEmpty) ..._autoFixSection(fixes),
                for (final entry in byColumn.entries)
                  _columnGroup(entry.key, entry.value),
                if (rowLevel.isNotEmpty) _rowLevelGroup(rowLevel),
                if (fixes.isEmpty && byColumn.isEmpty && rowLevel.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(SelSpace.x4),
                    child: Text(
                      'No problems found in this sheet.',
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

  // ------------------------------------------------------------- auto-fixes

  List<Widget> _autoFixSection(List<AutoFixGroup> groups) {
    final hasDates = groups.any((g) => g.kind == AutoFixKind.date);
    return [
      for (final g in groups)
        _Group(
          title: g.label,
          count: g.count,
          tone: Sel.info,
          open: _isOpen('fix:${g.kind.name}'),
          onToggle: () => _toggle('fix:${g.kind.name}'),
          trailing: SelButton(
            label: 'Fix all',
            kind: SelButtonKind.quiet,
            onPressed: widget.busy
                ? null
                : () => widget.onApplyFixes(g.proposals),
          ),
          children: [
            for (final p in g.proposals.take(6))
              _FixPreview(
                proposal: p,
                onTap: () => widget.onJumpToRow(p.rowIndex),
              ),
            if (g.count > 6)
              Padding(
                padding: const EdgeInsets.only(
                  left: SelSpace.x4,
                  top: SelSpace.x1,
                  bottom: SelSpace.x2,
                ),
                child: Text('and ${g.count - 6} more', style: SelType.small),
              ),
          ],
        ),
      if (hasDates)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SelSpace.x4,
            0,
            SelSpace.x4,
            SelSpace.x3,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  // 4/3/2026 is 4 March or 3 April depending on who typed it;
                  // the sheet cannot say which, so this is a question, not a
                  // guess the importer makes quietly.
                  widget.dayFirst
                      ? 'Reading dates day first'
                      : 'Reading dates month first',
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
  }

  // ---------------------------------------------------------- column groups

  Widget _columnGroup(BulkImportColumn column, List<int> rowIndexes) {
    // Inside a column, group by the value that is actually wrong — one
    // misspelt arm name across thirty rows is one problem, not thirty.
    final byValue = <String, List<int>>{};
    for (final i in rowIndexes) {
      final v = widget.rawRows[i].valuesByColumn[column] ?? '';
      byValue.putIfAbsent(v, () => []).add(i);
    }

    final canBulkMapArm =
        column == BulkImportColumn.category &&
        widget.onBulkMapArm != null &&
        widget.arms.isNotEmpty;

    return _Group(
      title: bulkImportFieldLabel(column),
      count: rowIndexes.length,
      tone: Sel.danger,
      open: _isOpen('col:${column.name}'),
      onToggle: () => _toggle('col:${column.name}'),
      children: [
        for (final entry in byValue.entries)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SelSpace.x4,
              SelSpace.x1,
              SelSpace.x4,
              SelSpace.x2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.key.isEmpty ? '(empty)' : '"${entry.key}"',
                        style: SelType.small.copyWith(color: Sel.ink),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${entry.value.length} '
                      '${entry.value.length == 1 ? "row" : "rows"}',
                      style: SelType.small,
                    ),
                  ],
                ),
                const SizedBox(height: SelSpace.x1),
                Wrap(
                  spacing: SelSpace.x1,
                  runSpacing: SelSpace.x1,
                  children: [
                    for (final i in entry.value.take(12))
                      _RowChip(
                        label: '${widget.rawRows[i].sheetRowNumber}',
                        onTap: () => widget.onJumpToRow(i),
                      ),
                    if (entry.value.length > 12)
                      Text('+${entry.value.length - 12}', style: SelType.small),
                  ],
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
      ],
    );
  }

  Widget _rowLevelGroup(Map<int, BulkImportIssue> rowLevel) {
    final unanswered = [
      for (final i in rowLevel.keys)
        if (!widget.acknowledgedSheetRows.contains(
          widget.rawRows[i].sheetRowNumber,
        ))
          widget.rawRows[i].sheetRowNumber,
    ];

    return _Group(
      title: 'Possible duplicates',
      count: rowLevel.length,
      tone: Sel.warning,
      open: _isOpen('rowlevel'),
      onToggle: () => _toggle('rowlevel'),
      // Answering the same question forty times is the tedium this rebuild
      // exists to remove — when they are all intentional, say so once.
      trailing: unanswered.isEmpty
          ? null
          : SelButton(
              label: 'Keep all',
              kind: SelButtonKind.quiet,
              onPressed: widget.busy
                  ? null
                  : () {
                      for (final sheetRow in unanswered) {
                        widget.onAcknowledgeDuplicate(sheetRow);
                      }
                    },
            ),
      children: [
        for (final entry in rowLevel.entries)
          _DuplicateRow(
            sheetRow: widget.rawRows[entry.key].sheetRowNumber,
            message: entry.value.message ?? widget.issueLabel(entry.value.code),
            acknowledged: widget.acknowledgedSheetRows.contains(
              widget.rawRows[entry.key].sheetRowNumber,
            ),
            busy: widget.busy,
            onTap: () => widget.onJumpToRow(entry.key),
            onKeep: () => widget.onAcknowledgeDuplicate(
              widget.rawRows[entry.key].sheetRowNumber,
            ),
            onRemove: () => widget.onRemoveRow(entry.key),
          ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.count,
    required this.tone,
    required this.open,
    required this.onToggle,
    required this.children,
    this.trailing,
  });

  final String title;
  final int count;
  final Color tone;
  final bool open;
  final VoidCallback onToggle;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SelSpace.x4,
              vertical: SelSpace.x3,
            ),
            child: Row(
              children: [
                Icon(
                  open ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                  size: 13,
                  color: Sel.ash,
                ),
                const SizedBox(width: SelSpace.x2),
                Container(
                  height: 6,
                  width: 6,
                  decoration: BoxDecoration(
                    color: tone,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: SelSpace.x2),
                Expanded(
                  child: Text(
                    title,
                    style: SelType.small.copyWith(color: Sel.ink),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text('$count', style: SelType.small),
                if (trailing != null) ...[
                  const SizedBox(width: SelSpace.x2),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
        if (open) ...children,
        const Divider(height: 1, color: Sel.borderMuted),
      ],
    );
  }
}

class _FixPreview extends StatelessWidget {
  const _FixPreview({required this.proposal, required this.onTap});

  final AutoFixProposal proposal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SelSpace.x4,
          vertical: SelSpace.x1,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 30,
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

class _RowChip extends StatelessWidget {
  const _RowChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: SelSpace.x2,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: Sel.border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label, style: SelType.small.copyWith(color: Sel.soot)),
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
    return PopupMenuButton<PartnershipArm>(
      enabled: !busy,
      color: Sel.card,
      onSelected: onPick,
      itemBuilder: (context) => [
        for (final a in arms)
          PopupMenuItem<PartnershipArm>(
            value: a,
            height: 36,
            child: Text(a.name, style: SelType.small.copyWith(color: Sel.ink)),
          ),
      ],
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
            Text('Map all to…', style: SelType.small.copyWith(color: Sel.ink)),
            const SizedBox(width: SelSpace.x2),
            const Icon(LucideIcons.chevronDown, size: 12, color: Sel.ash),
          ],
        ),
      ),
    );
  }
}

/// A suspected duplicate: keep it or drop it, but say which.
class _DuplicateRow extends StatelessWidget {
  const _DuplicateRow({
    required this.sheetRow,
    required this.message,
    required this.acknowledged,
    required this.busy,
    required this.onTap,
    required this.onKeep,
    required this.onRemove,
  });

  final int sheetRow;
  final String message;
  final bool acknowledged;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onKeep;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SelSpace.x4,
          vertical: SelSpace.x2,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                '$sheetRow',
                style: SelType.small.copyWith(color: Sel.ash),
              ),
            ),
            Expanded(
              child: Text(
                message,
                style: SelType.small.copyWith(color: Sel.ink),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (acknowledged)
              const Icon(LucideIcons.check, size: 13, color: Sel.success)
            else ...[
              SelButton(
                label: 'Keep',
                kind: SelButtonKind.quiet,
                onPressed: busy ? null : onKeep,
              ),
              SelButton(
                label: 'Drop',
                kind: SelButtonKind.quiet,
                onPressed: busy ? null : onRemove,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
