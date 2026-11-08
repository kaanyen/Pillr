import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/navigation/panel_flows.dart';
import '../core/notifications/sel_notice.dart';
import '../core/utils/date_utils.dart';
import '../design/seline.dart';
import '../features/arms/domain/arm_tree.dart';
import '../features/arms/domain/partnership_arm.dart';
import '../features/arms/providers/arms_providers.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/activity/activity_log_helper.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/entries/bulk_import/batch_edit_model.dart';
import '../features/entries/bulk_import/bulk_import_batches.dart';
import '../features/entries/bulk_import/bulk_import_history_provider.dart';
import '../features/entries/providers/entries_providers.dart';
import '../core/errors/plain_error.dart';

/// Correcting an import after it has landed.
///
/// The import grid checks a spreadsheet before it becomes anything; this is the
/// same rows once they are entries, when one of them turns out to be wrong. The
/// difference matters: these are on the books, so the screen states what will
/// change before it writes anything, saves only the rows that actually differ,
/// and leaves voided rows alone — their money has already been taken back out.
class BatchEditScreen extends ConsumerStatefulWidget {
  const BatchEditScreen({super.key, required this.batchId});

  final String batchId;

  @override
  ConsumerState<BatchEditScreen> createState() => _BatchEditScreenState();
}

class _BatchEditScreenState extends ConsumerState<BatchEditScreen> {
  BulkImportBatch? _batch;
  List<BatchRowDraft> _drafts = [];
  final _amountControllers = <String, TextEditingController>{};

