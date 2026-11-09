import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons/lucide_icons.dart';

import '../../../design/seline.dart';
import '../../arms/domain/partnership_arm.dart';
import '../../fellowships/fellowship_match.dart';
import '../../partners/domain/partner.dart';
import 'bulk_import_autofix.dart';
import 'bulk_import_columns.dart';
import 'bulk_import_grid.dart' show describeIssue, columnForIssue;
import 'bulk_import_mapping.dart' show bulkImportFieldLabel;
import 'bulk_import_models.dart';

/// Where a row stands, which decides the tab it shows under.
enum ReviewTab { all, needYou, worthALook, ready, leftOut }

/// Check the rows, as on the canvas.
///
/// The rows that need something are listed with what is wrong written under
/// each, and the row in hand is opened on the right with its choices. Every
/// change goes through the same callbacks as the full sheet, so the import
/// re-checks itself exactly as it did before.
class BulkImportReview extends StatefulWidget {
  const BulkImportReview({
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
    required this.knownFellowships,
    required this.onEditCell,
    required this.onApplyFixes,
    required this.onKeepRow,
    required this.onDropRow,
    required this.onUndoDecision,
    required this.onBulkMapArm,
    required this.onBulkResolveFellowship,
    required this.onPickPartner,
  });

  final List<BulkRawRow> rawRows;
  final List<BulkResolvedRow> resolved;
  final List<BulkImportColumn> columns;
  final List<PartnershipArm> arms;
  final bool dayFirst;
  final bool busy;
  final String Function(double) money;
  final Set<int> keptSheetRows;
  final Set<int> droppedSheetRows;
  final List<String> knownFellowships;
  final void Function(int rowIndex, BulkImportColumn column, String value)
  onEditCell;
  final void Function(List<AutoFixProposal> proposals) onApplyFixes;
  final void Function(int sheetRow) onKeepRow;
  final void Function(int sheetRow) onDropRow;
  final void Function(int sheetRow) onUndoDecision;
  final Future<void> Function(List<String> sourceTexts, PartnershipArm arm)
  onBulkMapArm;
  final Future<void> Function(
    List<String> sourceTexts,
    String target, {
    required bool create,
  })
  onBulkResolveFellowship;

  /// Opens the partner search; null when nothing was chosen.
  final Future<Partner?> Function() onPickPartner;

  @override
  State<BulkImportReview> createState() => _BulkImportReviewState();
}

class _BulkImportReviewState extends State<BulkImportReview> {
  /// Null until the reader picks one: opens on Need you when anything
  /// does, otherwise on every row.
  ReviewTab? _picked;
  int? _open;

  /// The row card moved to the edge of the screen, picture-in-picture style.
  bool _aside = false;

  bool _isDuplicate(BulkResolvedRow r) => r.issues.any(
    (i) =>
        i.code == BulkImportIssueCode.duplicateInFile ||
        i.code == BulkImportIssueCode.duplicateInDatabase,
  );

  ReviewTab _tabOf(int i) {
    final r = widget.resolved[i];
    if (widget.droppedSheetRows.contains(r.sheetRowNumber)) {
      return ReviewTab.leftOut;
    }
    if (r.isBlocking ||
        (_isDuplicate(r) && !widget.keptSheetRows.contains(r.sheetRowNumber))) {
      return ReviewTab.needYou;
    }
    final open = r.issues.where(
      (x) =>
          !(widget.keptSheetRows.contains(r.sheetRowNumber) &&
              (x.code == BulkImportIssueCode.duplicateInFile ||
                  x.code == BulkImportIssueCode.duplicateInDatabase)),
    );
    return open.isEmpty ? ReviewTab.ready : ReviewTab.worthALook;
  }

  BulkImportIssue? _mainIssue(BulkResolvedRow r) {
    if (r.issues.isEmpty) return null;
    return r.issues.firstWhere(
      (i) => i.severity == BulkImportSeverity.error,
      orElse: () => r.issues.first,
    );
  }

  String _say(BulkImportIssue i) => i.message ?? describeIssue(i.code).title;

  String _raw(int i, BulkImportColumn c) =>
      (widget.rawRows[i].valuesByColumn[c] ?? '').trim();

