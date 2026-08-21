import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:the_pillr/l10n/app_localizations.dart';

import '../../../design/seline.dart';
import '../../../screens/arm_palette.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../../core/utils/entry_duplicate_utils.dart';
import '../../arms/domain/partnership_arm.dart';
import '../../arms/providers/arms_providers.dart';
import '../../auth/domain/user_church_index.dart' show UserChurchIndex;
import '../../auth/providers/auth_providers.dart';
import '../../church/providers/church_settings_providers.dart';
import '../../partners/providers/partners_providers.dart';
import '../../periods/domain/partnership_period.dart';
import '../../periods/providers/periods_providers.dart';
import 'bulk_import_columns.dart';
import 'bulk_import_commit.dart';
import 'bulk_import_drop_zone.dart';
import 'bulk_import_models.dart';
import 'bulk_import_parser.dart';
import 'bulk_import_resolver.dart';
import 'bulk_import_commit_progress.dart';
import 'bulk_import_session_store.dart';
import 'bulk_import_xlsx_pick.dart';
import '../providers/entries_providers.dart';

/// Column widths shared by header + data rows (avoids toolbar overflow).
class BulkImportScreen extends ConsumerStatefulWidget {
  const BulkImportScreen({super.key});

  @override
  ConsumerState<BulkImportScreen> createState() => _BulkImportScreenState();
}

class _BulkImportScreenState extends ConsumerState<BulkImportScreen> with WidgetsBindingObserver {
  List<BulkRawRow>? _rawRows;
  List<BulkImportIssue> _fileIssues = [];
  List<BulkResolvedRow>? _resolved;
  BulkImportCommitResult? _result;

  bool _parsing = false;
  bool _loadingPartners = false;
  bool _committing = false;
  bool _restoringSession = false;
  String? _error;

  /// Sheet row numbers the user has confirmed are intentional (not a duplicate).
  final Set<int> _duplicateAcknowledgedSheetRows = {};