  final _label = TextEditingController();
  final _note = TextEditingController();
  final _preparedBy = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final c in _amountControllers.values) {
      c.dispose();
    }
    _label.dispose();
    _note.dispose();
    _preparedBy.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final batchesRepo = ref.read(bulkImportBatchRepositoryProvider);
      final entriesRepo = ref.read(entriesRepositoryProvider);
      final batch = await batchesRepo.fetchBatch(idx.churchId, widget.batchId);
      final entries =
          await entriesRepo.fetchEntriesForBatch(idx.churchId, widget.batchId);
      // The order the sheet was read in is the order it is corrected in.
      entries.sort((a, b) => a.dateGiven.compareTo(b.dateGiven));
      if (!mounted) return;
      setState(() {
        _batch = batch;
        _drafts = entries.map(BatchRowDraft.from).toList();
        for (final c in _amountControllers.values) {
          c.dispose();
        }
        _amountControllers
          ..clear()
          ..addEntries(_drafts.map((d) => MapEntry(
                d.original.id,
                TextEditingController(text: d.amountCedis.toStringAsFixed(2)),
              )));
        _label.text = batch?.label ?? '';
        _note.text = batch?.note ?? '';
        _preparedBy.text = batch?.preparedBy ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = plainError(e);
        _loading = false;
      });
    }
  }

  BatchEditSummary get _summary => summariseBatchEdits(_drafts);

  bool get _detailsChanged {
    final b = _batch;
    if (b == null) return false;
    String norm(String? s) => (s ?? '').trim();
    return norm(_label.text) != norm(b.label) ||
        norm(_note.text) != norm(b.note) ||
        norm(_preparedBy.text) != norm(b.preparedBy);
  }

  Future<void> _save() async {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    final pastor = ref.read(churchUserProfileProvider).valueOrNull;
    if (idx == null || pastor == null) return;

    final changed = _drafts.where((d) => d.hasChanges).toList();
    if (changed.isEmpty && !_detailsChanged) return;

    if (changed.isNotEmpty) {
      final ok = await _confirmRowChanges(changed);
      if (!ok) return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final entriesRepo = ref.read(entriesRepositoryProvider);
      for (final d in changed) {
        final e = d.original;
        // A foreign-currency row keeps its currency and its rate; the figure
        // being edited is the cedi amount, so the source amount is derived
        // back from it rather than left saying something else.
        final rate = e.displayExchangeRate;
        await entriesRepo.pastorUpdateEntry(
          churchId: idx.churchId,
          existing: e,
          pastor: pastor,
          partnerId: d.partnerId,
          partnerSnapshot: {...e.partnerSnapshot, 'fullName': d.partnerName},
          partnershipArmId: d.armId,
          armSnapshot: {'name': d.armName},
          partnershipPeriodId: e.partnershipPeriodId,
          periodSnapshot: e.periodSnapshot,
          amountCedis: d.amountCedis,
          sourceCurrency: e.displaySourceCurrency,
          sourceAmount: rate > 0 ? d.amountCedis / rate : d.amountCedis,
          exchangeRateToBase: rate,
          dateGiven: d.dateGiven,
          notes: e.notes,
        );
      }

      if (_detailsChanged) {
        await ref.read(bulkImportBatchRepositoryProvider).rename(
              churchId: idx.churchId,
              batchId: widget.batchId,
              label: _label.text,
              note: _note.text,
              preparedBy: _preparedBy.text,
              writePreparedBy: true,
              previousLabel: _batch?.label ?? _batch?.fileName,
              previousNote: _batch?.note,
              writePrevious: true,
            );
        await logPillrActivity(
          ref,
          churchId: idx.churchId,
          action: 'import.rename',
          entityType: 'import_batch',
          entityId: widget.batchId,
          entitySnapshot: {
            'label': _label.text,
            'fileName': _batch?.fileName,
          },
        );
      }

      if (changed.isNotEmpty) {
        await ref.read(bulkImportBatchRepositoryProvider).markEdited(
              churchId: idx.churchId,
              batchId: widget.batchId,
              byUid: pastor.uid,
              editedCount: changed.length,
            );
        await logPillrActivity(
          ref,
          churchId: idx.churchId,
          action: 'import.batch_edit',
          entityType: 'import_batch',
          entityId: widget.batchId,
          entitySnapshot: {
            'edited': changed.length,
            'fileName': _batch?.fileName,
          },
        );
      }

      ref.invalidate(rankingEntriesProvider);
      invalidateEntryDerivedData(ref);
      await ref.read(importHistoryProvider.notifier).refresh();
      if (!mounted) return;
      setState(() => _saving = false);
      selNotice(
        context,
        changed.isEmpty
            ? 'Import details saved.'
            : '${changed.length} ${changed.length == 1 ? "row" : "rows"} corrected. '
                'Revert them from Imports if that was a mistake.',
        kind: SelNoticeKind.success,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = plainError(e);
        _saving = false;
      });
    }
  }

  Future<bool> _confirmRowChanges(List<BatchRowDraft> changed) async {
    final money = ref.read(churchMoneyFormatProvider);
    final summary = _summary;
    final delta = summary.amountDelta;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => SelDialog(
        title: 'Save these corrections?',
        subtitle: 'This changes money already on the books.',
        width: 560,
        actions: [
          SelButton(
            label: 'Cancel',
            kind: SelButtonKind.quiet,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          SelButton.cyan(
            label: 'Save corrections',
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (delta != 0)
              Text(
                'The approved total for this import changes by '
                '${delta > 0 ? "+" : "−"}${money(delta.abs())}.',
                style: SelType.body,
              )
            else
              Text(
                'No money moves — only who or when.',
                style: SelType.body,
              ),
            const SizedBox(height: SelSpace.x3),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final d in changed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: SelSpace.x2),
                        child: Text(
                          '${d.original.partnerSnapshot['fullName'] ?? 'Partner'} — '
                          '${d.changes.join(', ')}',
                          style: SelType.small,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return ok ?? false;
  }

  Future<void> _pickPartner(BatchRowDraft draft) async {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null) return;
    final chosen = await showPartnerPickerPanel(
      context,
      churchId: idx.churchId,
      uid: idx.uid,
    );
    if (chosen == null) return;
    setState(() {
      draft.partnerId = chosen.id;
      draft.partnerName = chosen.fullName;
    });
  }

  Future<void> _pickDate(BatchRowDraft draft) async {
    final d = await showDatePicker(
      context: context,
      initialDate: draft.dateGiven,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => draft.dateGiven = d);
  }

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final money = ref.watch(churchMoneyFormatProvider);
    final arms = ref.watch(armsStreamProvider).valueOrNull ?? const [];
    final canEdit = idx?.isPastor ?? false;

    if (_loading) {
      return const SelPageBody(
        children: [SelCard(child: SelSkeletonRows(count: 6))],
      );
    }

    final batch = _batch;
    if (batch == null) {
      return SelPageBody(
        children: [
          SelEmpty(
            title: 'Import not found',
            message: 'It may have been removed.',
            actionLabel: 'Back to imports',
            onAction: () => context.go('/records/imports'),
          ),
        ],
      );
    }

    final summary = _summary;
    final dirty = summary.hasChanges || _detailsChanged;

    return SelPageBody(
      children: [
        SelPageTitle(
          title: batch.displayName,
          subtitle: 'Correcting an import that is already on the books.',
          actions: [
            SelButton(
              label: 'Back to imports',
              kind: SelButtonKind.quiet,
              onPressed: () => context.go('/records/imports'),
            ),
            if (canEdit)
              SelButton.cyan(
                label: dirty ? 'Save changes' : 'Saved',
                icon: LucideIcons.check,
                loading: _saving,
                onPressed: !dirty || _saving ? null : _save,
              ),
          ],
        ),

        // The summary the whole screen is read against, always in view.
        SelStatRow(stats: [
          SelStat(
            label: 'Total',
            value: money(summary.total),
            footnote: summary.pesewasDelta == 0
                ? 'Approved rows'
                : '${summary.amountDelta > 0 ? "+" : "−"}'
                    '${money(summary.amountDelta.abs())} unsaved',
          ),
          SelStat(
            label: 'Entries',
            value: '${_drafts.length}',
            footnote: summary.lockedRows > 0
                ? '${summary.lockedRows} cleared'
                : 'In this import',
          ),
          SelStat(
            label: 'Prepared by',
            value: batch.preparedBy ?? 'Not recorded',
            footnote: 'Who put the sheet together',
          ),
          SelStat(
            label: 'Uploaded by',
            value: batch.createdByName.isEmpty ? 'Unknown' : batch.createdByName,
            footnote:
                formatFirestoreDate(batch.createdAt, pattern: 'd MMM y, HH:mm'),
          ),
        ]),

        const SelSectionGap(factor: 0.4),

        if (_error != null) ...[
          SelError(message: _error!),
          const SizedBox(height: SelSpace.x4),
        ],

        if (!canEdit)
          SelCard(
            child: Text(
              'Only a pastor can change entries. You can read this import here, '
              'and the figures above are live.',
              style: SelType.bodyMuted,
            ),
          ),

        SelPanel(
          title: 'Import details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelField(
                controller: _label,
                label: 'Name',
                hint: batch.fileName.isEmpty ? 'March offerings' : batch.fileName,
                enabled: canEdit,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: SelSpace.x3),
              SelField(
                controller: _preparedBy,
                label: 'Prepared by',
                hint: 'Who put this sheet together',
                enabled: canEdit,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: SelSpace.x3),
              SelField(
                controller: _note,
                label: 'Note',
                hint: 'Anything worth remembering about this import',
                maxLines: 2,
                enabled: canEdit,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: SelSpace.x3),
              Text(
                'Period: ${batch.periodName} · File: '
                '${batch.fileName.isEmpty ? "pasted rows" : batch.fileName}',
                style: SelType.small,
              ),
            ],
          ),
        ),

        const SizedBox(height: SelSpace.x4),

        SelSectionLabel(label: 'Rows'),
        const SizedBox(height: SelSpace.x2),

        if (_drafts.isEmpty)
          const SelCard(
            child: Text('This import created no entries.'),
          )
        else
          for (final draft in _drafts)
            Padding(
              padding: const EdgeInsets.only(bottom: SelSpace.x2),
              child: _RowEditor(
                draft: draft,
                arms: arms,
                canEdit: canEdit && !draft.isLocked,
                amountController: _amountControllers[draft.original.id]!,
                money: money,
                onChanged: () => setState(() {}),
                onPickPartner: () => _pickPartner(draft),
                onPickDate: () => _pickDate(draft),
                onReset: () {
                  setState(() {
                    draft.reset();
                    _amountControllers[draft.original.id]!.text =
                        draft.amountCedis.toStringAsFixed(2);
                  });
                },
              ),
            ),
      ],
    );
  }
}