  @override
  Widget build(BuildContext context) {
    final n = widget.resolved.length;
    final tabs = [for (var i = 0; i < n; i++) _tabOf(i)];
    int count(ReviewTab t) =>
        t == ReviewTab.all ? n : tabs.where((x) => x == t).length;
    final tab =
        _picked ??
        (tabs.contains(ReviewTab.needYou) ? ReviewTab.needYou : ReviewTab.all);
    final shown = [
      for (var i = 0; i < n; i++)
        if (tab == ReviewTab.all || tabs[i] == tab) i,
    ];
    final settle = [
      for (var i = 0; i < n; i++)
        if (tabs[i] == ReviewTab.needYou) i,
    ];
    var open = _open;
    if (open == null || open >= n) {
      open = settle.isNotEmpty
          ? settle.first
          : (shown.isEmpty ? null : shown.first);
    }

    final list = SelCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelCountTabs<ReviewTab>(
            selected: tab,
            onSelect: (t) => setState(() => _picked = t),
            tabs: [
              for (final t in ReviewTab.values) (t, _tabLabels[t]!, count(t)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Text(
              switch (tab) {
                    ReviewTab.needYou =>
                      'Rows that need a decision before they can come in. Choose one to open it on the right.',
                    ReviewTab.worthALook =>
                      'Rows that can come in as they are, with something worth a look.',
                    ReviewTab.ready => 'Rows ready to come in.',
                    ReviewTab.leftOut =>
                      'Rows left out. They will not come in.',
                    ReviewTab.all => 'Every row in the sheet.',
                  } +
                  (MediaQuery.sizeOf(context).width >= 980
                      ? '  ·  J and K: next and previous  ·  ]: move the card aside'
                      : ''),
              style: SelType.small,
            ),
          ),
          ..._clusters(),
          _HeadRow(),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.all(SelSpace.x6),
              child: Text(
                tab == ReviewTab.needYou
                    ? 'Nothing needs you. Every row is settled.'
                    : 'No rows here.',
                textAlign: TextAlign.center,
                style: SelType.bodySm,
              ),
            ),
          for (final i in shown)
            _ReviewRow(
              index: i,
              row: widget.resolved[i],
              raw: widget.rawRows[i],
              tab: tabs[i],
              issue: _mainIssue(widget.resolved[i]),
              say: _say,
              open: i == open,
              arms: widget.arms,
              hasArmColumn: widget.columns.contains(BulkImportColumn.category),
              money: widget.money,
              busy: widget.busy,
              onOpen: () => setState(() => _open = i),
              onEditCell: widget.onEditCell,
            ),
        ],
      ),
    );

    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (open != null) _decision(open, settle),
        if (settle.length > 1) ...[
          const SizedBox(height: SelSpace.x4),
          _stillToSettle(settle, open),
        ],
        ..._tidy(),
      ],
    );

    void step(int by) {
      if (settle.isEmpty) return;
      final at = settle.indexOf(open ?? -1);
      setState(
        () => _open =
            settle[((at < 0 ? 0 : at) + by + settle.length) % settle.length],
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 980) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                list,
                const SizedBox(height: SelSpace.x4),
                side,
              ],
            ),
          );
        }
        // A laptop: the rows take the screen and the row card floats at the
        // right like picture-in-picture. Moved aside, it leaves a flap on
        // the edge that says how many rows still need you.
        final fixes = _fixes;
        final card = _FloatingCard(
          decision: open == null
              ? null
              : _decision(open, settle, floating: true),
          folds: [
            if (settle.length > 1)
              (
                'Still to settle',
                settle.length - 1,
                _stillToSettle(settle, open, bare: true),
              ),
            if (fixes.isNotEmpty)
              (
                'Tidy up',
                fixes.fold<int>(0, (s, g) => s + g.count),
                _tidyBody(fixes, bare: true),
              ),
          ],
        );
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyJ): () => step(1),
            const SingleActivator(LogicalKeyboardKey.keyK): () => step(-1),
            const SingleActivator(LogicalKeyboardKey.bracketRight): () =>
                setState(() => _aside = !_aside),
          },
          child: Focus(
            autofocus: true,
            child: Stack(
              children: [
                Positioned.fill(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(right: _aside ? 96 : 372),
                    child: list,
                  ),
                ),
                if (!_aside)
                  Positioned(
                    top: 0,
                    right: 0,
                    bottom: 6,
                    width: 356,
                    child: card,
                  )
                else
                  Positioned(
                    right: 0,
                    top: (c.maxHeight - 170) / 2,
                    child: _Flap(
                      needYou: settle.length,
                      onTap: () => setState(() => _aside = false),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------ decision

  Widget _decision(int i, List<int> settle, {bool floating = false}) {
    final r = widget.resolved[i];
    final sheetRow = r.sheetRowNumber;
    final issue = _mainIssue(r);
    final dropped = widget.droppedSheetRows.contains(sheetRow);
    final kept = widget.keptSheetRows.contains(sheetRow);
    final pos = settle.indexOf(i);
    final name = r.fullName.isEmpty ? 'this row' : r.fullName;

    final partnerIssue =
        issue != null &&
        const {
          BulkImportIssueCode.possibleDuplicatePartner,
          BulkImportIssueCode.ambiguousName,
          BulkImportIssueCode.ambiguousPhone,
          BulkImportIssueCode.nameMismatch,
          BulkImportIssueCode.memberIdNotFound,
          BulkImportIssueCode.memberIdConflict,
          BulkImportIssueCode.missingName,
        }.contains(issue.code);
    final duplicate = _isDuplicate(r);
    final fixColumn = issue == null ? null : columnForIssue(issue.code);

    final title = dropped
        ? 'Row $sheetRow is left out'
        : issue == null
        ? 'Row $sheetRow is ready'
        : duplicate && !kept
        ? (issue.code == BulkImportIssueCode.duplicateInDatabase
              ? 'Is this already in Pillr?'
              : 'Is this the same as another row?')
        : partnerIssue
        ? 'Who is $name?'
        : describeIssue(issue.code).title;

    final children = <Widget>[];
    if (dropped) {
      children.add(Text('It will not come in.', style: SelType.bodySm));
      children.add(const SizedBox(height: SelSpace.x4));
      children.add(
        SelButton(
          label: 'Bring row $sheetRow back',
          onPressed: widget.busy ? null : () => widget.onUndoDecision(sheetRow),
        ),
      );
    } else if (duplicate && !kept) {
      children.add(Text(_say(issue!), style: SelType.bodySm));
      children.add(const SizedBox(height: SelSpace.x4));
      children.add(
        SelButton.cyan(
          label: 'It is new, bring it in',
          expanded: true,
          onPressed: widget.busy ? null : () => widget.onKeepRow(sheetRow),
        ),
      );
      children.add(const SizedBox(height: SelSpace.x2));
      children.add(
        SelButton(
          label: 'Leave row $sheetRow out',
          expanded: true,
          onPressed: widget.busy ? null : () => widget.onDropRow(sheetRow),
        ),
      );
    } else if (partnerIssue) {
      children.add(Text(_say(issue), style: SelType.bodySm));
      children.add(const SizedBox(height: SelSpace.x4));
      children.add(
        _Choice(
          title: 'Someone already on the book',
          body: 'Search by name, member ID or phone',
          onTap: widget.busy
              ? null
              : () async {
                  final p = await widget.onPickPartner();
                  if (p == null) return;
                  // A member ID matches exactly; a name is the fallback.
                  if (widget.columns.contains(BulkImportColumn.memberId) &&
                      p.memberId.isNotEmpty) {
                    widget.onEditCell(i, BulkImportColumn.memberId, p.memberId);
                  }
                  widget.onEditCell(i, BulkImportColumn.name, p.fullName);
                },
        ),
      );
      if (issue.severity == BulkImportSeverity.warning) {
        children.add(
          _Choice(
            title: 'Keep it as it is',
            body: issue.code == BulkImportIssueCode.possibleDuplicatePartner
                ? 'Comes in as a new partner, ${r.fullName}${r.fellowship.isEmpty ? '' : ', ${r.fellowship}'}'
                : 'Comes in as the sheet has it',
            onTap: null,
          ),
        );
      }
    } else if (issue != null &&
        fixColumn != null &&
        fixColumn != BulkImportColumn.category) {
      children.add(Text(_say(issue), style: SelType.bodySm));
      children.add(const SizedBox(height: SelSpace.x3));
      children.add(
        _FixField(
          key: ValueKey('fix-$sheetRow-${fixColumn.name}'),
          label: bulkImportFieldLabel(fixColumn),
          initial: _raw(i, fixColumn),
          busy: widget.busy,
          onSave: (v) => widget.onEditCell(i, fixColumn, v),
        ),
      );
    } else if (issue != null && fixColumn == BulkImportColumn.category) {
      children.add(Text(_say(issue), style: SelType.bodySm));
      children.add(const SizedBox(height: SelSpace.x3));
      children.add(
        SelSelect<String>(
          value: null,
          hint: Text('Pick an arm', style: SelType.bodyMuted),
          onChanged: widget.busy
              ? null
              : (id) {
                  final arm = widget.arms.where((a) => a.id == id).firstOrNull;
                  if (arm == null) return;
                  final text = _raw(i, BulkImportColumn.category);
                  if (text.isNotEmpty) {
                    widget.onBulkMapArm([text], arm);
                  } else {
                    widget.onEditCell(i, BulkImportColumn.category, arm.name);
                  }
                },
          items: [
            for (final a in widget.arms)
              DropdownMenuItem(value: a.id, child: Text(a.name)),
          ],
        ),
      );
    } else if (issue != null) {
      children.add(Text(_say(issue), style: SelType.bodySm));
    } else {
      children.add(
        Text(
          '${widget.money(r.amountCedis)} to ${r.armName} for ${r.fullName}, ${DateFormat('d MMM y').format(r.dateGiven)}.',
          style: SelType.bodySm,
        ),
      );
    }
    if (!dropped && !(duplicate && !kept)) {
      children.add(const SizedBox(height: SelSpace.x3));
      children.add(
        Align(
          alignment: Alignment.centerLeft,
          child: SelLink(
            label: 'Leave row $sheetRow out',
            onTap: widget.busy ? null : () => widget.onDropRow(sheetRow),
          ),
        ),
      );
    }
    if (kept && duplicate) {
      children.add(const SizedBox(height: SelSpace.x2));
      children.add(
        Align(
          alignment: Alignment.centerLeft,
          child: SelLink(
            label: 'Undo: ask me again',
            onTap: widget.busy ? null : () => widget.onUndoDecision(sheetRow),
          ),
        ),
      );
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Sel.ink,
                borderRadius: BorderRadius.circular(SelRadius.pill),
              ),
              child: Text(
                pos < 0
                    ? 'Row $sheetRow'
                    : floating
                    ? 'Row $sheetRow · ${pos + 1} of ${settle.length}'
                    : 'Row $sheetRow · ${pos + 1} of ${settle.length} to settle',
                style: SelType.small.copyWith(color: Sel.card),
              ),
            ),
            const Spacer(),
            if (settle.length > 1) ...[
              IconButton(
                tooltip: 'Previous',
                icon: const Icon(LucideIcons.arrowUp, size: 16, color: Sel.ink),
                onPressed: () => setState(() {
                  final at = pos < 0 ? 0 : pos;
                  _open = settle[(at - 1 + settle.length) % settle.length];
                }),
              ),
              IconButton(
                tooltip: 'Next',
                icon: const Icon(
                  LucideIcons.arrowDown,
                  size: 16,
                  color: Sel.ink,
                ),
                onPressed: () => setState(() {
                  _open = settle[(pos + 1) % settle.length];
                }),
              ),
            ],
            if (floating)
              _MoveAside(onTap: () => setState(() => _aside = true)),
          ],
        ),
        const SizedBox(height: SelSpace.x3),
        Text(title, style: SelType.subtitle),
        const SizedBox(height: SelSpace.x1),
        Text(
          [
            if (r.fullName.isNotEmpty) r.fullName,
            if (r.fellowship.isNotEmpty) r.fellowship,
            widget.money(r.amountCedis),
            DateFormat('d MMM').format(r.dateGiven),
          ].join(' · '),
          style: SelType.small,
        ),
        const SizedBox(height: SelSpace.x4),
        ...children.where((w) => !(w is Text && w.data == title)),
      ],
    );
    return floating ? body : SelCard(child: body);
  }

  Widget _stillToSettle(List<int> settle, int? open, {bool bare = false}) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!bare) Text('Still to settle', style: SelType.subtitle),
        for (final (n, i)
            in settle.where((x) => x != open).take(5).indexed) ...[
          if (!bare || n > 0)
            const Divider(height: SelSpace.x4, color: Sel.rowLine),
          Row(
            children: [
              const _Mark(kind: ReviewTab.needYou),
              const SizedBox(width: SelSpace.x3),
              Expanded(
                child: Text(
                  'Row ${widget.resolved[i].sheetRowNumber}: ${_say(_mainIssue(widget.resolved[i]) ?? const BulkImportIssue(code: BulkImportIssueCode.duplicateInFile, severity: BulkImportSeverity.warning))}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SelType.bodySm.copyWith(color: Sel.text),
                ),
              ),
              const SizedBox(width: SelSpace.x2),
              SelLink(label: 'Open', onTap: () => setState(() => _open = i)),
            ],
          ),
        ],
      ],
    );
    return bare ? body : SelCard(child: body);
  }

  List<AutoFixGroup> get _fixes =>
      detectAutoFixes(widget.rawRows, dayFirst: widget.dayFirst);

  List<Widget> _tidy() {
    final groups = _fixes;
    if (groups.isEmpty) return const [];
    return [
      const SizedBox(height: SelSpace.x4),
      SelCard(child: _tidyBody(groups)),
    ];
  }

  Widget _tidyBody(List<AutoFixGroup> groups, {bool bare = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!bare)
          Text(
            'Tidy up · ${groups.fold<int>(0, (s, g) => s + g.count)}',
            style: SelType.subtitle,
          ),
        for (final (n, g) in groups.indexed) ...[
          if (!bare || n > 0)
            const Divider(height: SelSpace.x4, color: Sel.rowLine),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '“${g.proposals.first.before}” becomes ${g.proposals.first.after}',
                      style: SelType.bodySm.copyWith(color: Sel.text),
                    ),
                    Text(
                      '${g.label} · ${g.count} ${g.count == 1 ? 'row' : 'rows'}',
                      style: SelType.small,
                    ),
                  ],
                ),
              ),
              SelLink(
                label: 'Apply',
                onTap: widget.busy
                    ? null
                    : () => widget.onApplyFixes(g.proposals),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// One banner per spelling that several rows share: a fellowship that is
  /// not in the book, or an arm name the church does not have.
  List<Widget> _clusters() {
    final fellowships = <String, List<int>>{};
    final armTexts = <String, List<int>>{};
    for (var i = 0; i < widget.resolved.length; i++) {
      final r = widget.resolved[i];
      if (widget.droppedSheetRows.contains(r.sheetRowNumber)) continue;
      for (final x in r.issues) {
        if (x.code == BulkImportIssueCode.unknownFellowship) {
          final t = _raw(i, BulkImportColumn.fellowship);
          if (t.isNotEmpty) fellowships.putIfAbsent(t, () => []).add(i);
        }
        if (x.code == BulkImportIssueCode.armNotFound) {
          final t = _raw(i, BulkImportColumn.category);
          if (t.isNotEmpty) armTexts.putIfAbsent(t, () => []).add(i);
        }
      }
    }
    String rows(List<int> ix) =>
        'Rows ${ix.map((i) => widget.resolved[i].sheetRowNumber).join(', ')}';
    return [
      for (final e in fellowships.entries)
        _Banner(
          title:
              '“${e.key}” on ${e.value.length} ${e.value.length == 1 ? 'row isn’t' : 'rows isn’t'} a fellowship yet',
          body: () {
            final s = suggestSimilarFellowship(e.key, widget.knownFellowships);
            return s == null
                ? rows(e.value)
                : '${rows(e.value)}. Pillr has $s.';
          }(),
          actions: [
            if (suggestSimilarFellowship(e.key, widget.knownFellowships)
                case final s?)
              SelButton(
                label: 'Use $s for all ${e.value.length}',
                onPressed: widget.busy
                    ? null
                    : () => widget.onBulkResolveFellowship(
                        [e.key],
                        s,
                        create: false,
                      ),
              ),
            SelLink(
              label: 'Create “${e.key}”',
              onTap: widget.busy
                  ? null
                  : () => widget.onBulkResolveFellowship(
                      [e.key],
                      e.key,
                      create: true,
                    ),
            ),
          ],
        ),
      for (final e in armTexts.entries)
        _Banner(
          title:
              '“${e.key}” on ${e.value.length} ${e.value.length == 1 ? 'row isn’t' : 'rows isn’t'} one of your arms',
          body:
              '${rows(e.value)}. Point it at an arm; Pillr remembers it next time.',
          actions: [
            SizedBox(
              width: 200,
              child: SelSelect<String>(
                value: null,
                hint: Text('Pick an arm', style: SelType.bodyMuted),
                onChanged: widget.busy
                    ? null
                    : (id) {
                        final arm = widget.arms
                            .where((a) => a.id == id)
                            .firstOrNull;
                        if (arm != null) widget.onBulkMapArm([e.key], arm);
                      },
                items: [
                  for (final a in widget.arms)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
              ),
            ),
          ],
        ),
    ];
  }
}

// ----------------------------------------------------------------- pieces

const _tabLabels = {
  ReviewTab.all: 'All rows',
  ReviewTab.needYou: 'Need you',
  ReviewTab.worthALook: 'Worth a look',
  ReviewTab.ready: 'Ready',
  ReviewTab.leftOut: 'Left out',
};

class _HeadRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget h(
      String t, {
      int flex = 1,
      double? w,
      TextAlign align = TextAlign.left,
    }) {
      final text = Text(t, textAlign: align, style: SelType.small);
      return w == null
          ? Expanded(flex: flex, child: text)
          : SizedBox(width: w, child: text);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Sel.rowLine)),
      ),
      child: Row(
        children: [
          h('', w: 30),
          h('Row', w: 44),
          h('Date', w: 80),
          h('Name', flex: 3),
          h('Fellowship', flex: 2),
          h('Arm', w: 150),
          h('Amount', w: 110, align: TextAlign.right),
        ],
      ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.kind});

  final ReviewTab kind;

  @override
  Widget build(BuildContext context) {
    final (fill, edge, icon, color) = switch (kind) {
      ReviewTab.needYou => (
        Sel.ink,
        Sel.ink,
        LucideIcons.alertCircle,
        Sel.card,
      ),
      ReviewTab.worthALook => (Sel.card, Sel.cyan, LucideIcons.info, Sel.cyan),
      ReviewTab.leftOut => (Sel.track, Sel.track, LucideIcons.minus, Sel.warm),
      _ => (Sel.skyWash, Sel.skyWash, LucideIcons.check, Sel.ink),
    };
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: edge, width: 1.5),
      ),
      child: Icon(icon, size: 12, color: color),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.index,
    required this.row,
    required this.raw,
    required this.tab,
    required this.issue,
    required this.say,
    required this.open,
    required this.arms,
    required this.hasArmColumn,
    required this.money,
    required this.busy,
    required this.onOpen,
    required this.onEditCell,
  });

  final int index;
  final BulkResolvedRow row;
  final BulkRawRow raw;
  final ReviewTab tab;
  final BulkImportIssue? issue;
  final String Function(BulkImportIssue) say;
  final bool open;
  final List<PartnershipArm> arms;
  final bool hasArmColumn;
  final String Function(double) money;
  final bool busy;
  final VoidCallback onOpen;
  final void Function(int rowIndex, BulkImportColumn column, String value)
  onEditCell;

  String _v(BulkImportColumn c) => (raw.valuesByColumn[c] ?? '').trim();

  @override
  Widget build(BuildContext context) {
    final col = issue == null ? null : columnForIssue(issue!.code);
    final dateBad = col == BulkImportColumn.date;
    final amountBad = col == BulkImportColumn.amount;
    final nameBad = col == BulkImportColumn.name && tab == ReviewTab.needYou;
    final text = SelType.bodySm.copyWith(color: Sel.text);
    final armValue = arms.any((a) => a.id == row.armId) ? row.armId : null;

    Widget cell(
      String value, {
      required bool editable,
      required BulkImportColumn c,
      TextAlign align = TextAlign.left,
    }) => editable
        ? _InlineEdit(
            key: ValueKey('${raw.sheetRowNumber}-${c.name}'),
            initial: value,
            align: align,
            busy: busy,
            onSave: (v) => onEditCell(index, c, v),
          )
        : Text(
            value.isEmpty ? '—' : value,
            textAlign: align,
            overflow: TextOverflow.ellipsis,
            style: text,
          );

    return Material(
      color: open ? Sel.skyTint : Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Sel.rowLine)),
          ),
          child: Opacity(
            opacity: tab == ReviewTab.leftOut ? 0.5 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 30,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _Mark(kind: tab),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${raw.sheetRowNumber}',
                        style: SelType.small,
                      ),
                    ),
                    SizedBox(
                      width: 80,
                      child: cell(
                        dateBad
                            ? _v(BulkImportColumn.date)
                            : DateFormat('d MMM').format(row.dateGiven),
                        editable: dateBad,
                        c: BulkImportColumn.date,
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Padding(
                        padding: const EdgeInsets.only(right: SelSpace.x3),
                        child: cell(
                          _v(BulkImportColumn.name),
                          editable: nameBad,
                          c: BulkImportColumn.name,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        row.fellowship.isEmpty
                            ? _v(BulkImportColumn.fellowship)
                            : row.fellowship,
                        overflow: TextOverflow.ellipsis,
                        style: text,
                      ),
                    ),
                    SizedBox(
                      width: 150,
                      child: hasArmColumn && arms.isNotEmpty
                          ? SelSelect<String>(
                              value: armValue,
                              hint: Text(
                                _v(BulkImportColumn.category).isEmpty
                                    ? 'Pick'
                                    : _v(BulkImportColumn.category),
                                style: SelType.bodyMuted,
                              ),
                              onChanged: busy
                                  ? null
                                  : (id) {
                                      final arm = arms
                                          .where((a) => a.id == id)
                                          .firstOrNull;
                                      if (arm != null) {
                                        onEditCell(
                                          index,
                                          BulkImportColumn.category,
                                          arm.name,
                                        );
                                      }
                                    },
                              items: [
                                for (final a in arms)
                                  DropdownMenuItem(
                                    value: a.id,
                                    child: Text(a.name),
                                  ),
                              ],
                            )
                          : Text(row.armName, style: text),
                    ),
                    SizedBox(
                      width: 110,
                      child: cell(
                        amountBad
                            ? _v(BulkImportColumn.amount)
                            : money(row.amountCedis),
                        editable: amountBad,
                        c: BulkImportColumn.amount,
                        align: TextAlign.right,
                      ),
                    ),
                  ],
                ),
                if (issue != null && tab != ReviewTab.ready)
                  Padding(
                    padding: const EdgeInsets.only(left: 74, top: 6),
                    child: Text(
                      say(issue!),
                      style: SelType.small.copyWith(
                        color: Sel.ink,
                        fontWeight: tab == ReviewTab.needYou
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A cell typed into in place; it saves on Enter or when focus leaves.
class _InlineEdit extends StatefulWidget {
  const _InlineEdit({
    super.key,
    required this.initial,
    required this.onSave,
    required this.busy,
    this.align = TextAlign.left,
  });

  final String initial;
  final ValueChanged<String> onSave;
  final bool busy;
  final TextAlign align;

  @override
  State<_InlineEdit> createState() => _InlineEditState();
}

class _InlineEditState extends State<_InlineEdit> {
  late final _c = TextEditingController(text: widget.initial);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _save();
    });
  }

  void _save() {
    if (_c.text.trim() != widget.initial.trim()) widget.onSave(_c.text.trim());
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 36,
    child: TextField(
      controller: _c,
      focusNode: _focus,
      enabled: !widget.busy,
      textAlign: widget.align,
      style: SelType.bodySm.copyWith(color: Sel.text),
      onSubmitted: (_) => _save(),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        filled: true,
        fillColor: Sel.card,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF9ACFF6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Sel.cyan, width: 1.5),
        ),
      ),
    ),
  );
}

