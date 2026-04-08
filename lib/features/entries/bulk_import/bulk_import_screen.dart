import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:the_pillr/l10n/app_localizations.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../../core/theme/pillr_layout.dart';
import '../../../common/widgets/pillr_surface_card.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../arms/providers/arms_providers.dart';
import '../../auth/domain/user_church_index.dart';
import '../../auth/providers/auth_providers.dart';
import '../../church/providers/church_settings_providers.dart';
import '../../partners/providers/partners_providers.dart';
import '../../periods/domain/partnership_period.dart';
import '../../periods/providers/periods_providers.dart';
import 'bulk_import_columns.dart';
import 'bulk_import_commit.dart';
import 'bulk_import_models.dart';
import 'bulk_import_parser.dart';
import 'bulk_import_resolver.dart';
import 'bulk_import_xlsx_pick.dart';

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
      appBar: AppBar(
        title: Text(l10n.bulkImportTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/entries'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: PillrLayout.bulkImportMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.bulkImportHint, style: AppTypography.body),
                const SizedBox(height: AppSpacing.md),
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
                  FilledButton.icon(
                    onPressed: _parsing || _committing ? null : () => _pickAndParse(context),
                    icon: _parsing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file_outlined),
                    label: Text(_parsing ? l10n.bulkImportParsing : l10n.bulkImportPickFile),
                  ),
                  if (_loadingPartners)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: Text(l10n.bulkImportLoadingPartners, style: AppTypography.caption),
                    ),
                  if (_resolved != null && _rawRows != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _buildSummary(context, l10n, _resolved!, idx.isStaff),
                    const SizedBox(height: AppSpacing.md),
                    if (_resolved!.any((r) => r.isBlocking))
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Text(
                          l10n.bulkImportBlocking,
                          style: AppTypography.caption.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    Text(l10n.bulkImportPreview, style: AppTypography.label),
                    const SizedBox(height: AppSpacing.sm),
                    if (activePeriod == null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: Text(
                          l10n.bulkImportNoActivePeriod,
                          style: AppTypography.caption.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (_resolved!.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: Text(l10n.bulkImportNoRowsInImport, style: AppTypography.caption),
                      ),
                    ...List.generate(_resolved!.length, (i) {
                      return _buildRowCard(
                        context,
                        l10n,
                        i,
                        _resolved![i],
                      );
                    }),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      onPressed: _committing ||
                              activePeriod == null ||
                              _resolved!.isEmpty ||
                              _resolved!.any((r) => r.isBlocking)
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
                          : Text(l10n.bulkImportConfirm),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.bulkImportSummary, style: AppTypography.label),
            const SizedBox(height: AppSpacing.sm),
            Text(l10n.bulkImportStatRows(s.totalRows)),
            Text(l10n.bulkImportStatNewPartners(s.newPartners)),
            Text(l10n.bulkImportStatExistingPartners(s.existingPartners)),
            Text(l10n.bulkImportStatTotal(fmt.format(s.totalAmount))),
            Text(l10n.bulkImportStatWarnings(s.warningCount)),
            Text(l10n.bulkImportStatErrors(s.blockingCount)),
            if (s.pastorYesCount > 0) Text(l10n.bulkImportStatPastorYes(s.pastorYesCount)),
            if (viewerIsStaff && s.staffPastorYesCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  l10n.bulkImportStaffPastorNote,
                  style: AppTypography.caption.copyWith(
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRowCard(
    BuildContext context,
    AppLocalizations l10n,
    int index,
    BulkResolvedRow row,
  ) {
    final dateStr = DateFormat.yMMMd().format(row.dateGiven);
    return PillrSurfaceCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ExpansionTile(
        title: Text(
          l10n.bulkImportRowNum(row.sheetRowNumber),
          style: AppTypography.label,
        ),
        subtitle: Text(
          '${row.fullName} · ${fmtAmount(row.amountCedis)} · $dateStr',
          style: AppTypography.caption,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: row.issues
                      .map(
                        (i) => Chip(
                          label: Text(
                            i.message ?? _issueLabel(l10n, i.code),
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
                Text('${l10n.bulkImportFieldPartner}: ${_resolutionLabel(l10n, row.resolution)}'),
                if (row.partner != null) Text('${row.partner!.memberId} · ${row.partner!.fullName}'),
                Text('${l10n.bulkImportFieldArm}: ${row.armName}'),
                Text('${l10n.bulkImportFieldPeriod}: ${row.periodName}'),
                if (row.notes != null && row.notes!.isNotEmpty)
                  Text('${l10n.bulkImportFieldNotes}: ${row.notes}'),
                Text('${l10n.bulkImportFieldPastorYes}: ${row.pastorConfirmed ? l10n.bulkImportYes : l10n.bulkImportNo}'),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppSpacing.sm,
                    children: [
                      TextButton(
                        onPressed: _loadingPartners || _committing
                            ? null
                            : () => _confirmRemoveRow(context, l10n, index),
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        child: Text(l10n.bulkImportRemoveRow),
                      ),
                      TextButton(
                        onPressed: _loadingPartners || _committing
                            ? null
                            : () => _editRow(context, l10n, index),
                        child: Text(l10n.bulkImportEditRow),
                      ),
                    ],
                  ),
                ),
              ],
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPartners = false;
        _error = '$e';
      });
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
    setState(() {
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
            return AlertDialog(
              title: Text(l10n.bulkImportEditRowTitle(row.sheetRowNumber)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: dateCtrl,
                      decoration: InputDecoration(labelText: l10n.bulkImportFieldDate),
                    ),
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(labelText: l10n.bulkImportFieldName),
                    ),
                    TextField(
                      controller: fellowCtrl,
                      decoration: InputDecoration(labelText: l10n.bulkImportFieldFellowship),
                    ),
                    TextField(
                      controller: phoneCtrl,
                      decoration: InputDecoration(labelText: l10n.bulkImportFieldPhone),
                    ),
                    TextField(
                      controller: emailCtrl,
                      decoration: InputDecoration(labelText: l10n.bulkImportFieldEmail),
                    ),
                    TextField(
                      controller: amountCtrl,
                      decoration: InputDecoration(labelText: l10n.bulkImportFieldAmount),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    TextField(
                      controller: armCtrl,
                      decoration: InputDecoration(labelText: l10n.bulkImportFieldArm),
                    ),
                    TextField(
                      controller: notesCtrl,
                      decoration: InputDecoration(labelText: l10n.bulkImportFieldNotes),
                      maxLines: 2,
                    ),
                    SwitchListTile(
                      title: Text(l10n.bulkImportFieldPastorYes),
                      value: pastorYes,
                      onChanged: (b) => setLocal(() => pastorYes = b),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.bulkImportCancel)),
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