  String? _fileName;
  Uint8List? _fileBytes;
  bool _sessionRestored = false;
  String? _persistUid;
  String? _persistChurchId;
  Timer? _persistDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restorePersistedSession());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _persistDebounce?.cancel();
    _persistSession();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
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
    );
  }

  Future<void> _restorePersistedSession() async {
    if (_sessionRestored) return;
    _sessionRestored = true;
    final idx = await _waitForChurchIndex();
    if (idx == null || !mounted) return;
    _cachePersistIds(idx);
    final saved = await BulkImportSessionStore.load(uid: idx.uid, churchId: idx.churchId);
    if (saved == null || saved.rawRows.isEmpty || !mounted) return;
    setState(() {
      _restoringSession = true;
      _fileName = saved.fileName;
      _fileBytes = saved.fileBytes;
      _rawRows = saved.rawRows;
      _fileIssues = saved.fileIssues;
      _duplicateAcknowledgedSheetRows
        ..clear()
        ..addAll(saved.duplicateAcknowledgedSheetRows);
      _result = null;
      _resolved = null;
    });
    await _loadPartnersAndResolve();
    if (!mounted) return;
    setState(() => _restoringSession = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).bulkImportDraftRestored)),
    );
  }

  bool get _hasDraftRows => _rawRows != null && _rawRows!.isNotEmpty;

  bool get _isResolvingDraft =>
      _restoringSession || (_hasDraftRows && _resolved == null && (_loadingPartners || _parsing));

  bool _rowHasDuplicateIssue(BulkResolvedRow r) {
    return r.issues.any(
      (i) =>
          i.code == BulkImportIssueCode.duplicateInFile ||
          i.code == BulkImportIssueCode.duplicateInDatabase,
    );
  }

  bool _duplicatesFullyAcknowledged() {
    if (_resolved == null) return false;
    for (final r in _resolved!) {
      if (_rowHasDuplicateIssue(r) && !_duplicateAcknowledgedSheetRows.contains(r.sheetRowNumber)) {
        return false;
      }
    }
    return true;
  }

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
    final activePeriod = ref.watch(activePeriodProvider);

    if (idx == null || (!idx.isPastor && !idx.isStaff)) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.bulkImportTitle)),
        body: Center(child: Text(l10n.bulkImportAccessDenied)),
      );
    }
    _cachePersistIds(idx);

    final showUploadZone = !_hasDraftRows && !_isResolvingDraft;

    return Scaffold(
      backgroundColor: Sel.card,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(SelSpace.x6),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: SelSpace.x4),
                    child: Text(_error!, style: SelType.body.copyWith(fontWeight: FontWeight.w500)),
                  ),
                if (_fileIssues.isNotEmpty)
                  ..._fileIssues.map(
                    (i) => Padding(
                      padding: const EdgeInsets.only(bottom: SelSpace.x1),
                      child: Text(
                        i.message ?? _issueLabel(l10n, i.code),
                        style: SelType.small.copyWith(
                          color: Sel.ink,
                        ),
                      ),
                    ),
                  ),
                if (_result != null) _buildResult(context, l10n, _result!),
                if (_result == null) ...[
                  if (_isResolvingDraft) ...[
                    _buildRestoringDraft(context, l10n),
                  ] else if (showUploadZone) ...[
                    Text(
                      l10n.bulkImportUploadTitle,
                      style: SelType.subtitle.copyWith(color: Sel.ink),
                    ),
                    const SizedBox(height: SelSpace.x1),
                    Text(
                      l10n.bulkImportUploadSubtitle,
                      style: SelType.body.copyWith(
                        color: Sel.warm,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: SelSpace.x4),
                    BulkImportDropZone(
                      onPick: () => _pickAndParse(context),
                      loading: _parsing || _committing,
                      fileName: _fileName,
                    ),
                  ] else if (_hasDraftRows) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _parsing || _committing ? null : () => _pickAndParse(context),
                        icon: Icon(LucideIcons.upload, size: 18, color: Sel.soot),
                        label: Text(l10n.bulkImportReplaceFile),
                      ),
                    ),
                  ],
                  if (_loadingPartners && !_isResolvingDraft)
                    Padding(
                      padding: const EdgeInsets.only(top: SelSpace.x4),
                      child: Text(l10n.bulkImportLoadingPartners, style: SelType.small),
                    ),
                  if (_resolved != null && _rawRows != null) ...[
                    const SizedBox(height: SelSpace.x6),
                    if (_resolved!.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: SelSpace.x4),
                        child: Text(l10n.bulkImportNoRowsInImport, style: SelType.small),
                      ),
                    if (_resolved!.isNotEmpty) ...[
                      _buildSummary(context, l10n, _resolved!, idx.isStaff),
                      const SizedBox(height: SelSpace.x4),
                      _buildIssueReview(context, l10n, _resolved!),
                    ],
                    const SizedBox(height: SelSpace.x4),
                    if (_resolved!.any((r) => r.isBlocking))
                      Material(
                        color: Sel.canvas,
                        borderRadius: BorderRadius.circular(SelRadius.card),
                        child: Padding(
                          padding: const EdgeInsets.all(SelSpace.x6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(LucideIcons.alertTriangle, size: 18, color: Sel.ink),
                              const SizedBox(width: SelSpace.x2),
                              Expanded(
                                child: Text(
                                  l10n.bulkImportBlocking,
                                  style: SelType.small.copyWith(
                                    color: Sel.ink,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (activePeriod == null)
                      Padding(
                        padding: const EdgeInsets.only(top: SelSpace.x4, bottom: SelSpace.x4),
                        child: Text(
                          l10n.bulkImportNoActivePeriod,
                          style: SelType.small.copyWith(
                            color: Sel.ink,
                          ),
                        ),
                      ),
                    const SizedBox(height: SelSpace.x6),
                    Builder(
                      builder: (context) {
                        final sum = _resolved != null
                            ? summarize(_resolved!, viewerIsStaff: idx.isStaff)
                            : null;
                        final nonDupWarnings =
                            _resolved != null ? _countNonDuplicateWarnings(_resolved!) : 0;
                        final allClear = sum != null &&
                            sum.blockingCount == 0 &&
                            nonDupWarnings == 0 &&
                            _duplicatesFullyAcknowledged();
                        return FilledButton(
                          style: allClear
                              ? FilledButton.styleFrom(
                                  backgroundColor: Sel.soot,
                                  foregroundColor: Sel.card,
                                )
                              : null,
                          onPressed: _committing ||
                                  activePeriod == null ||
                                  _resolved == null ||
                                  _resolved!.isEmpty ||
                                  _resolved!.any((r) => r.isBlocking) ||
                                  !_duplicatesFullyAcknowledged()
                              ? null
                              : () => _commit(context, idx.churchId, idx.isPastor),
                          child: _committing
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                    const SizedBox(width: SelSpace.x2),
                                    Text(l10n.bulkImportCommitting),
                                  ],
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (allClear) ...[
                                      Icon(LucideIcons.clipboardCheck, size: 20, color: Sel.card),
                                      const SizedBox(width: SelSpace.x2),
                                    ],
                                    Text(
                                      allClear ? l10n.bulkImportCompleteImport : l10n.bulkImportConfirm,
                                    ),
                                  ],
                                ),
                        );
                      },
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummary(
    BuildContext context,
    AppLocalizations l10n,
    List<BulkResolvedRow> rows,
    bool viewerIsStaff,
  ) {
    final s = summarize(rows, viewerIsStaff: viewerIsStaff);
    final fmt = NumberFormat.currency(symbol: 'GHS ', decimalDigits: 2);
    const totalBg = Sel.card;
    const totalIconCircle = Sel.canvas;
    const pendingBg = Sel.card;
    const pendingIconCircle = Sel.canvas;
    const partnersBg = Sel.card;
    const partnersIconCircle = Sel.canvas;
    const goalBg = Sel.card;
    const goalIconCircle = Sel.canvas;

    Widget compactTile({
      required String label,
      required String valueText,
      required IconData icon,
      required Color bg,
      required Color iconCircle,
      required Color iconColor,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: SelSpace.x2, vertical: SelSpace.x2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(SelRadius.card),
          border: Border.all(color: Sel.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: iconCircle,
                borderRadius: BorderRadius.circular(SelRadius.pill),
              ),
              child: Icon(icon, size: 16, color: iconColor),
            ),
            const SizedBox(width: SelSpace.x2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: SelType.small.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    valueText,
                    style: SelType.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final row1 = <Widget>[
      compactTile(
        label: l10n.bulkImportPreview,
        valueText: '${s.totalRows}',
        icon: LucideIcons.list,
        bg: totalBg,
        iconCircle: totalIconCircle,
        iconColor: Sel.soot,
      ),
      compactTile(
        label: l10n.bulkImportStatNewPartners(0).split(':').first.trim(),
        valueText: '${s.newPartners}',
        icon: LucideIcons.userPlus,
        bg: partnersBg,
        iconCircle: partnersIconCircle,
        iconColor: Sel.warm,
      ),
      compactTile(
        label: l10n.bulkImportStatExistingPartners(0).split(':').first.trim(),
        valueText: '${s.existingPartners}',
        icon: LucideIcons.userCheck,
        bg: goalBg,
        iconCircle: goalIconCircle,
        iconColor: Sel.soot,
      ),
      compactTile(
        label: l10n.bulkImportStatTotal('').split(':').first.trim(),
        valueText: fmt.format(s.totalAmount),
        icon: LucideIcons.wallet,
        bg: totalBg,
        iconCircle: totalIconCircle,
        iconColor: Sel.soot,
      ),
    ];

    final row2 = <Widget>[
      compactTile(
        label: l10n.bulkImportStatWarnings(0).split(':').first.trim(),
        valueText: '${s.warningCount}',
        icon: LucideIcons.alertTriangle,
        bg: pendingBg,
        iconCircle: pendingIconCircle,
        iconColor: Sel.warm,
      ),
      compactTile(
        label: l10n.bulkImportStatErrors(0).split(':').first.trim(),
        valueText: '${s.blockingCount}',
        icon: LucideIcons.xCircle,
        bg: Sel.card,
        iconCircle: Sel.canvas,
        iconColor: Sel.ink,
      ),
      if (s.pastorYesCount > 0)
        compactTile(
          label: l10n.bulkImportStatPastorYes(0).split(':').first.trim(),
          valueText: '${s.pastorYesCount}',
          icon: LucideIcons.check,
          bg: Sel.card,
          iconCircle: Sel.canvas,
          iconColor: Sel.warm,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.bulkImportSummary,
          style: SelType.bodyMedium.copyWith(
            color: Sel.warm,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: SelSpace.x2),
        LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth < 520) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < row1.length; i++) ...[
                          SizedBox(width: 168, child: row1[i]),
                          if (i < row1.length - 1) const SizedBox(width: SelSpace.x2),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: SelSpace.x2),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < row2.length; i++) ...[
                          SizedBox(width: 168, child: row2[i]),
                          if (i < row2.length - 1) const SizedBox(width: SelSpace.x2),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < row1.length; i++) ...[
                      Expanded(child: row1[i]),
                      if (i < row1.length - 1) const SizedBox(width: SelSpace.x2),
                    ],
                  ],
                ),
                const SizedBox(height: SelSpace.x2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: row2[0]),
                    const SizedBox(width: SelSpace.x2),
                    Expanded(child: row2[1]),
                    const SizedBox(width: SelSpace.x2),
                    if (row2.length > 2) Expanded(child: row2[2]),
                    if (row2.length > 2) const SizedBox(width: SelSpace.x2),
                    if (row2.length > 2) const Expanded(child: SizedBox.shrink()),
                    if (row2.length == 2) ...[
                      const Expanded(child: SizedBox.shrink()),
                      const SizedBox(width: SelSpace.x2),
                      const Expanded(child: SizedBox.shrink()),
                    ],
                  ],
                ),
              ],
            );
          },
        ),
        if (viewerIsStaff && s.staffPastorYesCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: SelSpace.x4),
            child: Text(
              l10n.bulkImportStaffPastorNote,
              style: SelType.small.copyWith(
                color: Theme.of(context).colorScheme.tertiary,
              ),
            ),
          ),
      ],
    );
  }

  /// Issue-first review.
  ///
  /// A bulk importer's failures are bulk failures: one misspelled arm name in
  /// the source spreadsheet blocks every row that uses it. Listing rows and
  /// asking someone to expand and fix each one turns a single mistake into
  /// forty corrections.
  ///
  /// So this leads with the *problems*, grouped, each with the fix attached —
  /// map every unmatched "Super Sunday" to a real arm once, and every row
  /// carrying it clears at the same time. Rows that are already fine collapse
  /// into a single line, because they need no attention.
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
            subtitle:
                '${rows.length - clean.length} of ${rows.length} rows',
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
    await _reResolve();
    _schedulePersistSession();
  }

  String fmtAmount(double v) {
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toStringAsFixed(2);
  }

  Widget _buildRestoringDraft(BuildContext context, AppLocalizations l10n) {
    return SelCard(clip: true, 
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SelSpace.x8, horizontal: SelSpace.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
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

  Widget _buildResult(BuildContext context, AppLocalizations l10n, BulkImportCommitResult r) {
    return Card(
      color: Sel.canvas,
      child: Padding(
        padding: const EdgeInsets.all(SelSpace.x6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.bulkImportResultTitle, style: SelType.bodyMedium),
            const SizedBox(height: SelSpace.x2),
            Text(l10n.bulkImportEntriesCreated(r.entriesCreated)),
            Text(l10n.bulkImportPartnersCreated(r.partnersCreated)),
            Text(l10n.bulkImportApproved(r.entriesApproved)),
            Text(l10n.bulkImportSkipped(r.rowsSkipped)),
            if (r.errors.isNotEmpty) ...[
              const SizedBox(height: SelSpace.x2),
              Text(l10n.bulkImportErrorListHeader, style: SelType.small),
              ...r.errors.map((e) => Text('• $e', style: SelType.small)),
            ],
            const SizedBox(height: SelSpace.x4),
            FilledButton(
              onPressed: () => context.go('/queue'),
              child: Text(l10n.bulkImportBack),
            ),
          ],
        ),
      ),
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
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.bulkImportCancel)),
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
    final dot = nameLower.lastIndexOf('.');
    final ext = dot >= 0 ? nameLower.substring(dot + 1) : '';
    final isXlsx = ext == 'xlsx' || nameLower.endsWith('.xlsx');
    if (!isXlsx) {
      setState(() => _error = l10n.bulkImportNeedXlsx);
      return;
    }
    if (ext == 'xlsm' || nameLower.endsWith('.xlsm')) {
      setState(() => _error = l10n.bulkImportNoMacros);
      return;
    }

    setState(() {
      _error = null;
      _parsing = true;
    });
    try {
      final parsed = parseBulkImportWorkbook(picked.bytes);
      if (parsed.rows.isEmpty && parsed.fileIssues.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _fileIssues = parsed.fileIssues;
          _parsing = false;
        });
        return;
      }
      if (parsed.rows.isEmpty) {
        if (!mounted) return;
        setState(() {
          _error = l10n.bulkImportNoRows;
          _fileIssues = parsed.fileIssues;
          _parsing = false;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _fileName = picked.name;
        _fileBytes = picked.bytes;
        _rawRows = parsed.rows;
        _fileIssues = parsed.fileIssues;
        _resolved = null;
        _result = null;
        _duplicateAcknowledgedSheetRows.clear();
        _parsing = false;
      });
      await _loadPartnersAndResolve();
      await _persistSession();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '${l10n.bulkImportParseError}: $e';
        _parsing = false;
      });
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
    try {
      final armsRepo = ref.read(armsRepositoryProvider);
      final periodsRepo = ref.read(periodsRepositoryProvider);
      final arms = await armsRepo.fetchArms(idx.churchId);
      final periods = await periodsRepo.fetchPeriods(idx.churchId);
      if (!mounted) return;
      PartnershipPeriod? activePeriod;
      try {
        activePeriod = periods.firstWhere((p) => p.isActive);
      } catch (_) {
        activePeriod = null;
      }
      final repo = ref.read(partnersRepositoryProvider);
      final partners = await repo.fetchAllActivePartners(idx.churchId);
      if (!mounted) return;
      final resolved = resolveBulkImportRows(
        rawRows: _rawRows!,
        arms: arms,
        activePeriod: activePeriod,
        partners: partners,
        viewerIsStaff: idx.isStaff,
      );
      setState(() {
        _resolved = resolved;
        _loadingPartners = false;
      });
      await _applyDatabaseDuplicateFlags(idx);
      await _persistSession();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPartners = false;
        _error = '$e';
      });
    }
  }

  /// Flags rows that match an existing entry (same partner, arm, period, date, similar amount).
  Future<void> _applyDatabaseDuplicateFlags(UserChurchIndex idx) async {
    if (_resolved == null) return;
    final entriesRepo = ref.read(entriesRepositoryProvider);
    // Always scan ALL church entries — staff can now read all entries and need
    // to detect duplicates created by other staff members too.
    try {
      final updated = <BulkResolvedRow>[];
      for (final r in _resolved!) {
        if (r.partnerId == null || r.armId == null || r.periodId == null) {
          updated.add(r);
          continue;
        }
        final issues = List<BulkImportIssue>.from(r.issues)
          ..removeWhere((i) => i.code == BulkImportIssueCode.duplicateInDatabase);
        final list = await entriesRepo.fetchEntriesForDuplicateCheck(
          idx.churchId,
          partnerId: r.partnerId!,
          allChurchEntries: true,
          createdByUid: null,
        );
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
      await _persistSession();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _confirmRemoveRow(BuildContext context, AppLocalizations l10n, int index) async {
    final raw = _rawRows;
    if (raw == null || index < 0 || index >= raw.length) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.bulkImportRemoveRowTitle),
        content: Text(l10n.bulkImportRemoveRowMessage),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.bulkImportCancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.bulkImportRemoveRowConfirm)),
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

  Future<void> _editRow(BuildContext context, AppLocalizations l10n, int index) async {
    final raw = _rawRows;
    if (raw == null || index >= raw.length) return;
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null) return;
    final arms = await ref.read(armsRepositoryProvider).fetchArms(idx.churchId);
    if (!context.mounted) return;
    final activeArms = arms.where((a) => a.isActive).toList();

    final row = raw[index];
    final v = Map<BulkImportColumn, String>.from(row.valuesByColumn);

    final nameCtrl = TextEditingController(text: v[BulkImportColumn.name] ?? '');
    final fellowCtrl = TextEditingController(text: v[BulkImportColumn.fellowship] ?? '');
    final phoneCtrl = TextEditingController(text: v[BulkImportColumn.contact] ?? '');
    final emailCtrl = TextEditingController(text: v[BulkImportColumn.email] ?? '');
    final amountCtrl = TextEditingController(text: v[BulkImportColumn.amount] ?? '');
    final dateCtrl = TextEditingController(text: v[BulkImportColumn.date] ?? '');
    final armCtrl = TextEditingController(text: v[BulkImportColumn.category] ?? '');
    final notesCtrl = TextEditingController(text: v[BulkImportColumn.givenToNotes] ?? '');
    var pastorYes = _parseYes(v[BulkImportColumn.pastorConfirmed]);
    PartnershipArm? selectedArm;
    for (final a in activeArms) {
      if (a.name.toLowerCase() == armCtrl.text.trim().toLowerCase()) {
        selectedArm = a;
        break;
      }
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return SelDialog(
              title: l10n.bulkImportEditRowTitle(row.sheetRowNumber),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.bulkImportCancel),
                ),
                FilledButton(
                  onPressed: () {
                    v[BulkImportColumn.date] = dateCtrl.text.trim();
                    v[BulkImportColumn.name] = nameCtrl.text.trim();
                    v[BulkImportColumn.fellowship] = fellowCtrl.text.trim();
                    v[BulkImportColumn.contact] = phoneCtrl.text.trim();
                    v[BulkImportColumn.email] = emailCtrl.text.trim();
                    v[BulkImportColumn.amount] = amountCtrl.text.trim();
                    v[BulkImportColumn.category] =
                        (selectedArm?.name ?? armCtrl.text).trim();
                    v[BulkImportColumn.givenToNotes] = notesCtrl.text.trim();
                    v[BulkImportColumn.pastorConfirmed] = pastorYes ? 'YES' : 'NO';
                    _rawRows![index] = BulkRawRow(
                      sheetRowNumber: row.sheetRowNumber,
                      valuesByColumn: v,
                    );
                    Navigator.pop(ctx);
                    _reResolve().then((_) => _schedulePersistSession());
                  },
                  child: Text(l10n.bulkImportSave),
                ),
              ],
              child: LayoutBuilder(
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
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                                  selectedArm = activeArms.firstWhere((a) => a.id == id);
                                  armCtrl.text = selectedArm!.name;
                                });
                              },
                        items: [
                          for (final a in activeArms)
                            DropdownMenuItem(value: a.id, child: Text(a.name)),
                        ],
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
                          padding: const EdgeInsets.symmetric(horizontal: SelSpace.x4, vertical: SelSpace.x2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.bulkImportFieldPastorYes,
                                  style: SelType.body.copyWith(fontWeight: FontWeight.w500),
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
                    ],
                  );
                },
              ),
            );
          },
        );
      },
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

  Future<void> _reResolve() async {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null || _rawRows == null) return;
    setState(() => _loadingPartners = true);
    try {
      final arms = await ref.read(armsRepositoryProvider).fetchArms(idx.churchId);
      final periods = await ref.read(periodsRepositoryProvider).fetchPeriods(idx.churchId);
      PartnershipPeriod? activePeriod;
      try {
        activePeriod = periods.firstWhere((p) => p.isActive);
      } catch (_) {
        activePeriod = null;
      }
      final partners = await ref.read(partnersRepositoryProvider).fetchAllActivePartners(idx.churchId);
      if (!mounted) return;
      final resolved = resolveBulkImportRows(
        rawRows: _rawRows!,
        arms: arms,
        activePeriod: activePeriod,
        partners: partners,
        viewerIsStaff: idx.isStaff,
      );
      setState(() {
        _resolved = resolved;
        _loadingPartners = false;
      });
      await _applyDatabaseDuplicateFlags(idx);
      await _persistSession();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingPartners = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _commit(
    BuildContext context,
    String churchId,
    bool viewerIsPastor,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final profile = ref.read(churchUserProfileProvider).valueOrNull;
    final resolved = _resolved;
    if (profile == null || resolved == null) return;

    final progressNotifier = ref.read(bulkImportCommitProgressProvider.notifier);
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
      final periods = await ref.read(periodsRepositoryProvider).fetchPeriods(churchId);
      PartnershipPeriod? period;
      try {
        period = periods.firstWhere((p) => p.isActive);
      } catch (_) {
        period = null;
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
      final successMessage = l10n.bulkImportCommitSuccessToast(r.entriesCreated);
      setState(() {
        _result = r;
        _committing = false;
        _rawRows = null;
        _resolved = null;
        _fileName = null;
        _fileBytes = null;
        _duplicateAcknowledgedSheetRows.clear();
      });
      messenger.showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
      Future<void>.delayed(const Duration(seconds: 4), () {
        if (mounted) {
          ref.read(bulkImportCommitProgressProvider.notifier).reset();
        }
      });
    } catch (e) {
      progressNotifier.fail('$e');
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _committing = false;
      });
    }
  }

  String _issueLabel(AppLocalizations l10n, BulkImportIssueCode c) {
    return switch (c) {
      BulkImportIssueCode.missingName => l10n.bulkImportIssueMissingName,
      BulkImportIssueCode.missingFellowship => l10n.bulkImportIssueMissingFellowship,
      BulkImportIssueCode.missingAmount => l10n.bulkImportIssueMissingAmount,
      BulkImportIssueCode.invalidAmount => l10n.bulkImportIssueInvalidAmount,
      BulkImportIssueCode.missingDate => l10n.bulkImportIssueMissingDate,
      BulkImportIssueCode.invalidDate => l10n.bulkImportIssueInvalidDate,
      BulkImportIssueCode.missingArm => l10n.bulkImportIssueMissingArm,
      BulkImportIssueCode.armNotFound => l10n.bulkImportIssueArmNotFound,
      BulkImportIssueCode.periodNotFound => l10n.bulkImportIssuePeriodNotFound,
      BulkImportIssueCode.ambiguousPhone => l10n.bulkImportIssueAmbiguousPhone,
      BulkImportIssueCode.memberIdNotFound => l10n.bulkImportIssueMemberIdNotFound,
      BulkImportIssueCode.memberIdConflict => l10n.bulkImportIssueMemberIdConflict,
      BulkImportIssueCode.fellowshipMismatch => l10n.bulkImportIssueFellowshipMismatch,
      BulkImportIssueCode.nameMismatch => l10n.bulkImportIssueNameMismatch,
      BulkImportIssueCode.duplicateInFile => l10n.bulkImportIssueDuplicateInFile,
      BulkImportIssueCode.duplicateInDatabase => l10n.bulkImportIssueDuplicateInDatabase,
      BulkImportIssueCode.staffPastorYesPending => l10n.bulkImportIssueStaffPastorYes,
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
      widget.code == BulkImportIssueCode.missingArm;

  /// The distinct spreadsheet values that failed to match, with their counts.
  Map<String, int> get _unmatched {
    final counts = <String, int>{};
    for (final i in widget.rowIndices) {
      final raw = widget.rows[i].armName.trim();
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
        out.add(_SpellingCluster(label: e.key, variants: [e.key], rows: e.value));
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
                                    text: '  ·  ${cluster.rows} '
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
                    SizedBox(
                      width: 190,
                      child: SelSelect<String>(
                        value: _armChoice[cluster.label],
                        hint: Text('Select arm', style: SelType.bodyMuted),
                        onChanged: widget.busy || _applying
                            ? null
                            : (v) => setState(() => _armChoice[cluster.label] = v),
                        items: [
                          for (final a in arms)
                            DropdownMenuItem(value: a.id, child: Text(a.name)),
                        ],
                      ),
                    ),
                    const SizedBox(width: SelSpace.x2),
                    SelButton(
                      label: 'Apply',
                      kind: SelButtonKind.edge,
                      dense: true,
                      loading: _applying,
                      onPressed: _armChoice[cluster.label] == null || widget.busy
                          ? null
                          : () async {
                              final arm = arms
                                  .where((a) => a.id == _armChoice[cluster.label])
                                  .firstOrNull;
                              if (arm == null) return;
                              setState(() => _applying = true);
                              await widget.onBulkMapArm(cluster.variants, arm);
                              if (mounted) setState(() => _applying = false);
                            },
                    ),
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