/// A field in the decision card with its own Save.
class _FixField extends StatefulWidget {
  const _FixField({
    super.key,
    required this.label,
    required this.initial,
    required this.onSave,
    required this.busy,
  });

  final String label;
  final String initial;
  final ValueChanged<String> onSave;
  final bool busy;

  @override
  State<_FixField> createState() => _FixFieldState();
}

class _FixFieldState extends State<_FixField> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SelField(
        controller: _c,
        label: widget.label,
        onSubmitted: (v) => widget.onSave(v.trim()),
      ),
      const SizedBox(height: SelSpace.x3),
      Align(
        alignment: Alignment.centerLeft,
        child: SelButton.cyan(
          label: 'Use this',
          onPressed: widget.busy ? null : () => widget.onSave(_c.text.trim()),
        ),
      ),
    ],
  );
}

class _Choice extends StatelessWidget {
  const _Choice({required this.title, required this.body, required this.onTap});

  final String title;
  final String body;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: SelSpace.x2),
    child: Material(
      color: Sel.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: onTap == null ? Sel.border : Sel.ink,
          width: onTap == null ? 1 : 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                onTap == null ? LucideIcons.circle : LucideIcons.search,
                size: 16,
                color: Sel.ink,
              ),
              const SizedBox(width: SelSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: SelType.body.copyWith(
                        color: Sel.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(body, style: SelType.small),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.title,
    required this.body,
    required this.actions,
  });

  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
    decoration: const BoxDecoration(
      color: Sel.rowHover,
      border: Border(top: BorderSide(color: Sel.border)),
    ),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: SelSpace.x2,
      spacing: SelSpace.x4,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Mark(kind: ReviewTab.worthALook),
            const SizedBox(width: SelSpace.x3),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: SelType.body.copyWith(
                    color: Sel.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(body, style: SelType.small),
              ],
            ),
          ],
        ),
        Wrap(
          spacing: SelSpace.x3,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: actions,
        ),
      ],
    ),
  );
}

