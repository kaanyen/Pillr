import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:the_pillr/l10n/app_localizations.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../../core/utils/entry_duplicate_utils.dart';
import '../../../core/theme/pillr_layout.dart';
import '../../../common/widgets/pillr_form_dialog.dart';
import '../../../common/widgets/pillr_surface_card.dart';
import '../../../common/widgets/pillr_text_field.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart' show AppRadius, AppSpacing;
import '../../../core/theme/app_typography.dart';
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
import 'bulk_import_xlsx_pick.dart';
import '../providers/entries_providers.dart';

/// Column widths shared by header + data rows (avoids toolbar overflow).
abstract final class _BulkImportRowLayout {
  static const double chevron = 28;
  static const double rowNum = 44;
  /// Space between Amount and Date so they don’t read as one block.
  static const double gapAfterAmount = 16;
  static const double amount = 108;
  static const double date = 118;
  static const double status = 108;
  static const double action = 88;
}

class BulkImportScreen extends ConsumerStatefulWidget {
  const BulkImportScreen({super.key});

  @override
  ConsumerState<BulkImportScreen> createState() => _BulkImportScreenState();
}

class _BulkImportScreenState extends ConsumerState<BulkImportScreen> {
  List<BulkRawRow>? _rawRows;
  List<BulkImportIssue> _fileIssues = [];
  List<BulkResolvedRow>? _resolved;
  BulkImportCommitResult? _result;

  bool _parsing = false;
  bool _loadingPartners = false;
  bool _committing = false;
  String? _error;

  /// Sheet row numbers the user has confirmed are intentional (not a duplicate).
  final Set<int> _duplicateAcknowledgedSheetRows = {};

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

