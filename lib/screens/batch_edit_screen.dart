import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/navigation/panel_flows.dart';
import '../core/notifications/sel_notice.dart';
import '../design/seline.dart';
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
      debugPrint('Correct import, loading: $e');
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
        if (idx.isStaff) {
          await entriesRepo.staffUpdateEntry(
            churchId: idx.churchId,
            existing: e,
            staff: pastor,
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
          continue;
        }
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
      // The Imports list is not on screen here; it loads fresh when opened.
      // Refreshing it from this page used it after it had closed.
      ref.invalidate(importHistoryProvider);
      if (!mounted) return;
      setState(() => _saving = false);
      selNotice(
        context,
        changed.isEmpty
            ? 'Import details saved.'
            : '${changed.length} ${changed.length == 1 ? "row" : "rows"} corrected. '
                '${idx.isStaff ? 'Your pastor approves them again. ' : ''}'
                'Revert them from Imports if that was a mistake.',
        kind: SelNoticeKind.success,
      );
      await _load();
    } catch (e) {
      debugPrint('Correct import, saving: $e');
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
        subtitle: ref.read(userChurchIndexProvider).valueOrNull?.isStaff == true
            ? 'Rows that were approved go back to your pastor to approve again.'
            : 'This changes money already on the books.',
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
            if (ref.read(userChurchIndexProvider).valueOrNull?.isStaff == true)
              Text(
                'Until your pastor approves them again, the changed rows that were '
                'approved leave the totals.',
                style: SelType.body,
              )
            else if (delta != 0)
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

  // ------------------------------------------------------------- the sheet

  _Tab _tab = _Tab.all;
  (int, int)? _sel;
  bool _aside = false;

  static const _columns = [
    SelSheetColumn('Date', weight: .8),
    SelSheetColumn('Name', weight: 1.5),
    SelSheetColumn('Fellowship', weight: 1.1),
    SelSheetColumn('Arm', weight: 1),
    SelSheetColumn('Amount', weight: .9, numeric: true),
  ];

  bool _inTab(BatchRowDraft d) => switch (_tab) {
    _Tab.all => true,
    _Tab.changed => d.hasChanges,
    _Tab.approved => d.original.status == 'approved',
    _Tab.waiting => d.original.status == 'pending',
  };

  List<BatchRowDraft> get _shown => [for (final d in _drafts) if (_inTab(d)) d];

  String _rowNumber(BatchRowDraft d) => '${_drafts.indexOf(d) + 1}';

  Widget _mark(BatchRowDraft d) {
    final (fill, edge, icon, color) = d.isLocked
        ? (Sel.track, Sel.track, LucideIcons.minus, Sel.warm)
        : d.hasChanges
        ? (Sel.ink, Sel.ink, LucideIcons.pencil, Sel.card)
        : d.original.status == 'approved'
        ? (Sel.skyWash, Sel.skyWash, LucideIcons.check, Sel.ink)
        : (Sel.card, const Color(0xFF8AA7C4), LucideIcons.clock, Sel.ink);
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle, border: Border.all(color: edge, width: 1.5)),
      child: Icon(icon, size: 11, color: color),
    );
  }

  String _afterSave(BatchRowDraft d, bool staff) => d.original.status != 'approved'
      ? ''
      : staff
      ? ' Goes back to your pastor to approve again.'
      : ' Stays approved.';

  SelSheetRow _row(BatchRowDraft d, String Function(double) money, List<PartnershipArm> arms, bool staff) {
    final locked = d.isLocked;
    final note = locked
        ? 'Archived, so it cannot be changed.'
        : d.hasChanges
        ? '${d.changes.map((c) => c[0].toUpperCase() + c.substring(1)).join('. ')}.${_afterSave(d, staff)}'
        : null;
    final fixed = SelSheetCellKind.fixed;
    return SelSheetRow(
      mark: _mark(d),
      number: _rowNumber(d),
      dimmed: locked,
      note: note,
      cells: [
        SelSheetCell(
          DateFormat('d MMM').format(d.dateGiven),
          kind: locked ? fixed : SelSheetCellKind.action,
          onAction: () => _pickDate(d),
          changed: d.dateChanged,
          was: d.dateChanged ? DateFormat('d MMM y').format(d.original.dateGiven) : null,
        ),
        SelSheetCell(
          d.partnerName,
          kind: locked ? fixed : SelSheetCellKind.action,
          onAction: () => _pickPartner(d),
          changed: d.partnerChanged,
          was: d.partnerChanged ? '${d.original.partnerSnapshot['fullName'] ?? 'Partner'}' : null,
        ),
        SelSheetCell('${d.original.partnerSnapshot['fellowship'] ?? ''}', kind: fixed),
        SelSheetCell(
          d.armName,
          kind: locked || arms.isEmpty ? fixed : SelSheetCellKind.choice,
          options: [for (final a in arms) a.name],
          changed: d.armChanged,
          was: d.armChanged ? '${d.original.armSnapshot['name'] ?? ''}' : null,
        ),
        SelSheetCell(
          money(d.amountCedis),
          editText: d.amountCedis.toStringAsFixed(2),
          kind: locked ? fixed : SelSheetCellKind.text,
          changed: d.amountChanged,
          was: d.amountChanged ? money(d.original.amountCedis) : null,
        ),
      ],
    );
  }

  void _edit(BatchRowDraft d, int col, String value, List<PartnershipArm> arms) {
    switch (col) {
      case 3:
        final arm = arms.where((a) => a.name == value).firstOrNull;
        if (arm != null) {
          setState(() => d
            ..armId = arm.id
            ..armName = arm.name);
        }
      case 4:
        final v = double.tryParse(value.replaceAll(RegExp(r'[^\d.]'), ''));
        if (v == null || v <= 0) {
          selNotice(context, 'Type the amount as a number, like 1250 or 1250.50.', kind: SelNoticeKind.error);
          return;
        }
        setState(() => d.amountCedis = v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final money = ref.watch(churchMoneyFormatProvider);
    final arms = ref.watch(armsStreamProvider).valueOrNull ?? const [];
    final staff = idx?.isStaff ?? false;
    final canEdit = (idx?.isPastor ?? false) || staff;

    if (_loading) {
      return const Center(child: PillrLoader(size: 40));
    }
    final batch = _batch;
    if (batch == null || !canEdit) {
      return SelPageBody(
        children: [
          SelEmpty(
            title: batch == null ? 'Import not found' : 'Not yours to correct',
            message: batch == null
                ? 'It may have been removed.'
                : 'Pastors, and the staff member who brought it in, can correct an import.',
          ),
          const SizedBox(height: SelSpace.x4),
          Center(child: SelButton(label: 'Back to imports', onPressed: () => context.go('/records/imports'))),
        ],
      );
    }

    final shown = _shown;
    final changed = _drafts.where((d) => d.hasChanges).toList();
    final approved = _drafts.where((d) => d.original.status == 'approved').length;
    final waiting = _drafts.where((d) => d.original.status == 'pending').length;
    final delta = _summary.amountDelta;
    var sel = _sel;
    if (sel != null && sel.$1 >= shown.length) sel = null;
    final current = sel == null ? null : shown[sel.$1];

    final header = Row(
      children: [
        SelButton(label: '← Imports', onPressed: _saving ? null : () => context.go('/records/imports')),
        const SizedBox(width: SelSpace.x4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Correct ${batch.displayName}', style: SelType.title.copyWith(fontSize: 20, height: 1.2)),
              Text(
                '${batch.fileName} · ${_drafts.length} entries · nothing changes until you save',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SelType.small,
              ),
            ],
          ),
        ),
        Text.rich(
          TextSpan(
            style: SelType.small,
            children: [
              TextSpan(text: '$approved', style: const TextStyle(color: Sel.ink, fontWeight: FontWeight.w800)),
              const TextSpan(text: ' approved   '),
              TextSpan(text: '$waiting', style: const TextStyle(color: Sel.ink, fontWeight: FontWeight.w800)),
              const TextSpan(text: ' waiting'),
            ],
          ),
        ),
      ],
    );

    final tabs = Row(
      children: [
        Expanded(
          child: SelPillTabs<_Tab>(
            selected: _tab,
            onSelect: (t) => setState(() {
              _tab = t;
              _sel = null;
            }),
            tabs: [
              (_Tab.all, 'All', _drafts.length),
              (_Tab.changed, 'Changed', changed.length),
              (_Tab.approved, 'Approved', approved),
              (_Tab.waiting, 'Waiting', waiting),
            ],
          ),
        ),
        const SizedBox(width: SelSpace.x2),
        Tooltip(
          message: '↑ ↓ ← → move between cells · Enter edits · Tab next cell · ]: move the card aside',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Sel.card,
              borderRadius: BorderRadius.circular(SelRadius.pill),
              border: Border.all(color: Sel.border, width: 1.5),
            ),
            child: Text('Keys', style: SelType.small.copyWith(color: Sel.ink, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );

    final banner = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Sel.skyTint, borderRadius: BorderRadius.circular(16)),
      child: Text(
        staff
            ? 'Changing a row that was approved sends it back to your pastor to approve again. Waiting rows stay waiting.'
            : 'Approved rows stay approved when you correct them, and the totals move with your change.',
        style: SelType.small.copyWith(color: Sel.ink),
      ),
    );

    Widget sheet({required bool shrinkWrap}) => shown.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(SelSpace.x6),
            child: Text('No rows here.', textAlign: TextAlign.center, style: SelType.bodySm),
          )
        : SelSheet(
            storageKey: 'correct-import',
            shrinkWrap: shrinkWrap,
            busy: _saving,
            columns: _columns,
            rows: [for (final d in shown) _row(d, money, arms, staff)],
            selected: sel,
            onSelect: (r, c) => setState(() => _sel = (r, c)),
            onEdit: (r, c, v) => _edit(shown[r], c, v, arms),
          );

    final card = _CorrectCard(
      draft: current,
      number: current == null ? null : _rowNumber(current),
      staff: staff,
      money: money,
      changed: changed.length,
      onNext: changed.isEmpty
          ? null
          : () {
              final from = current == null ? -1 : _drafts.indexOf(current);
              final next = changed.firstWhere((d) => _drafts.indexOf(d) > from, orElse: () => changed.first);
              setState(() {
                _tab = _Tab.all;
                _sel = (_drafts.indexOf(next), _sel?.$2 ?? 4);
              });
            },
      onUndo: current == null || !current.hasChanges ? null : () => setState(current.reset),
      onAside: () => setState(() => _aside = true),
    );

    final footer = Container(
      padding: const EdgeInsets.fromLTRB(24, 10, 10, 10),
      decoration: BoxDecoration(color: Sel.ink, borderRadius: BorderRadius.circular(SelRadius.card)),
      child: Row(
        children: [
          Text(
            changed.isEmpty ? 'No changes yet' : '${changed.length} ${changed.length == 1 ? 'row' : 'rows'} changed',
            style: SelType.body.copyWith(color: Sel.card, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: SelSpace.x4),
          Expanded(
            child: Text(
              changed.isEmpty
                  ? 'Click a cell to change it, as in a spreadsheet.'
                  : staff
                  ? () {
                      final n = changed.where((d) => d.original.status == 'approved').length;
                      return n == 0 ? 'They stay waiting for a pastor' : '$n ${n == 1 ? 'goes' : 'go'} back to your pastor';
                    }()
                  : delta == 0
                  ? 'No money moves, only who, when or which arm'
                  : 'The approved total changes by ${delta > 0 ? '+' : '−'}${money(delta.abs())}',
              overflow: TextOverflow.ellipsis,
              style: SelType.bodySm.copyWith(color: const Color(0xFFC9DEF3)),
            ),
          ),
          TextButton(
            onPressed: changed.isEmpty || _saving ? null : () => setState(() {
                    for (final d in _drafts) {
                      d.reset();
                    }
                  }),
            child: Text('Discard', style: SelType.button.copyWith(color: Sel.card)),
          ),
          const SizedBox(width: SelSpace.x2),
          Material(
            color: changed.isEmpty ? const Color(0xFF2A5884) : Sel.card,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: changed.isEmpty || _saving ? null : _save,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                child: Text(
                  _saving ? 'Saving…' : 'Save corrections',
                  style: SelType.button.copyWith(color: changed.isEmpty ? const Color(0xFF9DB8D3) : Sel.ink),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 900;
        final cardW = c.maxWidth < 1100 ? 320.0 : 356.0;
        final body = narrow
            ? SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    tabs,
                    const SizedBox(height: SelSpace.x2),
                    banner,
                    const SizedBox(height: SelSpace.x2),
                    sheet(shrinkWrap: true),
                    const SizedBox(height: SelSpace.x4),
                    card,
                  ],
                ),
              )
            : CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.bracketRight): () => setState(() => _aside = !_aside),
                },
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: EdgeInsets.only(right: _aside ? 96 : cardW + 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            tabs,
                            const SizedBox(height: SelSpace.x2),
                            banner,
                            const SizedBox(height: SelSpace.x2),
                            Expanded(child: sheet(shrinkWrap: false)),
                          ],
                        ),
                      ),
                    ),
                    if (!_aside)
                      Positioned(top: 0, right: 0, bottom: 6, width: cardW, child: card)
                    else
                      Positioned(
                        right: 0,
                        top: (c.maxHeight - 160) / 2,
                        child: _EdgeFlap(changed: changed.length, onTap: () => setState(() => _aside = false)),
                      ),
                  ],
                ),
              );
        return Padding(
          padding: const EdgeInsets.all(SelSpace.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: SelSpace.x3),
              if (_error != null) ...[
                SelError(message: _error!),
                const SizedBox(height: SelSpace.x3),
              ],
              Expanded(child: body),
              const SizedBox(height: SelSpace.x3),
              footer,
            ],
          ),
        );
      },
    );
  }
}