/// "Move aside →|" on the floating card.
class _MoveAside extends StatelessWidget {
  const _MoveAside({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: SelSpace.x1),
    child: Tooltip(
      message: 'Move the card to the edge of the screen (])',
      child: Material(
        color: Sel.skyTint,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Move aside',
                  style: SelType.small.copyWith(
                    color: Sel.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  LucideIcons.arrowRightToLine,
                  size: 14,
                  color: Sel.ink,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// The row card floating at the right of the rows. Its shadow is a flat
/// light-sky edge, never a blur.
class _FloatingCard extends StatelessWidget {
  const _FloatingCard({required this.decision, required this.folds});

  final Widget? decision;

  /// Title, count and what opens under it.
  final List<(String, int, Widget)> folds;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Sel.card,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Sel.skyWash, width: 1.5),
      boxShadow: const [BoxShadow(color: Sel.skyWash, offset: Offset(0, 4))],
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 16),
            child:
                decision ??
                Text('Choose a row to see it here.', style: SelType.bodySm),
          ),
        ),
        for (final (title, count, child) in folds)
          _Fold(title: title, count: count, child: child),
      ],
    ),
  );
}

/// A line at the foot of the floating card that opens to show its list.
class _Fold extends StatefulWidget {
  const _Fold({required this.title, required this.count, required this.child});