    return Scaffold(
      backgroundColor: AppColors.surfaceColor,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: PillrLayout.bulkImportMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                if (_fileIssues.isNotEmpty)
                  ..._fileIssues.map(
                    (i) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: Text(
                        i.message ?? _issueLabel(l10n, i.code),
                        style: AppTypography.caption.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                if (_result != null) _buildResult(context, l10n, _result!),
                if (_result == null) ...[
                  if (_resolved == null || _rawRows == null) ...[
                    Text(
                      l10n.bulkImportUploadTitle,
                      style: AppTypography.heading3.copyWith(color: AppColors.gray900),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      l10n.bulkImportUploadSubtitle,
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    BulkImportDropZone(
                      onPick: () => _pickAndParse(context),
                      loading: _parsing || _committing,
                    ),
                  ] else ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _parsing || _committing ? null : () => _pickAndParse(context),
                        icon: Icon(LucideIcons.upload, size: 18, color: AppColors.primaryColor),
                        label: Text(l10n.bulkImportReplaceFile),
                      ),
                    ),
                  ],
                  if (_loadingPartners)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: Text(l10n.bulkImportLoadingPartners, style: AppTypography.caption),
                    ),
                  if (_resolved != null && _rawRows != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    if (_resolved!.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: Text(l10n.bulkImportNoRowsInImport, style: AppTypography.caption),
                      ),
                    if (_resolved!.isNotEmpty) ...[
                      _buildSummary(context, l10n, _resolved!, idx.isStaff),
                      const SizedBox(height: AppSpacing.md),
                      _buildRowsTableSection(context, l10n, _resolved!),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    if (_resolved!.any((r) => r.isBlocking))
                      Material(
                        color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(LucideIcons.alertTriangle, size: 18, color: Theme.of(context).colorScheme.error),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  l10n.bulkImportBlocking,
                                  style: AppTypography.caption.copyWith(
                                    color: Theme.of(context).colorScheme.error,
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
                        padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.md),
                        child: Text(
                          l10n.bulkImportNoActivePeriod,
                          style: AppTypography.caption.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.lg),
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
                                  backgroundColor: const Color(0xFF16A34A),
                                  foregroundColor: AppColors.white,
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
                                    const SizedBox(width: AppSpacing.sm),
                                    Text(l10n.bulkImportCommitting),
                                  ],
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (allClear) ...[
                                      Icon(LucideIcons.clipboardCheck, size: 20, color: AppColors.white),
                                      const SizedBox(width: AppSpacing.sm),
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
    const totalBg = Color(0xFFEFF6FF);
    const totalIconCircle = Color(0xFFDBEAFE);
    const pendingBg = Color(0xFFFFFBEB);
    const pendingIconCircle = Color(0xFFFDE68A);
    const partnersBg = Color(0xFFECFDF5);
    const partnersIconCircle = Color(0xFFD1FAE5);
    const goalBg = Color(0xFFF5F3FF);
    const goalIconCircle = Color(0xFFEDE9FE);

    Widget compactTile({
      required String label,
      required String valueText,
      required IconData icon,
      required Color bg,
      required Color iconCircle,
      required Color iconColor,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.gray200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: iconCircle,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: iconColor),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.gray600,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    valueText,
                    style: AppTypography.body.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.gray900,
                    ),
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
        iconColor: AppColors.primaryColor,
      ),
      compactTile(
        label: l10n.bulkImportStatNewPartners(0).split(':').first.trim(),
        valueText: '${s.newPartners}',
        icon: LucideIcons.userPlus,
        bg: partnersBg,
        iconCircle: partnersIconCircle,
        iconColor: const Color(0xFF059669),
      ),
      compactTile(
        label: l10n.bulkImportStatExistingPartners(0).split(':').first.trim(),
        valueText: '${s.existingPartners}',
        icon: LucideIcons.userCheck,
        bg: goalBg,
        iconCircle: goalIconCircle,
        iconColor: AppColors.primaryColor,
      ),
      compactTile(
        label: l10n.bulkImportStatTotal('').split(':').first.trim(),
        valueText: fmt.format(s.totalAmount),
        icon: LucideIcons.wallet,
        bg: totalBg,
        iconCircle: totalIconCircle,
        iconColor: AppColors.primaryColor,
      ),
    ];

    final row2 = <Widget>[
      compactTile(
        label: l10n.bulkImportStatWarnings(0).split(':').first.trim(),
        valueText: '${s.warningCount}',
        icon: LucideIcons.alertTriangle,
        bg: pendingBg,
        iconCircle: pendingIconCircle,
        iconColor: const Color(0xFFB45309),
      ),
      compactTile(
        label: l10n.bulkImportStatErrors(0).split(':').first.trim(),
        valueText: '${s.blockingCount}',
        icon: LucideIcons.xCircle,
        bg: const Color(0xFFFEF2F2),
        iconCircle: const Color(0xFFFECACA),
        iconColor: AppColors.dangerColor,
      ),
      if (s.pastorYesCount > 0)
        compactTile(
          label: l10n.bulkImportStatPastorYes(0).split(':').first.trim(),
          valueText: '${s.pastorYesCount}',
          icon: LucideIcons.check,
          bg: const Color(0xFFECFDF5),
          iconCircle: const Color(0xFFD1FAE5),
          iconColor: const Color(0xFF059669),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.bulkImportSummary,
          style: AppTypography.label.copyWith(
            color: AppColors.gray600,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
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
                          if (i < row1.length - 1) const SizedBox(width: AppSpacing.sm),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < row2.length; i++) ...[
                          SizedBox(width: 168, child: row2[i]),
                          if (i < row2.length - 1) const SizedBox(width: AppSpacing.sm),
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
                      if (i < row1.length - 1) const SizedBox(width: AppSpacing.sm),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: row2[0]),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: row2[1]),
                    const SizedBox(width: AppSpacing.sm),
                    if (row2.length > 2) Expanded(child: row2[2]),
                    if (row2.length > 2) const SizedBox(width: AppSpacing.sm),
                    if (row2.length > 2) const Expanded(child: SizedBox.shrink()),
                    if (row2.length == 2) ...[
                      const Expanded(child: SizedBox.shrink()),
                      const SizedBox(width: AppSpacing.sm),
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
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Text(
              l10n.bulkImportStaffPastorNote,
              style: AppTypography.caption.copyWith(
                color: Theme.of(context).colorScheme.tertiary,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRowsTableSection(
    BuildContext context,
    AppLocalizations l10n,
    List<BulkResolvedRow> rows,
  ) {
    return PillrSurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
            child: Text(
              l10n.bulkImportPreview,
              style: AppTypography.label.copyWith(
                color: AppColors.gray600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, c) {
              final tableWidth = math.max(860.0, c.maxWidth);
              return Scrollbar(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _bulkTableHeader(context, l10n),
                        const Divider(height: 1),
                        ...List.generate(rows.length, (i) {
                          final sr = rows[i].sheetRowNumber;
                          return _BulkImportCollapsibleRow(
                            key: ValueKey(sr),
                            row: rows[i],
                            index: i,
                            l10n: l10n,
                            fmtAmount: fmtAmount,
                            onReview: () => _editRow(context, l10n, i),
                            onRemove: () => _confirmRemoveRow(context, l10n, i),
                            loadingLocked: _loadingPartners || _committing,
                            issueLabel: (code) => _issueLabel(l10n, code),
                            resolutionLabel: (k) => _resolutionLabel(l10n, k),
                            duplicateAcknowledged: _duplicateAcknowledgedSheetRows.contains(sr),
                            onAcknowledgeDuplicate: () => setState(() {
                              _duplicateAcknowledgedSheetRows.add(sr);
                            }),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _bulkTableHeader(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(width: _BulkImportRowLayout.chevron),
          SizedBox(
            width: _BulkImportRowLayout.rowNum,
            child: Text(
              l10n.bulkImportTableHeaderRow,
              style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              l10n.bulkImportTableHeaderPartner,
              style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(
            width: _BulkImportRowLayout.amount,
            child: Text(
              l10n.bulkImportTableHeaderAmount,
              style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(width: _BulkImportRowLayout.gapAfterAmount),
          SizedBox(
            width: _BulkImportRowLayout.date,
            child: Text(
              l10n.bulkImportTableHeaderDate,
              style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(
            width: _BulkImportRowLayout.status,
            child: Text(
              l10n.bulkImportTableHeaderStatus,
              style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: _BulkImportRowLayout.action,
            child: Text(
              l10n.bulkImportTableReview,
              style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: _BulkImportRowLayout.action,
            child: Text(
              l10n.bulkImportTableRemove,
              style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String fmtAmount(double v) {
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toStringAsFixed(2);
  }

  String _resolutionLabel(AppLocalizations l10n, PartnerResolutionKind k) {
    return switch (k) {
      PartnerResolutionKind.existing => l10n.bulkImportResolutionExisting,
      PartnerResolutionKind.createNew => l10n.bulkImportResolutionCreate,
      PartnerResolutionKind.ambiguous => l10n.bulkImportResolutionAmbiguous,
      PartnerResolutionKind.unresolved => l10n.bulkImportResolutionUnresolved,
    };
  }

  Widget _buildResult(BuildContext context, AppLocalizations l10n, BulkImportCommitResult r) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.bulkImportResultTitle, style: AppTypography.label),
            const SizedBox(height: AppSpacing.sm),
            Text(l10n.bulkImportEntriesCreated(r.entriesCreated)),
            Text(l10n.bulkImportPartnersCreated(r.partnersCreated)),
            Text(l10n.bulkImportApproved(r.entriesApproved)),
            Text(l10n.bulkImportSkipped(r.rowsSkipped)),
            if (r.errors.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(l10n.bulkImportErrorListHeader, style: AppTypography.caption),
              ...r.errors.map((e) => Text('• $e', style: AppTypography.caption)),
            ],
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () => context.go('/entries'),
              child: Text(l10n.bulkImportBack),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndParse(BuildContext context) async {
    setState(() {
      _error = null;
      _fileIssues = [];
      _rawRows = null;
      _resolved = null;
      _result = null;
      _duplicateAcknowledgedSheetRows.clear();
    });
    final picked = await pickBulkImportXlsx();
    if (picked == null) return;
    final nameLower = picked.name.toLowerCase();
    final dot = nameLower.lastIndexOf('.');
    final ext = dot >= 0 ? nameLower.substring(dot + 1) : '';
    final isXlsx = ext == 'xlsx' || nameLower.endsWith('.xlsx');
    if (!isXlsx) {
      setState(() => _error = AppLocalizations.of(context).bulkImportNeedXlsx);
      return;
    }
    if (ext == 'xlsm' || nameLower.endsWith('.xlsm')) {
      setState(() => _error = AppLocalizations.of(context).bulkImportNoMacros);
      return;
    }
    final bytes = picked.bytes;
    setState(() => _parsing = true);
    try {
      final parsed = parseBulkImportWorkbook(bytes);
      if (parsed.rows.isEmpty && parsed.fileIssues.isNotEmpty) {
        setState(() {
          _fileIssues = parsed.fileIssues;
          _parsing = false;
        });
        return;
      }
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
        _parsing = false;
      });
      await _loadPartnersAndResolve();
    } catch (e) {
      setState(() {
        _error = '${AppLocalizations.of(context).bulkImportParseError}: $e';
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
    final allChurch = idx.isPastor;
    final staffUid = idx.isStaff ? idx.uid : null;
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
          allChurchEntries: allChurch,
          createdByUid: allChurch ? null : staffUid,
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
      return;
    }
    await _reResolve();
  }

  Future<void> _editRow(BuildContext context, AppLocalizations l10n, int index) async {
    final raw = _rawRows;
    if (raw == null || index >= raw.length) return;
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

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return PillrFormDialog(
              title: l10n.bulkImportEditRowTitle(row.sheetRowNumber),
              leading: PillrFormDialog.leadingIcon(LucideIcons.fileEdit),
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
                    v[BulkImportColumn.category] = armCtrl.text.trim();
                    v[BulkImportColumn.givenToNotes] = notesCtrl.text.trim();
                    v[BulkImportColumn.pastorConfirmed] = pastorYes ? 'YES' : 'NO';
                    _rawRows![index] = BulkRawRow(
                      sheetRowNumber: row.sheetRowNumber,
                      valuesByColumn: v,
                    );
                    Navigator.pop(ctx);
                    _reResolve();
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
                          const SizedBox(height: AppSpacing.md),
                          b,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: a),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: b),
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      row2(
                        PillrTextField(
                          controller: dateCtrl,
                          label: l10n.bulkImportFieldDate,
                        ),
                        PillrTextField(
                          controller: nameCtrl,
                          label: l10n.bulkImportFieldName,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      row2(
                        PillrTextField(
                          controller: fellowCtrl,
                          label: l10n.bulkImportFieldFellowship,
                        ),
                        PillrTextField(
                          controller: phoneCtrl,
                          label: l10n.bulkImportFieldPhone,
                          keyboardType: TextInputType.phone,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      row2(
                        PillrTextField(
                          controller: emailCtrl,
                          label: l10n.bulkImportFieldEmail,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        PillrTextField(
                          controller: amountCtrl,
                          label: l10n.bulkImportFieldAmount,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      PillrTextField(
                        controller: armCtrl,
                        label: l10n.bulkImportFieldArm,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      PillrTextField(
                        controller: notesCtrl,
                        label: l10n.bulkImportFieldNotes,
                        maxLines: 3,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(color: AppColors.gray200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.bulkImportFieldPastorYes,
                                  style: AppTypography.body.copyWith(fontWeight: FontWeight.w500),
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
    setState(() {
      _loadingPartners = true;
      _duplicateAcknowledgedSheetRows.clear();
    });
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
    final profile = ref.read(churchUserProfileProvider).valueOrNull;
    final resolved = _resolved;
    if (profile == null || resolved == null) return;

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
        if (!mounted) return;
        setState(() {
          _committing = false;
          _error = AppLocalizations.of(context).bulkImportIssuePeriodNotFound;
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
        allChurchEntries: ref.read(userChurchIndexProvider).valueOrNull?.isPastor ?? false,
        viewerIsPastor: viewerIsPastor,
        duplicateAcknowledgedSheetRows: _duplicateAcknowledgedSheetRows,
      );
      if (!mounted) return;
      setState(() {
        _result = r;
        _committing = false;
      });
    } catch (e) {
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

class _BulkImportCollapsibleRow extends StatefulWidget {
  const _BulkImportCollapsibleRow({
    super.key,
    required this.row,
    required this.index,
    required this.l10n,
    required this.fmtAmount,
    required this.onReview,
    required this.onRemove,
    required this.loadingLocked,
    required this.issueLabel,
    required this.resolutionLabel,
    required this.duplicateAcknowledged,
    required this.onAcknowledgeDuplicate,
  });

  final BulkResolvedRow row;
  final int index;
  final AppLocalizations l10n;
  final String Function(double) fmtAmount;
  final VoidCallback onReview;
  final VoidCallback onRemove;
  final bool loadingLocked;
  final String Function(BulkImportIssueCode) issueLabel;
  final String Function(PartnerResolutionKind) resolutionLabel;
  final bool duplicateAcknowledged;
  final VoidCallback onAcknowledgeDuplicate;

  @override
  State<_BulkImportCollapsibleRow> createState() => _BulkImportCollapsibleRowState();
}

class _BulkImportCollapsibleRowState extends State<_BulkImportCollapsibleRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final l10n = widget.l10n;
    final dateStr = DateFormat.yMMMd().format(row.dateGiven);

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: _BulkImportRowLayout.chevron,
                    child: Icon(
                      _expanded ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  SizedBox(
                    width: _BulkImportRowLayout.rowNum,
                    child: Text(
                      '${row.sheetRowNumber}',
                      style: AppTypography.label,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: Text(
                        row.fullName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _BulkImportRowLayout.amount,
                    child: Text(
                      widget.fmtAmount(row.amountCedis),
                      style: AppTypography.body,
                      textAlign: TextAlign.right,
                    ),
                  ),
                  SizedBox(width: _BulkImportRowLayout.gapAfterAmount),
                  SizedBox(
                    width: _BulkImportRowLayout.date,
                    child: Text(
                      dateStr,
                      style: AppTypography.body,
                      textAlign: TextAlign.right,
                    ),
                  ),
                  SizedBox(
                    width: _BulkImportRowLayout.status,
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _BulkImportStatusBadge(
                          l10n: l10n,
                          row: row,
                          duplicateAcknowledged: widget.duplicateAcknowledged,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _BulkImportRowLayout.action,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: widget.loadingLocked ? null : widget.onReview,
                      child: Text(
                        l10n.bulkImportTableReview,
                        style: const TextStyle(fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _BulkImportRowLayout.action,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: widget.loadingLocked ? null : widget.onRemove,
                      child: Text(
                        l10n.bulkImportTableRemove,
                        style: const TextStyle(fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          alignment: Alignment.topLeft,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    0,
                    AppSpacing.sm,
                    AppSpacing.md,
                  ),
                  child: _detailsColumn(context),
                )
              : const SizedBox.shrink(),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Divider(height: 1, thickness: 1),
        ),
      ],
    );
  }

  Widget _detailsColumn(BuildContext context) {
    final row = widget.row;
    final l10n = widget.l10n;
    final hasDup = row.issues.any(
      (i) =>
          i.code == BulkImportIssueCode.duplicateInFile ||
          i.code == BulkImportIssueCode.duplicateInDatabase,
    );
    final showDupAck = hasDup && !widget.duplicateAcknowledged;

    final labelStyle = AppTypography.caption.copyWith(
      color: AppColors.gray600,
      fontWeight: FontWeight.w600,
    );
    final valueStyle = AppTypography.body;

    TableRow tr(String label, String value) {
      return TableRow(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Text(label, style: labelStyle),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Text(
              value,
              style: valueStyle,
              textAlign: TextAlign.left,
            ),
          ),
        ],
      );
    }

    final tableRows = <TableRow>[
      tr(l10n.bulkImportFieldPartner, widget.resolutionLabel(row.resolution)),
      if (row.partner != null)
        tr(
          l10n.bulkImportFieldName,
          '${row.partner!.memberId} · ${row.partner!.fullName}',
        ),
      tr(l10n.bulkImportFieldArm, row.armName),
      tr(l10n.bulkImportFieldPeriod, row.periodName),
      if (row.notes != null && row.notes!.isNotEmpty) tr(l10n.bulkImportFieldNotes, row.notes!),
      tr(
        l10n.bulkImportFieldPastorYes,
        row.pastorConfirmed ? l10n.bulkImportYes : l10n.bulkImportNo,
      ),
    ];

    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (row.issues.isNotEmpty) ...[
              Wrap(
                alignment: WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.start,
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: row.issues
                    .map(
                      (i) => Chip(
                        label: Text(
                          i.message ?? widget.issueLabel(i.code),
                          style: const TextStyle(fontSize: 11),
                        ),
                        backgroundColor: i.severity == BulkImportSeverity.error
                            ? Theme.of(context).colorScheme.errorContainer
                            : Theme.of(context).colorScheme.secondaryContainer,
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            Table(
              columnWidths: const {
                0: FlexColumnWidth(1.05),
                1: FlexColumnWidth(2.15),
              },
              border: TableBorder.all(color: AppColors.gray200, width: 1, borderRadius: BorderRadius.circular(AppRadius.md)),
              children: tableRows,
            ),
            if (showDupAck) ...[
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: widget.loadingLocked ? null : widget.onAcknowledgeDuplicate,
                  icon: Icon(LucideIcons.shieldCheck, size: 18, color: AppColors.primaryColor),
                  label: Text(l10n.bulkImportConfirmNotDuplicate),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BulkImportStatusBadge extends StatelessWidget {
  const _BulkImportStatusBadge({
    required this.l10n,
    required this.row,
    required this.duplicateAcknowledged,
  });

  final AppLocalizations l10n;
  final BulkResolvedRow row;
  final bool duplicateAcknowledged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasDup = row.issues.any(
      (i) =>
          i.code == BulkImportIssueCode.duplicateInFile ||
          i.code == BulkImportIssueCode.duplicateInDatabase,
    );
    final nonDupIssues = row.issues
        .where(
          (i) =>
              i.code != BulkImportIssueCode.duplicateInFile &&
              i.code != BulkImportIssueCode.duplicateInDatabase,
        )
        .toList();

    if (row.isBlocking) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          l10n.bulkImportRowStatusBlocked,
          style: AppTypography.caption.copyWith(
            color: scheme.onErrorContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    if (hasDup && !duplicateAcknowledged) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF3E8FF),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFB45309).withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.copy, size: 14, color: const Color(0xFF7C3AED)),
            const SizedBox(width: 4),
            Text(
              l10n.bulkImportRowStatusDuplicate,
              style: AppTypography.caption.copyWith(
                color: const Color(0xFF5B21B6),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    if (nonDupIssues.isNotEmpty) {
      return Tooltip(
        message: l10n.bulkImportTableReview,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.alertCircle, size: 16, color: AppColors.gray400),
            const SizedBox(width: 4),
            Text(
              l10n.bulkImportRowStatusCheck,
              style: AppTypography.caption.copyWith(
                color: AppColors.gray600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.check, size: 14, color: const Color(0xFF166534)),
          const SizedBox(width: 4),
          Text(
            l10n.bulkImportRowStatusReady,
            style: AppTypography.caption.copyWith(
              color: const Color(0xFF166534),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