enum _Tab { all, changed, approved, waiting }

/// The row in hand: what changed on it, what saving will do, and the next
/// changed row. The cells themselves are changed in the sheet.
class _CorrectCard extends StatelessWidget {
  const _CorrectCard({
    required this.draft,
    required this.number,
    required this.staff,
    required this.money,
    required this.changed,
    required this.onNext,
    required this.onUndo,
    required this.onAside,
  });

  final BatchRowDraft? draft;
  final String? number;
  final bool staff;
  final String Function(double) money;
  final int changed;
  final VoidCallback? onNext;
  final VoidCallback? onUndo;
  final VoidCallback onAside;

  @override
  Widget build(BuildContext context) {
    final d = draft;
    final approved = d?.original.status == 'approved';
    return Container(
      decoration: BoxDecoration(
        color: Sel.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Sel.skyWash, width: 1.5),
        boxShadow: const [BoxShadow(color: Sel.skyWash, offset: Offset(0, 4))],
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 14, 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (number != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Sel.ink, borderRadius: BorderRadius.circular(SelRadius.pill)),
                    child: Text('Row $number', style: SelType.small.copyWith(color: Sel.card)),
                  ),
                const Spacer(),
                SelLink(label: 'Move aside', onTap: onAside),
              ],
            ),
            const SizedBox(height: SelSpace.x3),
            if (d == null)
              Text('Click a cell in the sheet to change it. What changed on that row shows here.', style: SelType.bodySm)
            else ...[
              Text('${d.partnerName}, ${DateFormat('d MMM').format(d.original.dateGiven)}', style: SelType.subtitle),
              Text(
                d.isLocked
                    ? 'Archived'
                    : approved
                    ? 'Approved${d.original.reviewedBySnapshot?['fullName'] == null ? '' : ' by ${d.original.reviewedBySnapshot!['fullName']}'}'
                    : 'Waiting for a pastor',
                style: SelType.small,
              ),
              const SizedBox(height: SelSpace.x3),
              if (d.hasChanges)
                for (final c in d.changes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      c[0].toUpperCase() + c.substring(1),
                      style: SelType.bodySm.copyWith(color: Sel.ink, fontWeight: FontWeight.w700),
                    ),
                  )
              else
                Text('Nothing changed on this row yet.', style: SelType.bodySm),
              const SizedBox(height: SelSpace.x3),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFF3F8FD), borderRadius: BorderRadius.circular(12)),
                child: Text(
                  d.isLocked
                      ? 'An archived row cannot be changed. Bring the import back from Imports first.'
                      : !approved
                      ? 'It stays waiting for a pastor.'
                      : staff
                      ? 'Saving sends this row back to your pastor to approve again.'
                      : 'It stays approved, and the totals move with your change.',
                  style: SelType.small.copyWith(color: Sel.text),
                ),
              ),
            ],
            const SizedBox(height: SelSpace.x4),
            if (changed > 0)
              SelButton.cyan(label: 'Next changed row', expanded: true, onPressed: onNext),
            if (onUndo != null) ...[
              const SizedBox(height: SelSpace.x2),
              Center(child: SelLink(label: 'Undo row $number', onTap: onUndo)),
            ],
          ],
        ),
      ),
    );
  }
}

class _EdgeFlap extends StatelessWidget {
  const _EdgeFlap({required this.changed, required this.onTap});

  final int changed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Sel.ink,
    borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
    child: InkWell(
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
      onTap: onTap,
      child: Container(
        width: 84,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.chevronLeft, size: 16, color: Sel.card),
            const SizedBox(height: 6),
            Text(
              changed == 0 ? 'Row card' : '$changed ${changed == 1 ? 'row' : 'rows'}',
              style: SelType.subtitle.copyWith(color: Sel.card, fontSize: 17, fontWeight: FontWeight.w800),
            ),
            if (changed > 0) Text('changed', style: SelType.small.copyWith(color: SelNavyCard.soft)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Sel.card, borderRadius: BorderRadius.circular(SelRadius.pill)),
              child: Text('Open', style: SelType.small.copyWith(color: Sel.ink, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    ),
  );
}