  final String title;
  final int count;
  final Widget child;

  @override
  State<_Fold> createState() => _FoldState();
}

class _FoldState extends State<_Fold> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Sel.rowLine)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                children: [
                  Text(
                    widget.title,
                    style: SelType.bodySm.copyWith(
                      color: Sel.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: SelSpace.x2),
                  SelTag('${widget.count}', tone: SelTagTone.waiting),
                  const Spacer(),
                  Icon(
                    _open ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                    size: 16,
                    color: Sel.warm,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_open)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: widget.child,
            ),
          ),
      ],
    ),
  );
}

/// What is left at the edge when the card is moved aside: an arrow, how many
/// rows need you, and Open, in plain words.
class _Flap extends StatelessWidget {
  const _Flap({required this.needYou, required this.onTap});

  final int needYou;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = needYou == 0
        ? 'Open the row card'
        : 'Open the card for the $needYou ${needYou == 1 ? 'row' : 'rows'} that need you';
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: DecoratedBox(
          // The flat light-sky edge sits under the navy, not over it.
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.horizontal(left: Radius.circular(20)),
            boxShadow: [BoxShadow(color: Sel.skyWash, offset: Offset(0, 5))],
          ),
          child: Material(
            color: Sel.ink,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(20),
            ),
            child: InkWell(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(20),
              ),
              onTap: onTap,
              child: Container(
                width: 84,
                padding: const EdgeInsets.fromLTRB(10, 14, 8, 14),
                child: ExcludeSemantics(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Color(0x24FFFFFF),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          LucideIcons.chevronLeft,
                          size: 16,
                          color: Sel.card,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (needYou > 0) ...[
                        Text(
                          '$needYou ${needYou == 1 ? 'row' : 'rows'}',
                          style: SelType.subtitle.copyWith(
                            color: Sel.card,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          needYou == 1 ? 'needs you' : 'need you',
                          style: SelType.small.copyWith(
                            color: SelNavyCard.soft,
                          ),
                        ),
                      ] else
                        Text(
                          'Row card',
                          textAlign: TextAlign.center,
                          style: SelType.small.copyWith(
                            color: Sel.card,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Sel.card,
                          borderRadius: BorderRadius.circular(SelRadius.pill),
                        ),
                        child: Text(
                          'Open',
                          style: SelType.small.copyWith(
                            color: Sel.ink,
                            fontWeight: FontWeight.w800,
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
    );
  }
}
