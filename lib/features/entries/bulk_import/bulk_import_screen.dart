import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:the_pillr/l10n/app_localizations.dart';

import '../../../design/seline.dart';
import '../../../screens/arm_palette.dart';

import '../../../core/notifications/sel_notice.dart';
import '../../../core/navigation/panel_flows.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../activity/activity_log_helper.dart';
import '../../../core/utils/entry_duplicate_utils.dart';
import '../../../core/utils/text_case_utils.dart';
import '../../church/domain/exchange_rates.dart';
import '../../arms/domain/arm_tree.dart';
import '../../arms/domain/partnership_arm.dart';
import '../../arms/providers/arms_providers.dart';
import '../../fellowships/fellowship_match.dart';
import '../../fellowships/fellowship_providers.dart';
import '../../auth/domain/user_church_index.dart' show UserChurchIndex;
import '../../auth/providers/auth_providers.dart';
import '../../church/providers/church_settings_providers.dart';
import '../../partners/domain/partner.dart';
import '../../partners/providers/partners_providers.dart';
import '../domain/partnership_entry.dart';
import '../../periods/domain/partnership_period.dart';
import '../../periods/providers/periods_providers.dart';
import 'bulk_import_autofix.dart';
import 'bulk_import_batches.dart';
import 'bulk_import_columns.dart';
import 'bulk_import_grid.dart';
import 'bulk_import_mapping.dart';
import 'bulk_import_save.dart';
import 'bulk_import_sources.dart';
import 'bulk_import_template.dart';
import 'bulk_import_commit.dart';
import 'bulk_import_drop_zone.dart';
import 'bulk_import_review.dart';
import 'bulk_import_models.dart';
import 'bulk_import_parser.dart';
import 'bulk_import_resolver.dart';
import 'bulk_import_commit_progress.dart';
import 'bulk_import_session_store.dart';
import 'bulk_import_xlsx_pick.dart';
import '../data/entries_repository.dart';
import '../data/similar_entries.dart';
import '../providers/entries_providers.dart';
import '../../../core/errors/plain_error.dart';

/// Column widths shared by header + data rows (avoids toolbar overflow).
/// The four stages of an import.
///
/// The old screen put uploading, reviewing and importing on one scrolling
/// page, so there was no sense of progress and no clear finish line. Naming
/// the stages lets the UI show one decision at a time and say how far in you
/// are.
enum _Step {
  upload('File'),
  columns('Columns'),
  resolve('Check'),
  confirm('Bring in');

  const _Step(this.label);
  final String label;

  static const ordered = [
    _Step.upload,
    _Step.columns,
    _Step.resolve,
    _Step.confirm,
  ];
}

class BulkImportScreen extends ConsumerStatefulWidget {
  const BulkImportScreen({super.key});

  @override
  ConsumerState<BulkImportScreen> createState() => _BulkImportScreenState();
}