class _RowEditor extends StatelessWidget {
  const _RowEditor({
    required this.draft,
    required this.arms,
    required this.canEdit,
    required this.amountController,
    required this.money,
    required this.onChanged,
    required this.onPickPartner,
    required this.onPickDate,
    required this.onReset,
  });

  final BatchRowDraft draft;
  final List<PartnershipArm> arms;
  final bool canEdit;
  final TextEditingController amountController;
  final String Function(num) money;
  final VoidCallback onChanged;
  final VoidCallback onPickPartner;
  final VoidCallback onPickDate;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final entry = draft.original;
    return SelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(draft.partnerName, style: SelType.body),
                    const SizedBox(height: SelSpace.x1),
                    Text(
                      entry.partnerSnapshot['fellowship']?.toString() ?? '',
                      style: SelType.small,
                    ),
                    if (canEdit) ...[
                      const SizedBox(height: SelSpace.x1),
                      SelButton(
                        label: 'Change partner',
                        kind: SelButtonKind.quiet,
                        dense: true,
                        onPressed: onPickPartner,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: SelSpace.x3),
              SizedBox(
                width: 140,
                child: SelField(
                  controller: amountController,
                  label: 'Amount (₵)',
                  enabled: canEdit,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (v) {
                    final parsed = double.tryParse(v.replaceAll(',', ''));
                    if (parsed != null && parsed >= 0) {
                      draft.amountCedis = parsed;
                    }
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: SelSpace.x3),
              SizedBox(
                width: 160,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Date given', style: SelType.small),
                    const SizedBox(height: SelSpace.x1),
                    SelButton(
                      label: formatFirestoreDate(
                        draft.dateGiven,
                        pattern: 'd MMM y',
                      ),
                      icon: LucideIcons.calendar,
                      kind: SelButtonKind.quiet,
                      dense: true,
                      onPressed: canEdit ? onPickDate : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: SelSpace.x3),
              SizedBox(
                width: 180,
                child: SelSelect<String>(
                  value: arms.any((a) => a.id == draft.armId)
                      ? draft.armId
                      : null,
                  label: 'Arm',
                  onChanged: canEdit
                      ? (v) {
                          if (v == null) return;
                          final arm = arms.where((a) => a.id == v).firstOrNull;
                          draft.armId = v;
                          draft.armName = arm?.name ?? draft.armName;
                          onChanged();
                        }
                      : null,
                  items: [
                    for (final (a, label) in ArmTree(arms).recordingOptions())
                      DropdownMenuItem(value: a.id, child: Text(label)),
                  ],
                ),
              ),
            ],
          ),
          if (draft.isLocked || draft.hasChanges || entry.hasForeignSource) ...[
            const SizedBox(height: SelSpace.x2),
            Row(
              children: [
                if (draft.isLocked)
                  const SelStatusMark(
                    status: SelStatus.voided,
                    label: 'Cleared — not editable',
                  )
                else if (entry.status != 'approved')
                  SelStatusMark(
                    status: SelStatusStyle.parse(entry.status),
                    label: entry.status,
                  ),
                if (entry.hasForeignSource) ...[
                  const SizedBox(width: SelSpace.x2),
                  Text(
                    'Recorded as ${entry.displaySourceAmount.toStringAsFixed(2)} '
                    '${entry.displaySourceCurrency} at '
                    '${entry.displayExchangeRate}',
                    style: SelType.small,
                  ),
                ],
                if (draft.hasChanges) ...[
                  const SizedBox(width: SelSpace.x2),
                  Expanded(
                    child: Text(
                      draft.changes.join(' · '),
                      style: SelType.small,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SelButton(
                    label: 'Undo',
                    kind: SelButtonKind.quiet,
                    dense: true,
                    onPressed: onReset,
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