class _BulkImportScreenState extends ConsumerState<BulkImportScreen>
    with WidgetsBindingObserver {
  List<BulkRawRow>? _rawRows;
  List<BulkImportIssue> _fileIssues = [];
  List<BulkResolvedRow>? _resolved;
  BulkImportCommitResult? _result;

  bool _parsing = false;
  bool _loadingPartners = false;
  bool _committing = false;
  bool _restoringSession = false;
  String? _error;

  /// Sheet rows confirmed as intentional (not an accidental double-entry).
  final Set<int> _duplicateAcknowledgedSheetRows = {};

  /// Sheet rows set aside. Kept in the grid, greyed out and struck through,
  /// rather than deleted — a decision you cannot take back is one people
  /// hesitate over.
  final Set<int> _droppedSheetRows = {};

  String? _fileName;
  Uint8List? _fileBytes;

  /// The sheet exactly as read, before any interpretation. Kept so the column
  /// mapping step can be revisited without re-uploading.
  List<List<String?>>? _grid;
  BulkImportHeaderDetection? _detection;
  Map<BulkImportColumn, int> _mapping = {};
  _Step _step = _Step.upload;

  /// How to read an ambiguous numeric date. Ghana writes day first, so that
  /// is the default, but the sheet cannot prove it — the grid shows the
  /// reading and lets it be flipped.
  bool _dayFirst = true;

  /// Default currency for sheet amounts unless a row has a Currency column.
  String _importDefaultCurrency = BaseCurrency.code;

  /// Names accepted during this import (Create) before they land on partners.
  final Set<String> _acceptedFellowships = {};

  /// A saved import found on disk, waiting to be resumed or discarded.
  BulkImportPersistedSession? _pendingDraft;

  bool _sessionRestored = false;
  String? _persistUid;
  String? _persistChurchId;
  Timer? _persistDebounce;
  Timer? _resolveDebounce;

  /// Who put the sheet together. Not a Pillr user and not verifiable — a name
  /// typed by whoever is importing, so a figure queried months later has
  /// somebody to ask about it.
  final _preparedBy = TextEditingController();

  List<PartnershipArm>? _cachedArms;
  List<Partner>? _cachedPartners;

  /// Inactive and merged-away partners: not matched against, but used to
  /// follow a merged member ID and to warn before creating a duplicate.
  List<Partner> _cachedInactivePartners = const [];
  List<PartnershipPeriod>? _cachedPeriods;
  PartnershipPeriod? _cachedActivePeriod;
  PartnershipPeriod? _importPeriod;

  /// Step 3 shows the rows to settle; this switches to the whole sheet.
  bool _sheetView = false;

  /// What the last import brought in, kept for the finished screen.
  List<BulkResolvedRow> _resultRows = const [];
  String? _resultFile;
  final Map<String, List<PartnershipEntry>> _duplicateEntryCache = {};
  final Map<int, Partner> _partnerOverrides = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _restorePersistedSession(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _persistDebounce?.cancel();
    _resolveDebounce?.cancel();
    _persistSession();
    _preparedBy.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _persistDebounce?.cancel();
      _persistSession();
    }
  }

  void _cachePersistIds(UserChurchIndex idx) {
    _persistUid ??= idx.uid;
    _persistChurchId ??= idx.churchId;
  }

  void _schedulePersistSession() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 300), () {
      _persistSession();
    });
  }

  Future<void> _persistSession() async {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx != null) _cachePersistIds(idx);
    final uid = _persistUid;
    final churchId = _persistChurchId;
    if (uid == null || churchId == null) return;

    final rows = _rawRows;
    if (rows == null) return;
    if (rows.isEmpty) {
      await BulkImportSessionStore.clear(uid: uid, churchId: churchId);
      return;
    }
    await BulkImportSessionStore.save(
      uid: uid,
      churchId: churchId,
      fileName: _fileName,
      fileBytes: _fileBytes,
      rawRows: rows,
      fileIssues: _fileIssues,
      duplicateAcknowledgedSheetRows: _duplicateAcknowledgedSheetRows,
      mapping: _mapping,
      droppedSheetRows: _droppedSheetRows,
    );
  }

  Future<void> _restorePersistedSession() async {
    if (_sessionRestored) return;
    _sessionRestored = true;
    final idx = await _waitForChurchIndex();
    if (idx == null || !mounted) return;
    _cachePersistIds(idx);
    final saved = await BulkImportSessionStore.load(
      uid: idx.uid,
      churchId: idx.churchId,
    );
    if (saved == null || saved.rawRows.isEmpty || !mounted) return;
    // Offered, not resumed. Silently reopening someone else's half-finished
    // import is how the wrong file gets committed; the choice is one click
    // either way.
    setState(() => _pendingDraft = saved);
  }

  /// Picks the saved draft back up where it was left.
  Future<void> _continueDraft() async {
    final saved = _pendingDraft;
    if (saved == null) return;
    setState(() {
      _pendingDraft = null;
      _restoringSession = true;
      _fileName = saved.fileName;
      _fileBytes = saved.fileBytes;
      _rawRows = saved.rawRows;
      _fileIssues = saved.fileIssues;
      _mapping = saved.mapping.isNotEmpty
          ? Map<BulkImportColumn, int>.from(saved.mapping)
          : _mappingFromRows(saved.rawRows);
      _duplicateAcknowledgedSheetRows
        ..clear()
        ..addAll(saved.duplicateAcknowledgedSheetRows);
      _droppedSheetRows
        ..clear()
        ..addAll(saved.droppedSheetRows);
      _result = null;
      _resolved = null;
      _step = _Step.resolve;
    });
    await _loadPartnersAndResolve();
    if (!mounted) return;
    setState(() => _restoringSession = false);
    selNotice(
      context,
      AppLocalizations.of(context).bulkImportDraftRestored,
      kind: SelNoticeKind.info,
    );
  }

  /// A draft saved before the mapping was persisted still has to show its
  /// columns in a sensible order.
  Map<BulkImportColumn, int> _mappingFromRows(List<BulkRawRow> rows) {
    final seen = <BulkImportColumn>{};
    for (final r in rows) {
      seen.addAll(r.valuesByColumn.keys);
    }
    final ordered = [
      for (final c in bulkImportMappableFields)
        if (seen.contains(c)) c,
    ];
    return {for (var i = 0; i < ordered.length; i++) ordered[i]: i};
  }

  Future<void> _clearDraft(BuildContext context, AppLocalizations l10n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard the saved import?'),
        content: Text(
          'The rows from ${_pendingDraft?.fileName ?? "the saved file"} will be '
          'thrown away. Nothing has been imported yet, so nothing else changes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.bulkImportCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final uid = _persistUid;
    final churchId = _persistChurchId;
    if (uid != null && churchId != null) {
      await BulkImportSessionStore.clear(uid: uid, churchId: churchId);
    }
    if (!mounted) return;
    setState(() => _pendingDraft = null);
  }

  bool get _hasDraftRows => _rawRows != null && _rawRows!.isNotEmpty;

  bool get _isResolvingDraft =>
      _restoringSession ||
      (_hasDraftRows && _resolved == null && (_loadingPartners || _parsing));

  bool _rowHasDuplicateIssue(BulkResolvedRow r) {
    return r.issues.any(
      (i) =>
          i.code == BulkImportIssueCode.duplicateInFile ||
          i.code == BulkImportIssueCode.duplicateInDatabase,
    );
  }

  /// The rows that will be imported — everything not set aside.
  List<BulkResolvedRow> get _liveRows => [
    for (final r in _resolved ?? const <BulkResolvedRow>[])
      if (!_droppedSheetRows.contains(r.sheetRowNumber)) r,
  ];

  /// A suspected duplicate holds up the import until someone says which it
  /// is. Importing money twice is not a warning-level mistake.
  bool _duplicatesFullyAcknowledged() {
    if (_resolved == null) return false;
    for (final r in _liveRows) {
      if (_rowHasDuplicateIssue(r) &&
          !_duplicateAcknowledgedSheetRows.contains(r.sheetRowNumber)) {
        return false;
      }
    }
    return true;
  }

  void _keepRow(int sheetRow) => setState(() {
    _droppedSheetRows.remove(sheetRow);
    _duplicateAcknowledgedSheetRows.add(sheetRow);
  });

  void _dropRow(int sheetRow) => setState(() {
    _duplicateAcknowledgedSheetRows.remove(sheetRow);
    _droppedSheetRows.add(sheetRow);
  });

  void _undoRowDecision(int sheetRow) => setState(() {
    _droppedSheetRows.remove(sheetRow);
    _duplicateAcknowledgedSheetRows.remove(sheetRow);
  });

  int _countNonDuplicateWarnings(List<BulkResolvedRow> rows) {
    var n = 0;
    for (final r in rows) {
      for (final i in r.issues) {
        if (i.severity != BulkImportSeverity.warning) continue;
        if (i.code == BulkImportIssueCode.duplicateInFile ||
            i.code == BulkImportIssueCode.duplicateInDatabase) {
          continue;
        }
        n++;
      }
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;

    if (idx == null || (!idx.isPastor && !idx.isStaff)) {
      return SelPageBody(
        maxWidth: 640,
        children: [SelEmpty(title: l10n.bulkImportAccessDenied, message: '')],
      );
    }
    _cachePersistIds(idx);

    if (_result != null) {
      return SelPageBody(
        children: [_buildResult(context, l10n, _result!)],
      );
    }
    if (_isResolvingDraft) {
      return SelPageBody(
        maxWidth: 720,
        children: [_buildRestoringDraft(context, l10n)],
      );
    }

    if (_step == _Step.resolve &&
        _resolved != null &&
        _resolved!.isNotEmpty &&
        !_loadingPartners) {
      return _buildResolveTakeover(context, l10n, idx);
    }

    return SelPageBody(
      maxWidth: _step == _Step.upload || _step == _Step.columns
          ? double.infinity
          : 900,
      children: [
        Wrap(
          spacing: SelSpace.x3,
          runSpacing: SelSpace.x2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SelButton(
              label: '← Leave import',
              onPressed: _committing
                  ? null
                  : () => context.go('/records/imports'),
            ),
            Text(
              _fileName == null
                  ? 'New import · saved on this device as you go.'
                  : '$_fileName · saved on this device as you go.',
              style: SelType.small,
            ),
            if (_step != _Step.upload)
              SelLink(
                label: 'Start over',
                onTap: _committing ? null : _startOver,
              ),
          ],
        ),
        const SizedBox(height: SelSpace.x4),
        LayoutBuilder(
          builder: (context, c) {
            final title = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  switch (_step) {
                    _Step.upload => 'Bring in a sheet',
                    _Step.columns => 'Match the columns',
                    _Step.resolve => 'Check the rows',
                    _Step.confirm => 'Bring them in',
                  },
                  style: SelType.title,
                ),
                const SizedBox(height: SelSpace.x1),
                Text(
                  _step == _Step.upload || _fileName == null
                      ? 'Turn a month of giving in a spreadsheet into entries, without typing each one'
                      : _detection == null
                      ? _fileName!
                      : '$_fileName · headings found on row ${_detection!.headerRowIndex + 1}',
                  style: SelType.body.copyWith(color: Sel.warm),
                ),
              ],
            );
            if (c.maxWidth < 860) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  title,
                  const SizedBox(height: SelSpace.x4),
                  _StepBar(current: _step),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: title),
                _StepBar(current: _step),
              ],
            );
          },
        ),
        const SizedBox(height: SelSpace.x6),

        if (_error != null) ...[
          _Notice(message: _error!, status: SelStatus.blocked),
          const SizedBox(height: SelSpace.x4),
        ],
        for (final i in _fileIssues) ...[
          _Notice(
            message: i.message ?? _issueLabel(l10n, i.code),
            status: i.severity == BulkImportSeverity.error
                ? SelStatus.blocked
                : SelStatus.pending,
          ),
          const SizedBox(height: SelSpace.x4),
        ],

        switch (_step) {
          _Step.upload => _buildUploadStep(context, l10n),
          _Step.columns => _buildColumnsStep(context, l10n),
          _Step.resolve => _buildResolveStep(context, l10n, idx),
          _Step.confirm => _buildConfirmStep(context, l10n, idx),
        },
      ],
    );
  }

  void _startOver() {
    setState(() {
      _grid = null;
      _detection = null;
      _mapping = {};
      _rawRows = null;
      _resolved = null;
      _fileIssues = const [];
      _fileName = null;
      _fileBytes = null;
      _error = null;
      _duplicateAcknowledgedSheetRows.clear();
      _droppedSheetRows.clear();
      _acceptedFellowships.clear();
      _pendingDraft = null;
      _step = _Step.upload;
    });
  }

  // ---------------------------------------------------------------- step 1
  Widget _buildUploadStep(BuildContext context, AppLocalizations l10n) {
    final draft = _pendingDraft;
    final period = ref.watch(activePeriodProvider);

    final drop = SelCard(
      padding: const EdgeInsets.all(14),
      child: BulkImportDropZone(
        onPick: () => _pickAndParse(context),
        onPaste: () => _pasteRows(context),
        onTemplate: _downloadTemplate,
        loading: _parsing,
        fileName: _fileName,
      ),
    );

    Widget cellText(String t, {bool right = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Text(
        t,
        textAlign: right ? TextAlign.right : TextAlign.left,
        style: SelType.bodySm.copyWith(color: Sel.text),
      ),
    );
    Widget tag(String t, Color fill, Color ink) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(SelRadius.pill),
      ),
      child: Text(t, style: SelType.small.copyWith(color: ink)),
    );
    final looksFor = SelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: SelSpace.x1,
            children: [
              Text('What Pillr looks for', style: SelType.subtitle),
              Text(
                "Column names don't have to match. You'll confirm them next.",
                style: SelType.small,
              ),
            ],
          ),
          const SizedBox(height: SelSpace.x3),
          Table(
            border: const TableBorder(
              horizontalInside: BorderSide(color: Sel.rowLine),
            ),
            children: [
              TableRow(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Sel.rowLine)),
                ),
                children: [
                  for (final h in const ['Date', 'Name', 'Fellowship', 'Arm'])
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Text(h, style: SelType.small),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Text('Amount', textAlign: TextAlign.right, style: SelType.small),
                  ),
                ],
              ),
              TableRow(
                children: [
                  cellText('1 Nov 2026'),
                  cellText('Ama Boateng'),
                  cellText('Bethel'),
                  cellText('Tithe'),
                  cellText('500.00', right: true),
                ],
              ),
              TableRow(
                children: [
                  cellText('01/11/26'),
                  cellText('Kofi Mensah'),
                  cellText('Bethel'),
                  cellText('Building'),
                  cellText('GHS 1,250', right: true),
                ],
              ),
            ],
          ),
          const SizedBox(height: SelSpace.x3),
          Wrap(
            spacing: SelSpace.x2,
            runSpacing: SelSpace.x2,
            children: [
              tag('Needed: Date · Name · Amount', Sel.ink, Sel.card),
              tag('Arm and fellowship: in the sheet, or one for every row', Sel.skyWash, Sel.ink),
              tag('Optional: Phone · Notes', Sel.track, Sel.text),
            ],
          ),
        ],
      ),
    );

    final forEveryRow = SelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('For every row', style: SelType.subtitle),
          const SizedBox(height: SelSpace.x3),
          Text('Period', style: SelType.bodyMedium),
          const SizedBox(height: SelSpace.x2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            decoration: BoxDecoration(
              color: Sel.track,
              borderRadius: BorderRadius.circular(SelRadius.pill),
            ),
            child: Text(
              (_importPeriod ?? period)?.name ?? 'No active period',
              style: SelType.body.copyWith(color: Sel.text),
            ),
          ),
          const SizedBox(height: SelSpace.x1),
          Text(
            'The active period. You can pick another on the last step.',
            style: SelType.small,
          ),
          const SizedBox(height: SelSpace.x4),
          Text('Plain amounts are in', style: SelType.bodyMedium),
          const SizedBox(height: SelSpace.x2),
          SelSelect<String>(
            value: _importDefaultCurrency,
            onChanged: _parsing
                ? null
                : (v) {
                    if (v == null) return;
                    setState(() => _importDefaultCurrency = v);
                  },
            items: [
              for (final code in SelectableCurrency.all)
                DropdownMenuItem(
                  value: code,
                  child: Text(SelectableCurrency.label(code)),
                ),
            ],
          ),
          const SizedBox(height: SelSpace.x1),
          Text(
            'Used when an amount has no ₵, \$, £ or currency code.',
            style: SelType.small,
          ),
          const SizedBox(height: SelSpace.x4),
          SelField(
            controller: _preparedBy,
            label: 'Prepared by',
            hint: 'e.g. Bethel finance desk',
          ),
          const SizedBox(height: SelSpace.x1),
          Text('Optional. Kept with the import so it can be traced.', style: SelType.small),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (draft != null) ...[
          _DraftCard(
            fileName: draft.fileName,
            rowCount: draft.rawRows.length,
            savedAt: draft.savedAt,
            onContinue: _continueDraft,
            onClear: () => _clearDraft(context, l10n),
          ),
          const SizedBox(height: SelSpace.x4),
        ],
        LayoutBuilder(
          builder: (context, c) {
            final main = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [drop, const SizedBox(height: SelSpace.x4), looksFor],
            );
            final side = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [forEveryRow, const _RecentImports()],
            );
            if (c.maxWidth < 900) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [main, const SizedBox(height: SelSpace.x4), side],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: main),
                const SizedBox(width: SelSpace.x4),
                SizedBox(width: 300, child: side),
              ],
            );
          },
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- step 2
  Widget _buildColumnsStep(BuildContext context, AppLocalizations l10n) {
    final detection = _detection;
    final grid = _grid;
    if (detection == null || grid == null) return const SizedBox.shrink();

    final missing = BulkImportHeaderDetection.required
        .where((c) => !_mapping.containsKey(c))
        .toList();
    final first = detection.headerRowIndex + 1;
    final dataRows = [
      for (var r = first; r < grid.length; r++)
        if (grid[r].any((v) => (v ?? '').trim().isNotEmpty)) r,
    ];

    // A few real values per column, so the reader can tell which is which
    // without going back to the spreadsheet.
    String samples(int col) {
      final seen = <String>[];
      for (final r in dataRows) {
        if (col < grid[r].length) {
          final v = (grid[r][col] ?? '').trim();
          if (v.isNotEmpty && !seen.contains(v)) seen.add(v);
        }
        if (seen.length == 3) break;
      }
      return seen.isEmpty ? '—' : seen.join(' · ');
    }

    String valueAt(int row, BulkImportColumn field) {
      final col = _mapping[field];
      if (col == null || col >= grid[row].length) return '';
      return (grid[row][col] ?? '').trim();
    }

    final columns = [
      for (var c = 0; c < detection.labels.length; c++)
        if (detection.labels[c].isNotEmpty) c,
    ];

    final table = SelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: SelSpace.x1,
            children: [
              Text('${columns.length} columns in your sheet', style: SelType.subtitle),
              Text(
                'Pillr matched ${_mapping.length}. Change any that are wrong.',
                style: SelType.small,
              ),
            ],
          ),
          const SizedBox(height: SelSpace.x3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text('Your column', style: SelType.small)),
                Expanded(flex: 4, child: Text('First values', style: SelType.small)),
                SizedBox(width: 190, child: Text('Goes to', style: SelType.small)),
              ],
            ),
          ),
          const SizedBox(height: SelSpace.x2),
          for (final c in columns) ...[
            const Divider(height: 1, color: Sel.rowLine),
            _ColumnRow(
              header: detection.labels[c],
              sample: samples(c),
              value: _fieldForColumn(c),
              onChanged: (field) => _assignColumn(c, field),
            ),
          ],
        ],
      ),
    );

    Widget need(String label, BulkImportColumn field, {bool required = true}) {
      final col = _mapping[field];
      final ok = col != null;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ok ? Sel.skyWash : (required ? Sel.ink : Sel.track),
                shape: BoxShape.circle,
              ),
              child: Icon(
                ok ? LucideIcons.check : (required ? LucideIcons.alertCircle : LucideIcons.minus),
                size: 13,
                color: ok ? Sel.ink : (required ? Sel.card : Sel.warm),
              ),
            ),
            const SizedBox(width: SelSpace.x3),
            Expanded(
              child: Text(
                label,
                style: SelType.body.copyWith(
                  color: Sel.ink,
                  fontWeight: ok ? FontWeight.w500 : FontWeight.w700,
                ),
              ),
            ),
            Flexible(
              child: Text(
                ok
                    ? 'from “${detection.labels[col]}”'
                    : required
                    ? 'Pick its column'
                    : 'Not in the sheet',
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: SelType.small,
              ),
            ),
          ],
        ),
      );
    }

    final needs = SelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('What every entry needs', style: SelType.subtitle),
          const SizedBox(height: SelSpace.x1),
          need('Date', BulkImportColumn.date),
          const Divider(height: 1, color: Sel.rowLine),
          need('Name', BulkImportColumn.name),
          const Divider(height: 1, color: Sel.rowLine),
          need('Amount', BulkImportColumn.amount),
          const Divider(height: 1, color: Sel.rowLine),
          need('Fellowship', BulkImportColumn.fellowship, required: false),
          const Divider(height: 1, color: Sel.rowLine),
          need('Arm', BulkImportColumn.category, required: false),
          if (!_mapping.containsKey(BulkImportColumn.category)) ...[
            const SizedBox(height: SelSpace.x1),
            Text(
              'Without an arm column, you pick the arm for each row on the next step.',
              style: SelType.small,
            ),
          ],
        ],
      ),
    );

    final preview = SelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: SelSpace.x1,
            children: [
              Text("The first rows, as they'll come in", style: SelType.subtitle),
              Text('Updates as you change a column', style: SelType.small),
            ],
          ),
          const SizedBox(height: SelSpace.x3),
          Table(
            columnWidths: const {0: FixedColumnWidth(70)},
            border: const TableBorder(horizontalInside: BorderSide(color: Sel.rowLine)),
            children: [
              TableRow(
                children: [
                  for (final h in const ['Row', 'Date', 'Name', 'Fellowship', 'Arm'])
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Text(h, style: SelType.small),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Text('Amount', textAlign: TextAlign.right, style: SelType.small),
                  ),
                ],
              ),
              for (final r in dataRows.take(3))
                TableRow(
                  children: [
                    for (final v in [
                      '${r + 1}',
                      valueAt(r, BulkImportColumn.date),
                      valueAt(r, BulkImportColumn.name),
                      valueAt(r, BulkImportColumn.fellowship),
                      valueAt(r, BulkImportColumn.category),
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        child: Text(
                          v.isEmpty ? '—' : v,
                          style: SelType.bodySm.copyWith(color: Sel.text),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      child: Text(
                        valueAt(r, BulkImportColumn.amount).isEmpty
                            ? '—'
                            : valueAt(r, BulkImportColumn.amount),
                        textAlign: TextAlign.right,
                        style: SelType.bodySm.copyWith(color: Sel.text),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: SelSpace.x3),
            _Notice(
              status: SelStatus.blocked,
              message:
                  'Still needed: '
                  '${missing.map(bulkImportFieldLabel).join(', ')}. '
                  'Pick the column that holds each.',
            ),
          ],
          const Divider(height: SelSpace.x8, color: Sel.border),
          Row(
            children: [
              SelLink(
                label: 'Back',
                onTap: () => setState(() => _step = _Step.upload),
              ),
              const Spacer(),
              SelButton.cyan(
                label: 'Check ${dataRows.length} ${dataRows.length == 1 ? 'row' : 'rows'}',
                loading: _parsing,
                onPressed: missing.isEmpty ? _applyMappingAndResolve : null,
              ),
            ],
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) => c.maxWidth < 900
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [table, const SizedBox(height: SelSpace.x4), needs],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: table),
                    const SizedBox(width: SelSpace.x4),
                    SizedBox(width: 320, child: needs),
                  ],
                ),
        ),
        const SizedBox(height: SelSpace.x4),
        preview,
      ],
    );
  }

  BulkImportColumn? _fieldForColumn(int columnIndex) {
    for (final e in _mapping.entries) {
      if (e.value == columnIndex) return e.key;
    }
    return null;
  }

  void _assignColumn(int columnIndex, BulkImportColumn? field) {
    setState(() {
      // A field maps to exactly one column, so assigning it here releases it
      // from wherever it was.
      _mapping.removeWhere((k, v) => v == columnIndex);
      if (field != null) _mapping[field] = columnIndex;
    });
  }

  // ---------------------------------------------------------------- step 3
  /// The sheet, full screen.
  ///
  /// Reviewing an import inside a 900px column meant scrolling a list of
  /// problems with no sight of the data they referred to. This is the whole
  /// sheet at once, with the problems docked beside it, because the fix is
  /// almost always obvious once you can see the row.
  Widget _buildResolveTakeover(
    BuildContext context,
    AppLocalizations l10n,
    UserChurchIndex idx,
  ) {
    final resolved = _resolved!;
    final arms =
        ref.watch(armsStreamProvider).valueOrNull ?? const <PartnershipArm>[];

    // Sheet order, so the grid reads like the file it came from.
    final columns = _mapping.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    final live = _liveRows;
    final blocking = live.any((r) => r.isBlocking);
    final duplicatesPending = !_duplicatesFullyAcknowledged();
    final money = ref.watch(churchMoneyFormatProvider);

    // Law → pixels (check the sheet):
    // Fitts → Close / Back / Continue stay 44px.
    // Tesler → shell rail + account cluster are gone; issues start closed.
    // Pareto → the grid takes leftover viewport.
    // Jakob → fullscreen editor; Close returns to Records.
    // Goal-gradient → Continue stays last in the footer.
    // Aesthetic-usability → 12px inset, no 64px empty headroom.
    // Hick → 20px title, one line of meta.
    // Working memory → one surface.
    // Occam → hide chrome instead of a collapse toggle.
    // Doherty → hide is instant; no entrance motion.
    // Serial position → title left, Continue right.
    // Zeigarnik → "N things to fix" stays on the sheet.
    // Peak-end / Von Restorff / Postel's / Miller extras: N/A — review tool.
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            SelSpace.x3,
            SelSpace.x3,
            SelSpace.x3,
            SelSpace.x3,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // One line on a laptop: Leave, the title and file, the steps.
              // The page fills the screen, so every row of header it saves is
              // a row of the sheet on a 768-tall screen.
              if (compact) ...[
                Wrap(
                  spacing: SelSpace.x3,
                  runSpacing: SelSpace.x2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SelButton(
                      label: '← Leave',
                      onPressed: _committing ? null : () => context.go('/records/imports'),
                    ),
                    _StepBar(current: _step),
                  ],
                ),
                const SizedBox(height: SelSpace.x2),
                _sheetTitle(compact: compact, resolved: resolved, live: live),
              ] else
                Row(
                  children: [
                    SelButton(
                      label: '← Leave',
                      onPressed: _committing ? null : () => context.go('/records/imports'),
                    ),
                    const SizedBox(width: SelSpace.x4),
                    Expanded(child: _sheetTitle(compact: compact, resolved: resolved, live: live)),
                    _buildCompactSheetCurrencySelector(),
                    if (_loadingPartners)
                      const Padding(
                        padding: EdgeInsets.only(right: SelSpace.x3),
                        child: PillrLoader(size: 18),
                      ),
                    _StepBar(current: _step),
                  ],
                ),
              SizedBox(height: compact ? SelSpace.x2 : SelSpace.x3),
              if (_error != null) ...[
                _Notice(message: _error!, status: SelStatus.blocked),
                const SizedBox(height: SelSpace.x4),
              ],
              // Anything the parser decided about the file itself — rows it left
              // out, headers it could not place. Leaving a row out silently is
              // how an importer loses someone's giving without anyone noticing.
              for (final i in _fileIssues) ...[
                _Notice(
                  message: i.message ?? _issueLabel(l10n, i.code),
                  status: i.severity == BulkImportSeverity.error
                      ? SelStatus.blocked
                      : SelStatus.pending,
                ),
                const SizedBox(height: SelSpace.x4),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Saved on this device as you go.',
                      style: SelType.small,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SelLink(label: 'Start over', onTap: _committing ? null : _startOver),
                  const SizedBox(width: SelSpace.x4),
                  SelLink(
                    label: _sheetView ? 'Show the rows to settle' : 'See the whole sheet',
                    onTap: () => setState(() => _sheetView = !_sheetView),
                  ),
                ],
              ),
              const SizedBox(height: SelSpace.x2),
              Expanded(
                child: _sheetView
                    ? BulkImportGrid(
                  rawRows: _rawRows ?? const [],
                  resolved: resolved,
                  columns: _gridColumns(columns),
                  arms: arms,
                  dayFirst: _dayFirst,
                  busy: _loadingPartners || _committing,
                  money: (v) => v == v.roundToDouble()
                      ? money(v).replaceAll(RegExp(r'\.00$'), '')
                      : money(v),
                  keptSheetRows: _duplicateAcknowledgedSheetRows,
                  droppedSheetRows: _droppedSheetRows,
                  onEditCell: _editRawCell,
                  onApplyFixes: _applyFixes,
                  onDayFirstChanged: (v) => setState(() => _dayFirst = v),
                  onKeepRow: _keepRow,
                  onDropRow: _dropRow,
                  onUndoDecision: _undoRowDecision,
                  onBulkMapArm: _bulkMapArm,
                  knownFellowships: [
                    ...ref.watch(knownFellowshipsProvider),
                    ..._acceptedFellowships,
                  ],
                  onBulkResolveFellowship: _bulkResolveFellowship,
                )
                    : BulkImportReview(
                          rawRows: _rawRows ?? const [],
                          resolved: resolved,
                          columns: _gridColumns(columns),
                          arms: arms,
                          dayFirst: _dayFirst,
                          busy: _loadingPartners || _committing,
                          money: money,
                          keptSheetRows: _duplicateAcknowledgedSheetRows,
                          droppedSheetRows: _droppedSheetRows,
                          knownFellowships: [
                            ...ref.watch(knownFellowshipsProvider),
                            ..._acceptedFellowships,
                          ],
                          onEditCell: _editRawCell,
                          onApplyFixes: _applyFixes,
                          onKeepRow: _keepRow,
                          onDropRow: _dropRow,
                          onUndoDecision: _undoRowDecision,
                          onBulkMapArm: _bulkMapArm,
                          onBulkResolveFellowship: _bulkResolveFellowship,
                          onPickPartner: () => showPartnerPickerPanel(
                            context,
                            churchId: idx.churchId,
                            uid: idx.uid,
                          ),
                        ),
              ),
              const SizedBox(height: SelSpace.x3),
              Builder(
                builder: (context) {
                  final ready = live.where((r) => !r.isBlocking).toList();
                  final total = ready.fold<double>(0, (s, r) => s + r.amountCedis);
                  final needYou = live.where((r) => r.isBlocking).length;
                  final note = blocking
                      ? '$needYou ${needYou == 1 ? 'row needs' : 'rows need'} you'
                      : duplicatesPending
                      ? 'Say keep or leave out for the rows that might already be in Pillr'
                      : live.isEmpty
                      ? 'Every row was left out'
                      : 'Nothing is saved until you bring them in';
                  final canGo = !(blocking || duplicatesPending || _loadingPartners || live.isEmpty);
                  return Container(
                    padding: const EdgeInsets.fromLTRB(24, 10, 10, 10),
                    decoration: BoxDecoration(
                      color: Sel.ink,
                      borderRadius: BorderRadius.circular(SelRadius.card),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${ready.length} ready · ${money(total)}',
                          style: SelType.body.copyWith(
                            color: Sel.card,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: SelSpace.x4),
                        Expanded(
                          child: Text(
                            note,
                            overflow: TextOverflow.ellipsis,
                            style: SelType.bodySm.copyWith(color: const Color(0xFFC9DEF3)),
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _step = _Step.columns),
                          child: Text('Back', style: SelType.button.copyWith(color: Sel.card)),
                        ),
                        const SizedBox(width: SelSpace.x2),
                        Material(
                          color: canGo ? Sel.card : const Color(0xFF2A5884),
                          shape: const StadiumBorder(),
                          child: InkWell(
                            customBorder: const StadiumBorder(),
                            onTap: canGo ? () => setState(() => _step = _Step.confirm) : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                              child: Text(
                                'Continue',
                                style: SelType.button.copyWith(
                                  color: canGo ? Sel.ink : const Color(0xFF9DB8D3),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }


  Widget _sheetTitle({
    required bool compact,
    required List<BulkResolvedRow> resolved,
    required List<BulkResolvedRow> live,
  }) {
    final meta = live.length == resolved.length
        ? '${_fileName ?? "Your file"} · ${resolved.length} rows · nothing is saved until you bring them in'
        : '${_fileName ?? "Your file"} · ${live.length} of ${resolved.length} rows coming in';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Check the rows', style: SelType.title.copyWith(fontSize: 20, height: 1.2)),
        Text(
          meta,
          style: SelType.small,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }


  /// Writes one cell back to the raw sheet and re-runs resolution.
  ///
  /// Everything downstream — arm matching, partner matching, duplicate
  /// detection — depends on the raw values, so a corrected name has to be
  /// able to turn a new partner into an existing one.
  Future<void> _editRawCell(
    int rowIndex,
    BulkImportColumn column,
    String value,
  ) async {
    final rows = _rawRows;
    if (rows == null || rowIndex < 0 || rowIndex >= rows.length) return;
    final row = rows[rowIndex];
    final values = Map<BulkImportColumn, String>.from(row.valuesByColumn);
    values[column] = value;
    setState(() {
      _rawRows = List<BulkRawRow>.from(rows)
        ..[rowIndex] = BulkRawRow(
          sheetRowNumber: row.sheetRowNumber,
          valuesByColumn: values,
        );
      _duplicateAcknowledgedSheetRows.remove(row.sheetRowNumber);
    });
    // The cache is keyed by partner and holds what Firestore already has for
    // them. Typing in the sheet cannot change that, so there is nothing to
    // invalidate — and clearing it here cost one query per distinct partner,
    // sequentially, after every edit.
    _scheduleReResolve(checkDuplicates: _columnAffectsDuplicates(column));
    _schedulePersistSession();
  }

  bool _columnAffectsDuplicates(BulkImportColumn column) => switch (column) {
    BulkImportColumn.amount ||
    BulkImportColumn.date ||
    BulkImportColumn.category ||
    BulkImportColumn.name ||
    BulkImportColumn.contact ||
    BulkImportColumn.memberId ||
    BulkImportColumn.currency => true,
    _ => false,
  };

  void _scheduleReResolve({bool checkDuplicates = true}) {
    _resolveDebounce?.cancel();
    _resolveDebounce = Timer(const Duration(milliseconds: 350), () {
      _reResolve(checkDuplicates: checkDuplicates);
    });
  }

  Future<void> _applyFixes(List<AutoFixProposal> proposals) async {
    final rows = _rawRows;
    if (rows == null || proposals.isEmpty) return;
    setState(() => _rawRows = applyAutoFixes(rows, proposals));
    // Sheet values only — see _editRawCell.
    _scheduleReResolve();
    _schedulePersistSession();
  }

  Widget _buildResolveStep(
    BuildContext context,
    AppLocalizations l10n,
    UserChurchIndex idx,
  ) {
    if (_loadingPartners) {
      return SelCard(
        child: Column(
          children: [
            Text(l10n.bulkImportLoadingPartners, style: SelType.bodyMuted),
            const SizedBox(height: SelSpace.x4),
            const SelSkeletonRows(count: 4),
          ],
        ),
      );
    }
    final resolved = _resolved;
    if (resolved == null) return const SizedBox.shrink();
    if (resolved.isEmpty) {
      return SelCard(
        child: SelEmpty(
          title: l10n.bulkImportNoRowsInImport,
          message: 'Go back and check the column mapping.',
          actionLabel: 'Back to columns',
          onAction: () => setState(() => _step = _Step.columns),
        ),
      );
    }

    final live = _liveRows;
    final blocking = live.any((r) => r.isBlocking);
    final duplicatesPending = !_duplicatesFullyAcknowledged();
    final otherWarnings = _countNonDuplicateWarnings(resolved);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildIssueReview(context, l10n, resolved),
        const SizedBox(height: SelSpace.x6),
        Row(
          children: [
            SelButton(
              label: 'Back',
              kind: SelButtonKind.quiet,
              onPressed: () => setState(() => _step = _Step.columns),
            ),
            const Spacer(),
            if (blocking)
              Padding(
                padding: const EdgeInsets.only(right: SelSpace.x3),
                child: Text(l10n.bulkImportBlocking, style: SelType.small),
              )
            else if (duplicatesPending)
              Padding(
                padding: const EdgeInsets.only(right: SelSpace.x3),
                child: Text(
                  'Confirm the possible duplicates before continuing.',
                  style: SelType.small,
                ),
              )
            else if (otherWarnings > 0)
              Padding(
                padding: const EdgeInsets.only(right: SelSpace.x3),
                child: Text(
                  '$otherWarnings ${otherWarnings == 1 ? "warning" : "warnings"} '
                  '— you can continue.',
                  style: SelType.small,
                ),
              ),
            SelButton.cyan(
              label: 'Continue',
              onPressed: blocking || duplicatesPending
                  ? null
                  : () => setState(() => _step = _Step.confirm),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- step 4
  List<BulkImportColumn> _gridColumns(
    List<MapEntry<BulkImportColumn, int>> mapped,
  ) {
    final cols = mapped.map((e) => e.key).toList();
    if (cols.contains(BulkImportColumn.currency)) return cols;
    final amountIdx = cols.indexOf(BulkImportColumn.amount);
    if (amountIdx >= 0) {
      return [
        ...cols.sublist(0, amountIdx + 1),
        BulkImportColumn.currency,
        ...cols.sublist(amountIdx + 1),
      ];
    }
    return [...cols, BulkImportColumn.currency];
  }

  void _syncRowCurrencies() {
    final rows = _rawRows;
    if (rows == null) return;
    _rawRows = [
      for (final row in rows)
        () {
          final v = Map<BulkImportColumn, String>.from(row.valuesByColumn);
          final amountStr = v[BulkImportColumn.amount]?.trim() ?? '';
          final fromAmount = parseAmountCell(amountStr).currency;
          final fromColumn = parseCurrencyCode(v[BulkImportColumn.currency]);
          final code = fromAmount ?? fromColumn ?? _importDefaultCurrency;
          v[BulkImportColumn.currency] = code;
          return BulkRawRow(
            sheetRowNumber: row.sheetRowNumber,
            valuesByColumn: v,
          );
        }(),
    ];
  }

  Widget _buildCompactSheetCurrencySelector() {
    return Tooltip(
      message: 'Default for plain amounts without \$ € £ or a currency code',
      child: Padding(
        padding: const EdgeInsets.only(right: SelSpace.x3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Default', style: SelType.small.copyWith(color: Sel.ash)),
            const SizedBox(width: SelSpace.x2),
            SizedBox(
              width: 76,
              child: SelSelect<String>(
                value: _importDefaultCurrency,
                expanded: false,
                onChanged: _committing || _loadingPartners
                    ? null
                    : (v) async {
                        if (v == null) return;
                        setState(() => _importDefaultCurrency = v);
                        _syncRowCurrencies();
                        _scheduleReResolve();
                      },
                items: [
                  for (final code in SelectableCurrency.all)
                    DropdownMenuItem(value: code, child: Text(code)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmStep(
    BuildContext context,
    AppLocalizations l10n,
    UserChurchIndex idx,
  ) {
    if (_resolved == null) return const SizedBox.shrink();
    final resolved = _liveRows;
    final period = ref.watch(activePeriodProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Builder(
          builder: (context) {
            final sum = summarize(resolved, viewerIsStaff: idx.isStaff);
            final money = ref.watch(churchMoneyFormatProvider);
            Widget fig(String k, String v) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(k, style: SelType.small),
                Text(v, style: SelType.subtitle.copyWith(fontWeight: FontWeight.w800)),
              ],
            );
            return SelCard(
              child: Wrap(
                spacing: SelSpace.x10,
                runSpacing: SelSpace.x4,
                children: [
                  fig('Giving to bring in', money(sum.totalAmount)),
                  fig('Rows', '${sum.totalRows}'),
                  fig('Partners already on the book', '${sum.existingPartners}'),
                  fig('New partners', '${sum.newPartners}'),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: SelSpace.x4),
        SelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Everything checks out', style: SelType.subtitle),
              const SizedBox(height: SelSpace.x2),
              Text(
                idx.isStaff
                    ? 'These entries will be submitted for a pastor to review.'
                    : 'These entries will be recorded against the period you pick below.',
                style: SelType.bodyMuted,
              ),
              const SizedBox(height: SelSpace.x4),
              SelSelect<String>(
                value: (_importPeriod ?? period)?.id,
                label: 'Period',
                onChanged: (id) {
                  if (id == null) return;
                  final periods = _cachedPeriods ?? const <PartnershipPeriod>[];
                  PartnershipPeriod? chosen;
                  for (final p in periods) {
                    if (p.id == id) chosen = p;
                  }
                  chosen ??= period;
                  if (chosen == null) return;
                  setState(() {
                    _importPeriod = chosen;
                    _resolved = _resolved
                        ?.map(
                          (r) => r.copyWith(
                            periodId: chosen!.id,
                            periodName: chosen.name,
                          ),
                        )
                        .toList();
                  });
                },
                items: [
                  for (final p
                      in _cachedPeriods ??
                          (period == null
                              ? const <PartnershipPeriod>[]
                              : [period]))
                    DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
              ),
              const SizedBox(height: SelSpace.x2),
              Text(
                'Every row in this file lands in '
                '${(_importPeriod ?? period)?.name ?? "the active period"}. '
                'You can move the whole import afterwards if this is wrong.',
                style: SelType.small,
              ),
              const SizedBox(height: SelSpace.x4),
              SizedBox(
                width: 360,
                child: SelField(
                  controller: _preparedBy,
                  label: 'Prepared by (optional)',
                  hint: 'Who put this sheet together',
                ),
              ),
              const SizedBox(height: SelSpace.x2),
              Text(
                'Recorded against the import so it can be traced later. You '
                'are saved as the person who uploaded it.',
                style: SelType.small,
              ),
            ],
          ),
        ),
        const SizedBox(height: SelSpace.x4),
        Container(
          padding: const EdgeInsets.fromLTRB(24, 10, 10, 10),
          decoration: BoxDecoration(
            color: Sel.ink,
            borderRadius: BorderRadius.circular(SelRadius.card),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  idx.isStaff
                      ? 'They go to the queue for a pastor to approve.'
                      : 'They count as soon as they are in.',
                  style: SelType.bodySm.copyWith(color: const Color(0xFFC9DEF3)),
                ),
              ),
              TextButton(
                onPressed: _committing
                    ? null
                    : () => setState(() => _step = _Step.resolve),
                child: Text('Back', style: SelType.button.copyWith(color: Sel.card)),
              ),
              const SizedBox(width: SelSpace.x2),
              Material(
                color: Sel.card,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: _committing
                      ? null
                      : () => _commit(context, idx.churchId, idx.isPastor),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                    child: _committing
                        ? const PillrLoader(size: 18)
                        : Text(
                            'Bring in ${resolved.length} '
                            '${resolved.length == 1 ? "entry" : "entries"}',
                            style: SelType.button.copyWith(color: Sel.ink),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIssueReview(
    BuildContext context,
    AppLocalizations l10n,
    List<BulkResolvedRow> rows,
  ) {
    final byCode = <BulkImportIssueCode, List<int>>{};
    final severityOf = <BulkImportIssueCode, BulkImportSeverity>{};
    for (var i = 0; i < rows.length; i++) {
      for (final issue in rows[i].issues) {
        byCode.putIfAbsent(issue.code, () => []).add(i);
        if (severityOf[issue.code] != BulkImportSeverity.error) {
          severityOf[issue.code] = issue.severity;
        }
      }
    }

    final codes = byCode.keys.toList()
      ..sort((a, b) {
        final sa = severityOf[a] == BulkImportSeverity.error ? 0 : 1;
        final sb = severityOf[b] == BulkImportSeverity.error ? 0 : 1;
        if (sa != sb) return sa - sb;
        return byCode[b]!.length.compareTo(byCode[a]!.length);
      });

    final clean = rows.where((r) => r.issues.isEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (codes.isNotEmpty) ...[
          SelPanel(
            title: 'Needs attention',
            subtitle: '${rows.length - clean.length} of ${rows.length} rows',
            contentPadding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < codes.length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: Sel.border),
                  _IssueGroup(
                    code: codes[i],
                    severity: severityOf[codes[i]]!,
                    label: _issueLabel(l10n, codes[i]),
                    rowIndices: byCode[codes[i]]!,
                    rows: rows,
                    fmtAmount: fmtAmount,
                    busy: _loadingPartners || _committing,
                    onReviewRow: (idx) => _editRow(context, l10n, idx),
                    onRemoveRow: (idx) => _confirmRemoveRow(context, l10n, idx),
                    onBulkMapArm: _bulkMapArm,
                    onBulkResolveFellowship: _bulkResolveFellowship,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: SelSpace.x4),
        ],
        _CleanRowsPanel(rows: clean, fmtAmount: fmtAmount),
      ],
    );
  }

  /// Applies one arm to every row whose arm cell holds any of [sourceTexts],
  /// then re-resolves so the issue clears everywhere at once.
  Future<void> _bulkMapArm(List<String> sourceTexts, PartnershipArm arm) async {
    final raw = _rawRows;
    if (raw == null) return;
    final needles = sourceTexts.map((t) => t.trim().toLowerCase()).toSet();
    var changed = 0;
    for (var i = 0; i < raw.length; i++) {
      final v = Map<BulkImportColumn, String>.from(raw[i].valuesByColumn);
      final current = (v[BulkImportColumn.category] ?? '').trim().toLowerCase();
      if (!needles.contains(current)) continue;
      v[BulkImportColumn.category] = arm.name;
      raw[i] = BulkRawRow(
        sheetRowNumber: raw[i].sheetRowNumber,
        valuesByColumn: v,
      );
      changed++;
    }
    if (changed == 0) return;

    // Remember the decision so the same wording resolves by itself next time.
    // Best-effort: a failure here must not cost the user the mapping they
    // just applied, so it is caught and ignored.
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx != null) {
      for (final spelling in needles) {
        try {
          await ref
              .read(armsRepositoryProvider)
              .rememberArmAlias(
                churchId: idx.churchId,
                armId: arm.id,
                alias: spelling,
              );
        } catch (_) {
          // Non-fatal: the mapping still applies to this import.
        }
      }
    }

    await _reResolve();
    _schedulePersistSession();
  }

  Future<void> _bulkResolveFellowship(
    List<String> sourceTexts,
    String target, {
    required bool create,
  }) async {
    final label = TextCaseUtils.toTitleCase(target);
    if (label.isEmpty) return;

    if (create) {
      _acceptedFellowships.add(label);
      final idx = ref.read(userChurchIndexProvider).valueOrNull;
      if (idx != null) {
        final catalog =
            ref.read(churchSettingsProvider).valueOrNull?.fellowshipNames ??
            const [];
        final partners =
            ref.read(partnersStreamProvider(false)).valueOrNull ?? const [];
        try {
          await ref
              .read(fellowshipOpsProvider)
              .create(
                churchId: idx.churchId,
                name: label,
                catalog: catalog,
                partnerFellowships: partners.map((p) => p.fellowship),
              );
          try {
            await logPillrActivity(
              ref,
              churchId: idx.churchId,
              action: 'fellowship.create',
              entityType: 'fellowship',
              entitySnapshot: {'name': label, 'source': 'import'},
            );
          } catch (_) {}
        } catch (_) {
          // Staff cannot write church settings. The name still counts
          // for this import via _acceptedFellowships.
        }
      }
    }

    final raw = _rawRows;
    if (raw == null) return;
    final needles = sourceTexts.map((t) => t.trim().toLowerCase()).toSet();
    var changed = 0;
    for (var i = 0; i < raw.length; i++) {
      final v = Map<BulkImportColumn, String>.from(raw[i].valuesByColumn);
      final current = (v[BulkImportColumn.fellowship] ?? '')
          .trim()
          .toLowerCase();
      if (!needles.contains(current)) continue;
      if (fellowshipNamesMatch(v[BulkImportColumn.fellowship] ?? '', label)) {
        continue;
      }
      v[BulkImportColumn.fellowship] = label;
      raw[i] = BulkRawRow(
        sheetRowNumber: raw[i].sheetRowNumber,
        valuesByColumn: v,
      );
      changed++;
    }
    if (changed == 0 && !create) return;

    await _reResolve();
    _schedulePersistSession();
  }

  String fmtAmount(double v) {
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toStringAsFixed(2);
  }

  Widget _buildRestoringDraft(BuildContext context, AppLocalizations l10n) {
    return SelCard(
      clip: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: SelSpace.x8,
          horizontal: SelSpace.x6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: PillrLoader(size: 20),
            ),
            const SizedBox(height: SelSpace.x4),
            Text(
              l10n.bulkImportRestoringDraft,
              textAlign: TextAlign.center,
              style: SelType.body.copyWith(fontWeight: FontWeight.w600),
            ),
            if (_fileName != null && _fileName!.isNotEmpty) ...[
              const SizedBox(height: SelSpace.x2),
              Text(
                _fileName!,
                textAlign: TextAlign.center,
                style: SelType.small.copyWith(color: Sel.warm),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResult(
    BuildContext context,
    AppLocalizations l10n,
    BulkImportCommitResult r,
  ) {
    final money = ref.watch(churchMoneyFormatProvider);
    final me = ref.watch(userChurchIndexProvider).valueOrNull;
    final waiting = r.entriesCreated - r.entriesApproved;
    final title = r.incomplete
        ? 'The import stopped partway'
        : waiting > 0
        ? '${r.entriesCreated} ${r.entriesCreated == 1 ? 'entry is' : 'entries are'} in the queue'
        : '${r.entriesCreated} ${r.entriesCreated == 1 ? 'entry' : 'entries'} brought in';

    // What came in, by arm, from the rows that were brought in.
    final came = _resultRows;
    final byArm = <String, double>{};
    for (final row in came) {
      byArm[row.armName] = (byArm[row.armName] ?? 0) + row.amountCedis;
    }
    final arms = byArm.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = byArm.values.fold<double>(0, (s, v) => s + v);
    const tones = [Sel.ink, Sel.sky, Sel.skyWash, Sel.border];
    final partners = came.map((x) => x.partnerId ?? x.fullName).toSet().length;

    Widget line(bool ok, String head, String body) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ok ? Sel.skyWash : Sel.card,
              shape: BoxShape.circle,
              border: Border.all(color: ok ? Sel.skyWash : Sel.cyan, width: 1.5),
            ),
            child: Icon(
              ok ? LucideIcons.check : LucideIcons.info,
              size: 12,
              color: ok ? Sel.ink : Sel.cyan,
            ),
          ),
          const SizedBox(width: SelSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  head,
                  style: SelType.body.copyWith(color: Sel.ink, fontWeight: FontWeight.w700),
                ),
                if (body.isNotEmpty) Text(body, style: SelType.bodySm),
              ],
            ),
          ),
        ],
      ),
    );

    final lines = <Widget>[
      line(
        true,
        '${r.entriesCreated} ${r.entriesCreated == 1 ? 'row' : 'rows'} came in',
        waiting > 0
            ? 'Waiting for a pastor, like entries typed one by one'
            : 'Approved, and already counted in the totals',
      ),
      if (r.partnersCreated > 0)
        line(
          true,
          '${r.partnersCreated} new ${r.partnersCreated == 1 ? 'partner' : 'partners'}',
          'Added to the partner book from this sheet',
        ),
      if (r.rowsSkipped > 0 && r.errors.isEmpty)
        line(false, '${r.rowsSkipped} ${r.rowsSkipped == 1 ? 'row' : 'rows'} left out', ''),
      for (final e in r.errors) line(false, 'Left out', e),
    ];

    final giving = SelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: SelSpace.x3,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Giving brought in', style: SelType.small),
                  Text(money(total), style: SelType.hero.copyWith(fontSize: 36)),
                  Text(
                    'from $partners ${partners == 1 ? 'partner' : 'partners'}'
                    '${r.partnersCreated > 0 ? ', ${r.partnersCreated} of them new' : ''}',
                    style: SelType.bodySm,
                  ),
                ],
              ),
              Wrap(
                spacing: SelSpace.x2,
                runSpacing: SelSpace.x2,
                children: [
                  if (waiting > 0 && (me?.isPastor ?? false))
                    SelButton.cyan(
                      label: 'Review in the queue',
                      onPressed: () => context.go('/queue'),
                    ),
                  SelButton(
                    label: 'View this import',
                    onPressed: () => context.go('/records?import=${r.batchId}'),
                  ),
                ],
              ),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: SelSpace.x6),
            ClipRRect(
              borderRadius: BorderRadius.circular(SelRadius.pill),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    for (var k = 0; k < arms.length; k++)
                      Expanded(
                        flex: (1000 * arms[k].value / total).round().clamp(1, 1000),
                        child: Container(
                          margin: EdgeInsets.only(right: k == arms.length - 1 ? 0 : 2),
                          color: tones[k.clamp(0, tones.length - 1)],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: SelSpace.x3),
            Wrap(
              spacing: SelSpace.x4,
              runSpacing: SelSpace.x1,
              children: [
                for (var k = 0; k < arms.length; k++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 10, height: 10, color: tones[k.clamp(0, tones.length - 1)]),
                      const SizedBox(width: 6),
                      Text(
                        '${arms[k].key} ${money(arms[k].value)}',
                        style: SelType.small.copyWith(color: Sel.ink),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );

    final happened = SelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('What happened to every row', style: SelType.subtitle),
          for (var k = 0; k < lines.length; k++) ...[
            if (k > 0) const Divider(height: 1, color: Sel.rowLine),
            lines[k],
          ],
        ],
      ),
    );

    final wrong = SelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Brought in the wrong sheet?', style: SelType.subtitle),
          const SizedBox(height: SelSpace.x2),
          Text(
            waiting > 0
                ? 'Undo takes the entries still waiting back out. Nothing has been approved yet, so no totals change. You can also clear the whole import.'
                : 'Clear the import to take every entry it created back out of the totals. Nothing is deleted.',
            style: SelType.bodySm,
          ),
          const SizedBox(height: SelSpace.x4),
          Align(
            alignment: Alignment.centerLeft,
            child: SelButton(
              label: 'Undo it from Imports',
              onPressed: () => context.go('/records/imports'),
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SelButton(
            label: 'Back to Imports',
            onPressed: () => context.go('/records/imports'),
          ),
        ),
        const SizedBox(height: SelSpace.x4),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.end,
          runSpacing: SelSpace.x3,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: SelType.title),
                const SizedBox(height: SelSpace.x1),
                Text(
                  '${_resultFile ?? 'Your sheet'} · brought in by ${ref.watch(churchUserProfileProvider).valueOrNull?.fullName ?? 'you'} just now',
                  style: SelType.body.copyWith(color: Sel.warm),
                ),
              ],
            ),
            const _StepBar(current: _Step.confirm, done: true),
          ],
        ),
        const SizedBox(height: SelSpace.x6),
        LayoutBuilder(
          builder: (context, c) {
            final main = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [giving, const SizedBox(height: SelSpace.x4), happened],
            );
            if (c.maxWidth < 900) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [main, const SizedBox(height: SelSpace.x4), wrong],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: main),
                const SizedBox(width: SelSpace.x4),
                SizedBox(width: 320, child: wrong),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _pickAndParse(BuildContext context) async {
    final l10n = AppLocalizations.of(context);

    if (_hasDraftRows) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.bulkImportReplaceConfirmTitle),
          content: Text(l10n.bulkImportReplaceConfirmMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.bulkImportCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.bulkImportReplaceConfirmAction),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    final picked = await pickBulkImportXlsx();
    if (picked == null || !mounted) return;

    final nameLower = picked.name.toLowerCase();
    if (nameLower.endsWith('.xlsm')) {
      setState(() => _error = l10n.bulkImportNoMacros);
      return;
    }
    final isCsv = isCsvFileName(picked.name);
    if (!isCsv && !nameLower.endsWith('.xlsx')) {
      setState(() => _error = l10n.bulkImportNeedXlsx);
      return;
    }

    setState(() {
      _error = null;
      _parsing = true;
    });
    try {
      final grid = isCsv
          ? parseCsvGrid(utf8.decode(picked.bytes, allowMalformed: true))
          : readFirstXlsxSheet(picked.bytes);
      _adoptGrid(grid, fileName: picked.name, bytes: picked.bytes);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '${l10n.bulkImportParseError}. ${plainError(e)}';
        _parsing = false;
      });
    }
  }

  /// Takes a freshly read sheet and moves to the column step.
  ///
  /// Parsing is deliberately deferred until the user has confirmed the column
  /// mapping — that is the whole point of the step. Guessing first and asking
  /// afterwards is what produced sheets full of empty amounts.
  void _adoptGrid(
    List<List<String?>> grid, {
    required String fileName,
    Uint8List? bytes,
  }) {
    final detection = detectBulkImportHeaders(grid);
    if (!mounted) return;
    setState(() {
      _grid = grid;
      _detection = detection;
      _mapping = Map<BulkImportColumn, int>.from(detection.mapping);
      _fileName = fileName;
      _fileBytes = bytes;
      _rawRows = null;
      _resolved = null;
      _result = null;
      _fileIssues = const [];
      _duplicateAcknowledgedSheetRows.clear();
      _acceptedFellowships.clear();
      _parsing = false;
      _step = _Step.columns;
    });
  }

  /// Applies the confirmed mapping and resolves, then moves to Resolve.
  Future<void> _applyMappingAndResolve() async {
    final grid = _grid;
    final detection = _detection;
    if (grid == null || detection == null) return;

    setState(() {
      _error = null;
      _parsing = true;
    });
    final parsed = parseBulkImportGridWithMapping(
      grid,
      headerRowIndex: detection.headerRowIndex,
      mapping: _mapping,
    );
    if (!mounted) return;
    if (parsed.rows.isEmpty) {
      setState(() {
        _error = AppLocalizations.of(context).bulkImportNoRows;
        _fileIssues = parsed.fileIssues;
        _parsing = false;
      });
      return;
    }
    setState(() {
      _rawRows = parsed.rows;
      _fileIssues = parsed.fileIssues;
      _resolved = null;
      _parsing = false;
      _step = _Step.resolve;
    });
    await _loadPartnersAndResolve();
    await _persistSession();
  }

  /// Paste path: a block of cells copied straight out of a spreadsheet.
  Future<void> _pasteRows(BuildContext context) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => SelDialog(
        title: 'Paste from a spreadsheet',
        subtitle:
            'Select the rows in Excel or Google Sheets, including the header '
            'row, copy them, and paste here.',
        width: 620,
        scrollable: false,
        actions: [
          SelButton(
            label: 'Cancel',
            kind: SelButtonKind.quiet,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          SelButton.cyan(
            label: 'Use these rows',
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
        child: SelField(
          controller: controller,
          hint: 'DATE\tNAME\tAMOUNT\n2026-03-04\tAma Boateng\t500',
          maxLines: 10,
          autofocus: true,
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final text = controller.text.trim();
    if (text.isEmpty) return;
    final grid = parsePastedGrid(text);
    if (grid.length < 2) {
      setState(
        () => _error = 'Paste at least a header row and one row of data.',
      );
      return;
    }
    _adoptGrid(grid, fileName: 'Pasted rows');
  }

  /// Downloads a starter sheet listing this church's own arms.
  Future<void> _downloadTemplate() async {
    final arms = ref.read(armsStreamProvider).valueOrNull ?? const [];
    final churchName = ref.read(churchNameProvider);
    try {
      await saveTextFile(
        fileName: importTemplateFileName(churchName),
        contents: buildImportTemplateCsv(arms: arms),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save the template. ${plainError(e)}');
    }
  }

  /// [userChurchIndexProvider] can still be [AsyncLoading] right after parse — wait briefly.
  Future<UserChurchIndex?> _waitForChurchIndex() async {
    for (var i = 0; i < 120; i++) {
      final async = ref.read(userChurchIndexProvider);
      final idx = async.valueOrNull;
      if (idx != null) return idx;
      if (async.hasError) return null;
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    return ref.read(userChurchIndexProvider).valueOrNull;
  }

  Future<void> _ensureImportContext(UserChurchIndex idx) async {
    _cachedArms ??= await ref
        .read(armsRepositoryProvider)
        .fetchArms(idx.churchId);
    if (_cachedPartners == null || _cachedActivePeriod == null) {
      final periods = await ref
          .read(periodsRepositoryProvider)
          .fetchPeriods(idx.churchId);
      _cachedPeriods = periods;
      try {
        _cachedActivePeriod = periods.firstWhere((p) => p.isActive);
      } catch (_) {
        _cachedActivePeriod = null;
      }
      _importPeriod ??= _cachedActivePeriod;
      final all = await ref
          .read(partnersRepositoryProvider)
          .fetchAllPartners(idx.churchId, includeInactive: true);
      _cachedPartners = [for (final p in all) if (p.isActive) p];
      _cachedInactivePartners = [for (final p in all) if (!p.isActive) p];
    }
  }

  Future<void> _loadPartnersAndResolve() async {
    if (_rawRows == null) return;
    setState(() => _loadingPartners = true);
    final idx = await _waitForChurchIndex();
    if (idx == null) {
      if (!mounted) return;
      setState(() {
        _loadingPartners = false;
        _error = AppLocalizations.of(context).bulkImportChurchIndexMissing;
      });
      return;
    }
    _cachePersistIds(idx);
    _cachedArms = null;
    _cachedPartners = null;
    _cachedActivePeriod = null;
    _cachedPeriods = null;
    _importPeriod = null;
    _duplicateEntryCache.clear();
    _partnerOverrides.clear();
    try {
      await _resolveImport(idx, checkDuplicates: true, persist: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPartners = false;
        _error = plainError(e);
      });
    }
  }

  Future<void> _resolveImport(
    UserChurchIndex idx, {
    required bool checkDuplicates,
    bool persist = false,
    bool showLoading = false,
  }) async {
    if (_rawRows == null) return;
    if (showLoading) setState(() => _loadingPartners = true);
    await _ensureImportContext(idx);
    if (!mounted) return;
    setState(_syncRowCurrencies);
    final resolved = _applyPartnerOverrides(
      resolveBulkImportRows(
        rawRows: _rawRows!,
        arms: _cachedArms ?? const [],
        activePeriod: _importPeriod ?? _cachedActivePeriod,
        partners: _cachedPartners ?? const [],
        inactivePartners: _cachedInactivePartners,
        viewerIsStaff: idx.isStaff,
        exchangeRates: ref.read(churchExchangeRatesProvider),
        defaultImportCurrency: _importDefaultCurrency,
        knownFellowships: [
          ...ref.read(knownFellowshipsProvider),
          ..._acceptedFellowships,
        ],
      ),
    );
    if (!mounted) return;
    setState(() {
      _resolved = resolved;
      _loadingPartners = false;
    });
    if (checkDuplicates) {
      await _applyDatabaseDuplicateFlags(idx);
    }
    if (persist) {
      await _persistSession();
    } else {
      _schedulePersistSession();
    }
  }

  /// Flags rows that match an existing entry (same partner, arm, period, date, similar amount).
  /// Fetches every partner the sheet needs that is not cached yet, together.
  ///
  /// The duplicate check below reads one partner's existing entries per row.
  /// Walking it with an `await` inside the loop made that a round trip per
  /// distinct partner, one after another — a 300-partner sheet spent minutes
  /// waiting on serial queries. These are independent reads, so they go out
  /// concurrently, in bounded waves so a large sheet does not open hundreds of
  /// connections at once.
  Future<void> _warmDuplicateCache(
    UserChurchIndex idx,
    EntriesRepository entriesRepo,
  ) async {
    final resolved = _resolved;
    if (resolved == null) return;

    final missing = <String>{};
    for (final r in resolved) {
      if (r.partnerId == null || r.armId == null || r.periodId == null) {
        continue;
      }
      if (_duplicateEntryCache.containsKey(r.partnerId)) continue;
      missing.add(r.partnerId!);
    }
    if (missing.isEmpty) return;

    const wave = 20;
    final ids = missing.toList();
    for (var i = 0; i < ids.length; i += wave) {
      final slice = ids.skip(i).take(wave).toList();
      final lists = await Future.wait([
        for (final id in slice)
          entriesRepo.fetchEntriesForDuplicateCheck(
            idx.churchId,
            partnerId: id,
            allChurchEntries: true,
            createdByUid: null,
          ),
      ]);
      for (var j = 0; j < slice.length; j++) {
        _duplicateEntryCache[slice[j]] = lists[j];
      }
      if (!mounted) return;
    }
  }

  Future<void> _applyDatabaseDuplicateFlags(UserChurchIndex idx) async {
    if (_resolved == null) return;
    final entriesRepo = ref.read(entriesRepositoryProvider);
    // Staff read only their own entries, but a row may repeat one another
    // staff member recorded: the server compares against the whole church
    // and says only which rows look like duplicates.
    if (idx.isStaff) {
      try {
        final rows = _resolved!;
        final hits = await ref.read(similarEntriesProvider).check([
          for (var i = 0; i < rows.length; i++)
            if (rows[i].partnerId != null && rows[i].armId != null && rows[i].periodId != null)
              (
                key: '$i',
                partnerId: rows[i].partnerId!,
                armId: rows[i].armId!,
                periodId: rows[i].periodId!,
                amountCedis: rows[i].amountCedis,
                dateGiven: rows[i].dateGiven,
              ),
        ]);
        if (!mounted || _resolved == null) return;
        final updated = <BulkResolvedRow>[];
        for (var i = 0; i < _resolved!.length; i++) {
          final r = _resolved![i];
          final issues = List<BulkImportIssue>.from(r.issues)
            ..removeWhere((x) => x.code == BulkImportIssueCode.duplicateInDatabase);
          if (hits.contains('$i')) {
            issues.add(const BulkImportIssue(
              code: BulkImportIssueCode.duplicateInDatabase,
              severity: BulkImportSeverity.warning,
            ));
          }
          final block = issues.any((e) => e.severity == BulkImportSeverity.error);
          updated.add(r.copyWith(issues: issues, isBlocking: block));
        }
        setState(() => _resolved = updated);
        _schedulePersistSession();
      } catch (e) {
        if (mounted) setState(() => _error = 'Could not check for duplicates. ${plainError(e)}');
      }
      return;
    }
    try {
      await _warmDuplicateCache(idx, entriesRepo);
      final updated = <BulkResolvedRow>[];
      for (final r in _resolved!) {
        if (r.partnerId == null || r.armId == null || r.periodId == null) {
          updated.add(r);
          continue;
        }
        final issues = List<BulkImportIssue>.from(r.issues)
          ..removeWhere(
            (i) => i.code == BulkImportIssueCode.duplicateInDatabase,
          );
        final partnerId = r.partnerId!;
        var list = _duplicateEntryCache[partnerId];
        list ??= await entriesRepo.fetchEntriesForDuplicateCheck(
          idx.churchId,
          partnerId: partnerId,
          allChurchEntries: true,
          createdByUid: null,
        );
        _duplicateEntryCache[partnerId] = list;
        if (hasSimilarPartnershipEntryWithSameDate(
          list,
          partnerId: r.partnerId!,
          armId: r.armId!,
          periodId: r.periodId!,
          amount: r.amountCedis,
          dateGiven: r.dateGiven,
        )) {
          issues.add(
            const BulkImportIssue(
              code: BulkImportIssueCode.duplicateInDatabase,
              severity: BulkImportSeverity.warning,
            ),
          );
        }
        final block = issues.any((e) => e.severity == BulkImportSeverity.error);
        updated.add(r.copyWith(issues: issues, isBlocking: block));
      }
      if (!mounted) return;
      setState(() => _resolved = updated);
      _schedulePersistSession();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = plainError(e));
    }
  }

  Future<void> _confirmRemoveRow(
    BuildContext context,
    AppLocalizations l10n,
    int index,
  ) async {
    final raw = _rawRows;
    if (raw == null || index < 0 || index >= raw.length) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.bulkImportRemoveRowTitle),
        content: Text(l10n.bulkImportRemoveRowMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.bulkImportCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.bulkImportRemoveRowConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final removedSheetRow = raw[index].sheetRowNumber;
    setState(() {
      _duplicateAcknowledgedSheetRows.remove(removedSheetRow);
      _rawRows = List<BulkRawRow>.from(_rawRows!)..removeAt(index);
    });
    if (_rawRows!.isEmpty) {
      setState(() => _resolved = []);
      await _persistSession();
      return;
    }
    await _reResolve();
    await _persistSession();
  }

  Future<void> _editRow(
    BuildContext context,
    AppLocalizations l10n,
    int index,
  ) async {
    final raw = _rawRows;
    if (raw == null || index >= raw.length) return;
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null) return;
    final arms = await ref.read(armsRepositoryProvider).fetchArms(idx.churchId);
    if (!context.mounted) return;
    final activeArms = arms.where((a) => a.isActive).toList();

    final row = raw[index];
    final v = Map<BulkImportColumn, String>.from(row.valuesByColumn);

    final nameCtrl = TextEditingController(
      text: v[BulkImportColumn.name] ?? '',
    );
    final fellowCtrl = TextEditingController(
      text: v[BulkImportColumn.fellowship] ?? '',
    );
    final phoneCtrl = TextEditingController(
      text: v[BulkImportColumn.contact] ?? '',
    );
    final emailCtrl = TextEditingController(
      text: v[BulkImportColumn.email] ?? '',
    );
    final amountCtrl = TextEditingController(
      text: v[BulkImportColumn.amount] ?? '',
    );
    final dateCtrl = TextEditingController(
      text: v[BulkImportColumn.date] ?? '',
    );
    final armCtrl = TextEditingController(
      text: v[BulkImportColumn.category] ?? '',
    );
    final notesCtrl = TextEditingController(
      text: v[BulkImportColumn.givenToNotes] ?? '',
    );
    var pastorYes = _parseYes(v[BulkImportColumn.pastorConfirmed]);
    PartnershipArm? selectedArm;
    for (final a in activeArms) {
      if (a.name.toLowerCase() == armCtrl.text.trim().toLowerCase()) {
        selectedArm = a;
        break;
      }
    }

    await showSelSideSheet<void>(
      context,
      title: l10n.bulkImportEditRowTitle(row.sheetRowNumber),
      width: 560,
      child: StatefulBuilder(
        builder: (context, setLocal) {
          return LayoutBuilder(
            builder: (context, c) {
              final twoCol = c.maxWidth >= 480;
              Widget row2(Widget a, Widget b) {
                if (!twoCol) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      a,
                      const SizedBox(height: SelSpace.x4),
                      b,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: a),
                    const SizedBox(width: SelSpace.x4),
                    Expanded(child: b),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  row2(
                    SelField(
                      controller: dateCtrl,
                      label: l10n.bulkImportFieldDate,
                      hint: l10n.bulkImportFieldDateHint,
                    ),
                    SelField(
                      controller: nameCtrl,
                      label: l10n.bulkImportFieldName,
                    ),
                  ),
                  const SizedBox(height: SelSpace.x4),
                  row2(
                    SelField(
                      controller: fellowCtrl,
                      label: l10n.bulkImportFieldFellowship,
                    ),
                    SelField(
                      controller: phoneCtrl,
                      label: l10n.bulkImportFieldPhone,
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                  const SizedBox(height: SelSpace.x4),
                  row2(
                    SelField(
                      controller: emailCtrl,
                      label: l10n.bulkImportFieldEmail,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    SelField(
                      controller: amountCtrl,
                      label: l10n.bulkImportFieldAmount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: SelSpace.x4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l10n.bulkImportFieldArm,
                      style: SelType.small.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Sel.warm,
                      ),
                    ),
                  ),
                  const SizedBox(height: SelSpace.x1),
                  SelSelect<String>(
                    value: selectedArm?.id,
                    hint: Text(l10n.bulkImportSelectArm),
                    onChanged: activeArms.isEmpty
                        ? null
                        : (id) {
                            if (id == null) return;
                            setLocal(() {
                              selectedArm = activeArms.firstWhere(
                                (a) => a.id == id,
                              );
                              armCtrl.text = selectedArm!.name;
                            });
                          },
                    items: [
                      for (final a in activeArms)
                        DropdownMenuItem(value: a.id, child: Text(a.name)),
                    ],
                  ),
                  const SizedBox(height: SelSpace.x4),
                  SelButton(
                    label: 'Match to an existing partner',
                    icon: LucideIcons.users,
                    kind: SelButtonKind.ghost,
                    onPressed: () async {
                      final picked = await showPartnerPickerPanel(
                        context,
                        churchId: idx.churchId,
                        uid: idx.uid,
                      );
                      if (picked == null) return;
                      setLocal(() {
                        nameCtrl.text = picked.fullName;
                        fellowCtrl.text = picked.fellowship;
                        phoneCtrl.text = picked.phone ?? phoneCtrl.text;
                        emailCtrl.text = picked.email ?? emailCtrl.text;
                      });
                      _partnerOverrides[row.sheetRowNumber] = picked;
                    },
                  ),
                  const SizedBox(height: SelSpace.x4),
                  SelField(
                    controller: notesCtrl,
                    label: l10n.bulkImportFieldNotes,
                    maxLines: 3,
                  ),
                  const SizedBox(height: SelSpace.x4),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Sel.card,
                      borderRadius: BorderRadius.circular(SelRadius.card),
                      border: Border.all(color: Sel.border),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: SelSpace.x4,
                        vertical: SelSpace.x2,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.bulkImportFieldPastorYes,
                              style: SelType.body.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Switch.adaptive(
                            value: pastorYes,
                            onChanged: (b) => setLocal(() => pastorYes = b),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: SelSpace.x6),
                  Row(
                    children: [
                      SelButton(
                        label: l10n.bulkImportCancel,
                        kind: SelButtonKind.quiet,
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      SelButton.cyan(
                        label: l10n.bulkImportSave,
                        onPressed: () {
                          v[BulkImportColumn.date] = dateCtrl.text.trim();
                          v[BulkImportColumn.name] = nameCtrl.text.trim();
                          v[BulkImportColumn.fellowship] = fellowCtrl.text
                              .trim();
                          v[BulkImportColumn.contact] = phoneCtrl.text.trim();
                          v[BulkImportColumn.email] = emailCtrl.text.trim();
                          v[BulkImportColumn.amount] = amountCtrl.text.trim();
                          v[BulkImportColumn.category] =
                              (selectedArm?.name ?? armCtrl.text).trim();
                          v[BulkImportColumn.givenToNotes] = notesCtrl.text
                              .trim();
                          v[BulkImportColumn.pastorConfirmed] = pastorYes
                              ? 'YES'
                              : 'NO';
                          _rawRows![index] = BulkRawRow(
                            sheetRowNumber: row.sheetRowNumber,
                            valuesByColumn: v,
                          );
                          Navigator.pop(context);
                          _reResolve().then((_) => _schedulePersistSession());
                        },
                      ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
    );

    nameCtrl.dispose();
    fellowCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();
    amountCtrl.dispose();
    dateCtrl.dispose();
    armCtrl.dispose();
    notesCtrl.dispose();
  }

  bool _parseYes(String? s) {
    if (s == null) return false;
    final t = s.trim().toLowerCase();
    return t == 'yes' || t == 'y' || t == 'true' || t == '1';
  }

  List<BulkResolvedRow> _applyPartnerOverrides(List<BulkResolvedRow> rows) {
    if (_partnerOverrides.isEmpty) return rows;
    return [
      for (final r in rows)
        if (_partnerOverrides[r.sheetRowNumber] case final Partner chosen)
          r.copyWith(
            resolution: PartnerResolutionKind.existing,
            partnerId: chosen.id,
            partner: chosen,
            issues: r.issues
                .where(
                  (i) =>
                      i.code != BulkImportIssueCode.ambiguousPhone &&
                      i.code != BulkImportIssueCode.ambiguousName,
                )
                .toList(),
            isBlocking: r.issues.any(
              (i) =>
                  i.severity == BulkImportSeverity.error &&
                  i.code != BulkImportIssueCode.ambiguousPhone &&
                  i.code != BulkImportIssueCode.ambiguousName,
            ),
          )
        else
          r,
    ];
  }

  Future<void> _reResolve({bool checkDuplicates = true}) async {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null || _rawRows == null) return;
    try {
      await _resolveImport(idx, checkDuplicates: checkDuplicates);
    } catch (e) {
      if (mounted) setState(() => _error = plainError(e));
    }
  }

  Future<void> _commit(
    BuildContext context,
    String churchId,
    bool viewerIsPastor,
  ) async {
    final l10n = AppLocalizations.of(context);
    final profile = ref.read(churchUserProfileProvider).valueOrNull;
    if (profile == null || _resolved == null) return;
    // Rows the user set aside never reach Firestore.
    final resolved = _liveRows;

    final progressNotifier = ref.read(
      bulkImportCommitProgressProvider.notifier,
    );
    final eligible = resolved.where((r) => !r.isBlocking).length;
    progressNotifier.start(
      eligible > 0 ? eligible : resolved.length,
      l10n.bulkImportCommitProgressTitle,
    );

    setState(() {
      _committing = true;
      _error = null;
    });
    try {
      final arms = await ref.read(armsRepositoryProvider).fetchArms(churchId);
      PartnershipPeriod? period = _importPeriod;
      if (period == null) {
        final periods = await ref
            .read(periodsRepositoryProvider)
            .fetchPeriods(churchId);
        try {
          period = periods.firstWhere((p) => p.isActive);
        } catch (_) {
          period = null;
        }
      }
      if (period == null) {
        progressNotifier.fail(l10n.bulkImportIssuePeriodNotFound);
        if (!mounted) return;
        setState(() {
          _committing = false;
          _error = l10n.bulkImportIssuePeriodNotFound;
        });
        return;
      }
      final r = await commitBulkImport(
        ref: ref,
        churchId: churchId,
        staff: profile,
        churchDisplayName: ref.read(churchNameProvider) ?? 'Church',
        rows: resolved,
        arms: arms,
        period: period,
        allChurchEntries: true,
        viewerIsPastor: viewerIsPastor,
        duplicateAcknowledgedSheetRows: _duplicateAcknowledgedSheetRows,
        fileName: _fileName ?? 'Pasted rows',
        preparedBy: _preparedBy.text,
        duplicateCache: _duplicateEntryCache,
        onProgress: (current, total, message) {
          progressNotifier.update(current, message);
        },
      );
      progressNotifier.complete();
      final uid = _persistUid;
      final clearChurchId = _persistChurchId;
      if (uid != null && clearChurchId != null) {
        await BulkImportSessionStore.clear(uid: uid, churchId: clearChurchId);
      }
      if (!mounted) return;
      final successMessage = l10n.bulkImportCommitSuccessToast(
        r.entriesCreated,
      );
      setState(() {
        _result = r;
        // The finished screen still shows what came in and from which file.
        _resultRows = _liveRows;
        _resultFile = _fileName;
        _committing = false;
        _rawRows = null;
        _resolved = null;
        _fileName = null;
        _fileBytes = null;
        _duplicateAcknowledgedSheetRows.clear();
        _acceptedFellowships.clear();
      });
      if (context.mounted) {
        selNotice(context, successMessage, kind: SelNoticeKind.success);
      }
      Future<void>.delayed(const Duration(seconds: 4), () {
        if (mounted) {
          ref.read(bulkImportCommitProgressProvider.notifier).reset();
        }
      });
    } catch (e) {
      progressNotifier.fail(plainError(e));
      if (!mounted) return;
      setState(() {
        _error = plainError(e);
        _committing = false;
      });
    }
  }

  String _issueLabel(AppLocalizations l10n, BulkImportIssueCode c) {
    return switch (c) {
      BulkImportIssueCode.ignoredNonDataRow => 'Left out — not giving',
      BulkImportIssueCode.missingName => l10n.bulkImportIssueMissingName,
      BulkImportIssueCode.missingFellowship =>
        l10n.bulkImportIssueMissingFellowship,
      BulkImportIssueCode.missingAmount => l10n.bulkImportIssueMissingAmount,
      BulkImportIssueCode.invalidAmount => l10n.bulkImportIssueInvalidAmount,
      BulkImportIssueCode.missingDate => l10n.bulkImportIssueMissingDate,
      BulkImportIssueCode.invalidDate => l10n.bulkImportIssueInvalidDate,
      BulkImportIssueCode.missingArm => l10n.bulkImportIssueMissingArm,
      BulkImportIssueCode.armNotFound => l10n.bulkImportIssueArmNotFound,
      BulkImportIssueCode.periodNotFound => l10n.bulkImportIssuePeriodNotFound,
      BulkImportIssueCode.ambiguousPhone => l10n.bulkImportIssueAmbiguousPhone,
      BulkImportIssueCode.ambiguousName =>
        'More than one partner has this name and fellowship.',
      BulkImportIssueCode.memberIdNotFound =>
        l10n.bulkImportIssueMemberIdNotFound,
      BulkImportIssueCode.memberIdConflict =>
        l10n.bulkImportIssueMemberIdConflict,
      BulkImportIssueCode.memberIdMerged => 'Old member ID — goes to the person who has it now',
      BulkImportIssueCode.possibleDuplicatePartner =>
        'Looks like an existing partner',
      BulkImportIssueCode.fellowshipMismatch =>
        l10n.bulkImportIssueFellowshipMismatch,
      BulkImportIssueCode.unknownFellowship =>
        'New fellowship — create it or use a similar one',
      BulkImportIssueCode.nameMismatch => l10n.bulkImportIssueNameMismatch,
      BulkImportIssueCode.duplicateInFile =>
        l10n.bulkImportIssueDuplicateInFile,
      BulkImportIssueCode.duplicateInDatabase =>
        l10n.bulkImportIssueDuplicateInDatabase,
      BulkImportIssueCode.staffPastorYesPending =>
        l10n.bulkImportIssueStaffPastorYes,
      BulkImportIssueCode.missingExchangeRate => 'No exchange rate set',
    };
  }
}

/// One problem, every row it affects, and the fix.
class _IssueGroup extends ConsumerStatefulWidget {
  const _IssueGroup({
    required this.code,
    required this.severity,
    required this.label,
    required this.rowIndices,
    required this.rows,
    required this.fmtAmount,
    required this.busy,
    required this.onReviewRow,
    required this.onRemoveRow,
    required this.onBulkMapArm,
    required this.onBulkResolveFellowship,
  });

  final BulkImportIssueCode code;
  final BulkImportSeverity severity;
  final String label;
  final List<int> rowIndices;
  final List<BulkResolvedRow> rows;
  final String Function(double) fmtAmount;
  final bool busy;
  final void Function(int index) onReviewRow;
  final void Function(int index) onRemoveRow;
  final Future<void> Function(List<String> sourceTexts, PartnershipArm arm)
  onBulkMapArm;
  final Future<void> Function(
    List<String> sourceTexts,
    String target, {
    required bool create,
  })
  onBulkResolveFellowship;

  @override
  ConsumerState<_IssueGroup> createState() => _IssueGroupState();
}

class _IssueGroupState extends ConsumerState<_IssueGroup> {
  bool _open = false;
  final Map<String, String?> _armChoice = {};
  bool _applying = false;

  /// Only unmatched-arm problems have a one-shot bulk fix; the rest need the
  /// row editor because the correct value differs per row.
  bool get _fixable =>
      widget.code == BulkImportIssueCode.armNotFound ||
      widget.code == BulkImportIssueCode.missingArm ||
      widget.code == BulkImportIssueCode.unknownFellowship;

  /// The distinct spreadsheet values that failed to match, with their counts.
  Map<String, int> get _unmatched {
    final counts = <String, int>{};
    final fellowshipIssue =
        widget.code == BulkImportIssueCode.unknownFellowship;
    for (final i in widget.rowIndices) {
      final raw = fellowshipIssue
          ? widget.rows[i].fellowship.trim()
          : widget.rows[i].armName.trim();
      final key = raw.isEmpty ? '(blank)' : raw;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  /// Groups spellings that plainly mean the same thing, so the reader fixes a
  /// concept once rather than every way it was typed.
  ///
  /// The rule is **containment**: "Service" and "SUNDAY SERVICE" group because
  /// one's words are a subset of the other's. "Super Sunday" does not join
  /// them — it shares only the word "sunday" with one of them, and neither is
  /// contained in the other. Merging on any shared word would collapse all
  /// three, which is worse than not grouping at all.
  List<_SpellingCluster> get _clusters {
    Set<String> tokensOf(String v) => v
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.length >= 3)
        .toSet();

    final entries = _unmatched.entries.toList()
      // Shortest first, so the tersest spelling becomes the label.
      ..sort((a, b) => a.key.length.compareTo(b.key.length));

    final out = <_SpellingCluster>[];
    for (final e in entries) {
      final mine = tokensOf(e.key);
      _SpellingCluster? home;
      for (final c in out) {
        final theirs = tokensOf(c.label);
        if (mine.isEmpty || theirs.isEmpty) continue;
        if (mine.containsAll(theirs) || theirs.containsAll(mine)) {
          home = c;
          break;
        }
      }
      if (home == null) {
        out.add(
          _SpellingCluster(label: e.key, variants: [e.key], rows: e.value),
        );
      } else {
        home.variants.add(e.key);
        home.rows += e.value;
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final isError = widget.severity == BulkImportSeverity.error;
    final status = isError ? SelStatus.blocked : SelStatus.pending;
    final count = widget.rowIndices.length;
    final arms = (ref.watch(armsStreamProvider).valueOrNull ?? [])
        .where((a) => a.isActive)
        .toList();

    final sample = widget.rowIndices
        .take(3)
        .map((i) => widget.rows[i].fullName)
        .where((n) => n.trim().isNotEmpty)
        .join(', ');

    return Container(
      color: _open ? Sel.canvas : Sel.card,
      padding: const EdgeInsets.symmetric(
        horizontal: SelSpace.cardPad,
        vertical: SelSpace.x4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(status.icon, size: 15, color: status.color),
              ),
              const SizedBox(width: SelSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.label, style: SelType.bodyMedium),
                    if (sample.isNotEmpty)
                      Text(
                        count > 3 ? '$sample and ${count - 3} more' : sample,
                        style: SelType.small,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: SelSpace.x3),
              SelCountTag(
                label: '$count ${count == 1 ? "row" : "rows"}',
                emphasised: isError,
              ),
              const SizedBox(width: SelSpace.x2),
              SelButton(
                label: _open ? 'Hide' : 'Show rows',
                kind: SelButtonKind.quiet,
                dense: true,
                onPressed: () => setState(() => _open = !_open),
              ),
            ],
          ),
          if (_fixable) ...[
            const SizedBox(height: SelSpace.x4),
            for (final cluster in _clusters)
              Padding(
                padding: const EdgeInsets.only(bottom: SelSpace.x2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 7),
                            child: Text.rich(
                              TextSpan(
                                style: SelType.bodySm,
                                children: [
                                  const TextSpan(text: 'Map '),
                                  TextSpan(
                                    text: '“${cluster.label}”',
                                    style: SelType.bodySm.copyWith(
                                      color: Sel.ink,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  TextSpan(
                                    text:
                                        '  ·  ${cluster.rows} '
                                        '${cluster.rows == 1 ? "row" : "rows"}',
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Name the other spellings this will also fix, so
                          // applying does not silently change more than the
                          // label suggests.
                          if (cluster.variants.length > 1)
                            Text(
                              'also ${cluster.variants.where((v) => v != cluster.label).map((v) => '“$v”').join(', ')}',
                              style: SelType.small,
                            ),
                        ],
                      ),
                    ),
                    if (widget.code == BulkImportIssueCode.unknownFellowship)
                      Flexible(
                        child: Wrap(
                          spacing: SelSpace.x2,
                          runSpacing: SelSpace.x2,
                          alignment: WrapAlignment.end,
                          children: [
                            if (suggestSimilarFellowship(
                                  cluster.label,
                                  ref.watch(knownFellowshipsProvider),
                                )
                                case final similar?)
                              SelButton(
                                label: 'Use $similar',
                                kind: SelButtonKind.edge,
                                dense: true,
                                loading: _applying,
                                onPressed: widget.busy
                                    ? null
                                    : () async {
                                        setState(() => _applying = true);
                                        await widget.onBulkResolveFellowship(
                                          cluster.variants,
                                          similar,
                                          create: false,
                                        );
                                        if (mounted) {
                                          setState(() => _applying = false);
                                        }
                                      },
                              ),
                            SelButton(
                              label: 'Create “${cluster.label}”',
                              kind: SelButtonKind.quiet,
                              dense: true,
                              loading: _applying,
                              onPressed: widget.busy
                                  ? null
                                  : () async {
                                      setState(() => _applying = true);
                                      await widget.onBulkResolveFellowship(
                                        cluster.variants,
                                        cluster.label,
                                        create: true,
                                      );
                                      if (mounted) {
                                        setState(() => _applying = false);
                                      }
                                    },
                            ),
                          ],
                        ),
                      )
                    else ...[
                      SizedBox(
                        width: 190,
                        child: SelSelect<String>(
                          value: _armChoice[cluster.label],
                          hint: Text('Select arm', style: SelType.bodyMuted),
                          onChanged: widget.busy || _applying
                              ? null
                              : (v) => setState(
                                  () => _armChoice[cluster.label] = v,
                                ),
                          items: [
                            for (final (a, label) in ArmTree(arms).recordingOptions())
                              DropdownMenuItem(
                                value: a.id,
                                child: Text(label),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: SelSpace.x2),
                      SelButton(
                        label: 'Apply',
                        kind: SelButtonKind.edge,
                        dense: true,
                        loading: _applying,
                        onPressed:
                            _armChoice[cluster.label] == null || widget.busy
                            ? null
                            : () async {
                                final arm = arms
                                    .where(
                                      (a) => a.id == _armChoice[cluster.label],
                                    )
                                    .firstOrNull;
                                if (arm == null) return;
                                setState(() => _applying = true);
                                await widget.onBulkMapArm(
                                  cluster.variants,
                                  arm,
                                );
                                if (mounted) {
                                  setState(() => _applying = false);
                                }
                              },
                      ),
                    ],
                  ],
                ),
              ),
          ],
          if (_open) ...[
            const SizedBox(height: SelSpace.x3),
            Container(
              decoration: BoxDecoration(
                color: Sel.card,
                borderRadius: BorderRadius.circular(SelRadius.input),
                border: Border.all(color: Sel.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var n = 0; n < widget.rowIndices.length; n++) ...[
                    if (n > 0) const Divider(height: 1, color: Sel.border),
                    _AffectedRow(
                      row: widget.rows[widget.rowIndices[n]],
                      fmtAmount: widget.fmtAmount,
                      busy: widget.busy,
                      onReview: () => widget.onReviewRow(widget.rowIndices[n]),
                      onRemove: () => widget.onRemoveRow(widget.rowIndices[n]),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One affected row inside an expanded group. A single line — the group header
/// already said what is wrong, so the row only has to identify itself.
class _AffectedRow extends StatelessWidget {
  const _AffectedRow({
    required this.row,
    required this.fmtAmount,
    required this.busy,
    required this.onReview,
    required this.onRemove,
  });

  final BulkResolvedRow row;
  final String Function(double) fmtAmount;
  final bool busy;
  final VoidCallback onReview;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SelSpace.x4,
        vertical: SelSpace.x2 + 2,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text('${row.sheetRowNumber}', style: SelType.small),
          ),
          Expanded(
            flex: 3,
            child: Text(
              row.fullName.isEmpty ? '(no name)' : row.fullName,
              style: SelType.body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              row.armName,
              style: SelType.bodyMuted,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              fmtAmount(row.amountCedis),
              textAlign: TextAlign.right,
              style: SelType.body.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: SelSpace.x3),
          SelButton(
            label: 'Fix',
            kind: SelButtonKind.quiet,
            dense: true,
            onPressed: busy ? null : onReview,
          ),
          SelButton(
            label: 'Remove',
            kind: SelButtonKind.quiet,
            dense: true,
            onPressed: busy ? null : onRemove,
          ),
        ],
      ),
    );
  }
}

/// The rows that need nothing. Collapsed by default — they are the good news.
class _CleanRowsPanel extends StatefulWidget {
  const _CleanRowsPanel({required this.rows, required this.fmtAmount});

  final List<BulkResolvedRow> rows;
  final String Function(double) fmtAmount;

  @override
  State<_CleanRowsPanel> createState() => _CleanRowsPanelState();
}

class _CleanRowsPanelState extends State<_CleanRowsPanel> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final count = widget.rows.length;
    return SelCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SelSpace.cardPad,
              vertical: SelSpace.x4,
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.check, size: 15, color: Sel.success),
                const SizedBox(width: SelSpace.x3),
                Expanded(
                  child: Text('Ready to import', style: SelType.bodyMedium),
                ),
                SelCountTag(label: '$count ${count == 1 ? "row" : "rows"}'),
                const SizedBox(width: SelSpace.x2),
                if (count > 0)
                  SelButton(
                    label: _open ? 'Hide' : 'Show rows',
                    kind: SelButtonKind.quiet,
                    dense: true,
                    onPressed: () => setState(() => _open = !_open),
                  ),
              ],
            ),
          ),
          if (_open && count > 0) ...[
            const Divider(height: 1, color: Sel.border),
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const Divider(height: 1, color: Sel.border),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SelSpace.cardPad,
                  vertical: SelSpace.x2 + 2,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${widget.rows[i].sheetRowNumber}',
                        style: SelType.small,
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        widget.rows[i].fullName,
                        style: SelType.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          ArmDot(armId: widget.rows[i].armId ?? ''),
                          const SizedBox(width: SelSpace.x2),
                          Flexible(
                            child: Text(
                              widget.rows[i].armName,
                              style: SelType.bodyMuted,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 110,
                      child: Text(
                        widget.fmtAmount(widget.rows[i].amountCedis),
                        textAlign: TextAlign.right,
                        style: SelType.body.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// A set of spreadsheet spellings that mean the same thing.
class _SpellingCluster {
  _SpellingCluster({
    required this.label,
    required this.variants,
    required this.rows,
  });

  /// The tersest spelling in the group — what the reader is asked to map.
  final String label;

  /// Every spelling the mapping will be applied to, [label] included.
  final List<String> variants;

  /// Total affected rows across all [variants].
  int rows;
}

/// Progress across the four stages.
///
/// Shows where you are and what is left, which the old single-page layout
/// could not — there was no finish line, only a long scroll ending in a
/// disabled button.
class _StepBar extends StatelessWidget {
  const _StepBar({required this.current, this.done = false});

  final _Step current;

  /// Every step finished: all four show a tick.
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: SelSpace.x4,
      runSpacing: SelSpace.x2,
      children: [
        for (final s in _Step.ordered)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: s == current && !done
                      ? Sel.ink
                      : s.index < current.index || done
                      ? Sel.skyWash
                      : Sel.track,
                  shape: BoxShape.circle,
                ),
                child: s.index < current.index || done
                    ? const Icon(LucideIcons.check, size: 13, color: Sel.ink)
                    : Text(
                        '${s.index + 1}',
                        style: SelType.small.copyWith(
                          color: s == current ? Sel.card : Sel.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
              const SizedBox(width: SelSpace.x2),
              Text(
                s.label,
                style: SelType.bodySm.copyWith(
                  color: s == current ? Sel.ink : Sel.warm,
                  fontWeight: s == current ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// One column from the sheet, and the field it feeds.
class _ColumnRow extends StatelessWidget {
  const _ColumnRow({
    required this.header,
    required this.sample,
    required this.value,
    required this.onChanged,
  });

  final String header;

  /// Real values from the sheet, so the reader can identify the column
  /// without switching back to the spreadsheet.
  final String sample;

  final BulkImportColumn? value;
  final ValueChanged<BulkImportColumn?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  header,
                  style: SelType.body.copyWith(color: Sel.ink, fontWeight: FontWeight.w700),
                ),
                Text(
                  value == null ? 'Left out' : 'Matched',
                  style: SelType.small,
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              sample,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SelType.bodySm,
            ),
          ),
          SizedBox(
            width: 190,
            child: SelSelect<BulkImportColumn?>(
              value: value,
              hint: Text('Leave out', style: SelType.bodyMuted),
              onChanged: onChanged,
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text('Leave out', style: SelType.bodyMuted),
                ),
                for (final f in bulkImportMappableFields)
                  DropdownMenuItem(
                    value: f,
                    child: Text(bulkImportFieldLabel(f)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A file-level message. Uses the semantic state colours so a blocking
/// problem is distinguishable from a warning at a glance.
class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.status});

  final String message;
  final SelStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SelSpace.x4,
        vertical: SelSpace.x3,
      ),
      decoration: BoxDecoration(
        color: status.wash,
        borderRadius: BorderRadius.circular(SelRadius.card),
        border: Border.all(color: status.color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(status.icon, size: 14, color: status.color),
          ),
          const SizedBox(width: SelSpace.x3),
          Expanded(
            child: Text(
              message,
              style: SelType.bodySm.copyWith(color: Sel.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// The "you left something half-done" card at the top of the upload step.
class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.fileName,
    required this.rowCount,
    required this.savedAt,
    required this.onContinue,
    required this.onClear,
  });

  final String? fileName;
  final int rowCount;
  final DateTime? savedAt;
  final VoidCallback onContinue;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 10, 10, 10),
      decoration: BoxDecoration(
        color: Sel.skyTint,
        borderRadius: BorderRadius.circular(SelRadius.card),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Pick up where you left off', style: SelType.bodyMedium),
                const SizedBox(height: SelSpace.x1),
                Text(
                  '$rowCount ${rowCount == 1 ? "row" : "rows"} from '
                  '${fileName ?? "a spreadsheet"}'
                  '${savedAt == null ? "" : ", saved ${describeWhen(savedAt!)}"}. '
                  'Nothing has been imported yet.',
                  style: SelType.bodySm,
                ),
              ],
            ),
          ),
          const SizedBox(width: SelSpace.x4),
          SelLink(label: 'Discard', onTap: onClear),
          const SizedBox(width: SelSpace.x4),
          SelButton(label: 'Continue', onPressed: onContinue),
        ],
      ),
    );
  }
}

/// "3 minutes ago", "yesterday" — enough to recognise your own draft.
String describeWhen(DateTime when) {
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes} ${diff.inMinutes == 1 ? "minute" : "minutes"} ago';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours} ${diff.inHours == 1 ? "hour" : "hours"} ago';
  }
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  return DateFormat('d MMM').format(when);
}

/// The last few imports, and a way back out of one.
///
/// An import is the only thing in Pillr that writes dozens of records at once,
/// and until now it left no record of itself: the wrong period picked on a
/// sixty-seven row sheet meant finding those rows by eye among eight hundred.
class _RecentImports extends ConsumerWidget {
  const _RecentImports();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batches =
        ref.watch(recentImportBatchesProvider).valueOrNull ?? const [];
    if (batches.isEmpty) return const SizedBox.shrink();
    final money = ref.watch(churchMoneyFormatProvider);

    return Padding(
      padding: const EdgeInsets.only(top: SelSpace.x4),
      child: SelCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Recent imports', style: SelType.subtitle)),
                SelLink(
                  label: 'All imports',
                  onTap: () => context.go('/records/imports'),
                ),
              ],
            ),
            for (var i = 0; i < batches.length && i < 3; i++) ...[
              if (i > 0) const Divider(height: 1, color: Sel.rowLine),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            batches[i].displayName,
                            style: SelType.bodySm.copyWith(
                              color: Sel.ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${DateFormat('d MMM').format(batches[i].createdAt)} · ${batches[i].createdByName}',
                            style: SelType.small,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: SelSpace.x2),
                    Text(
                      '${batches[i].entryCount} entries\n${money(batches[i].totalCedis)}',
                      textAlign: TextAlign.right,
                      style: SelType.small,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImportRow extends ConsumerStatefulWidget {
  const _ImportRow({required this.batch, required this.money});

  final BulkImportBatch batch;
  final String Function(num) money;

  @override
  ConsumerState<_ImportRow> createState() => _ImportRowState();
}

class _ImportRowState extends ConsumerState<_ImportRow> {
  bool _busy = false;

  Future<void> _undo() async {
    final b = widget.batch;
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null) return;

    final ok = await selConfirm(
      context,
      title: 'Undo this import?',
      message:
          'Removes the entries from ${b.fileName} that are still waiting on a '
          'decision. Anything already approved stays — that money has been '
          'counted, and taking it back out quietly would be a second mistake.',
      confirmLabel: 'Undo import',
      destructive: true,
    );
    if (!ok) return;

    setState(() => _busy = true);
    try {
      final result = await ref
          .read(bulkImportBatchRepositoryProvider)
          .undo(churchId: idx.churchId, batchId: b.id, byUid: idx.uid);
      await logPillrActivity(
        ref,
        churchId: idx.churchId,
        action: 'import.undo',
        entityType: 'import_batch',
        entityId: b.id,
        entitySnapshot: {
          'fileName': b.fileName,
          'removed': result.removed,
          'kept': result.kept,
        },
      );
      ref.invalidate(rankingEntriesProvider);
      invalidateEntryDerivedData(ref);
      if (!mounted) return;
      selNotice(
        context,
        result.kept == 0
            ? 'Removed ${result.removed} '
                  '${result.removed == 1 ? "entry" : "entries"} from '
                  '${b.fileName}.'
            : 'Removed ${result.removed}; kept ${result.kept} already '
                  'approved.',
        kind: SelNoticeKind.success,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.batch;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SelSpace.x4,
        vertical: SelSpace.x3,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  b.fileName.isEmpty ? 'A spreadsheet' : b.fileName,
                  style: SelType.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${b.entryCount} ${b.entryCount == 1 ? "entry" : "entries"} · '
                  '${widget.money(b.totalCedis)} · ${b.periodName} · '
                  '${describeWhen(b.createdAt)} by ${b.createdByName}',
                  style: SelType.small,
                ),
                if (b.isUndone)
                  Text(
                    'Undone — ${b.removedCount} removed'
                    '${b.keptCount > 0 ? ", ${b.keptCount} kept" : ""}',
                    style: SelType.small.copyWith(color: Sel.warm),
                  ),
              ],
            ),
          ),
          const SizedBox(width: SelSpace.x4),
          if (!b.isUndone)
            SelButton(
              label: _busy ? 'Undoing…' : 'Undo',
              kind: SelButtonKind.ghost,
              dense: true,
              onPressed: _busy ? null : _undo,
            ),
        ],
      ),
    );
  }
}
