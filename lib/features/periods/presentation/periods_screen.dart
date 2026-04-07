import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../common/widgets/pillr_button.dart';
import '../../../common/widgets/pillr_confirmation_dialog.dart';
import '../../../common/widgets/pillr_data_table.dart';
import '../../../common/widgets/pillr_empty_state.dart';
import '../../../common/widgets/pillr_error_state.dart';
import '../../../common/widgets/pillr_loading_shimmer.dart';
import '../../../common/widgets/pillr_text_field.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../activity/activity_log_helper.dart';
import '../../auth/providers/auth_providers.dart';
import '../domain/partnership_period.dart';
import '../providers/periods_providers.dart';

class PeriodsScreen extends ConsumerWidget {
  const PeriodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final periods = ref.watch(periodsStreamProvider);
    final width = MediaQuery.sizeOf(context).width;

    if (idx != null && !idx.isPastor) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            'Partnership periods are managed by pastors.',
            style: AppTypography.body,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Partnership periods', style: AppTypography.heading2),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Only one period can be active at a time. Activating a period deactivates all others.',
                      style: AppTypography.body,
                    ),
                  ],
                ),
              ),
              PillrButton(
                label: '+ Add period',
                icon: Icons.add,
                onPressed: idx == null
                    ? null
                    : () => _openEditor(context, ref, churchId: idx.churchId, uid: idx.uid, existing: null),
                variant: PillrButtonVariant.primary,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          periods.when(
            loading: () => const PillrLoadingShimmer(height: 200),
            error: (e, _) => PillrErrorState(
              message: e.toString(),
              onRetry: () => ref.invalidate(periodsStreamProvider),
            ),
            data: (rows) {
              if (rows.isEmpty) {
                return PillrEmptyState(
                  title: 'No periods yet',
                  message: 'Create a period (e.g. Q1 2026), then activate it when ready.',
                  actionLabel: 'Add period',
                  onAction: idx == null
                      ? null
                      : () => _openEditor(context, ref, churchId: idx.churchId, uid: idx.uid, existing: null),
                );
              }
              final df = DateFormat.yMMMd();
              return PillrDataTable(
                minWidth: width > 800 ? width - AppSpacing.lg * 2 : 800,
                columns: [
                  DataColumn2(
                    label: Text('NAME', style: AppTypography.tableHeader),
                    size: ColumnSize.L,
                  ),
                  DataColumn2(label: Text('RANGE', style: AppTypography.tableHeader)),
                  DataColumn2(label: Text('ACTIVE', style: AppTypography.tableHeader)),
                  DataColumn2(label: Text('TOTAL ₵', style: AppTypography.tableHeader)),
                  DataColumn2(
                    label: Text('ACTIONS', style: AppTypography.tableHeader),
                    fixedWidth: 220,
                  ),
                ],
                rows: [
                  for (final r in rows)
                    DataRow(
                      cells: [
                        DataCell(Text(r.name, style: AppTypography.body.copyWith(fontWeight: FontWeight.w600))),
                        DataCell(Text(
                          '${df.format(r.startDate)} – ${df.format(r.endDate)}',
                          style: AppTypography.body,
                        )),
                        DataCell(
                          r.isActive
                              ? const Icon(Icons.check_circle, color: AppColors.successColor, size: 20)
                              : const Icon(Icons.circle_outlined, color: AppColors.gray400, size: 20),
                        ),
                        DataCell(Text(r.totalApprovedAmount.toStringAsFixed(2), style: AppTypography.body)),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!r.isActive)
                                TextButton(
                                  onPressed: idx == null
                                      ? null
                                      : () => _confirmActivate(context, ref, idx.churchId, r),
                                  child: const Text('Activate'),
                                ),
                              TextButton(
                                onPressed: idx == null
                                    ? null
                                    : () => _openEditor(context, ref, churchId: idx.churchId, uid: idx.uid, existing: r),
                                child: const Text('Edit'),
                              ),
                              TextButton(
                                onPressed: idx == null
                                    ? null
                                    : () => _confirmDelete(context, ref, idx.churchId, r),
                                child: Text('Delete', style: AppTypography.caption.copyWith(color: AppColors.dangerColor)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static Future<void> _confirmActivate(
    BuildContext context,
    WidgetRef ref,
    String churchId,
    PartnershipPeriod period,
  ) async {
    final ok = await showPillrConfirmationDialog(
      context: context,
      title: 'Activate this period?',
      message:
          '“${period.name}” becomes the active period. Every other period will be deactivated. Continue?',
      confirmLabel: 'Activate',
      confirmVariant: PillrButtonVariant.primary,
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(periodsRepositoryProvider).activatePeriod(churchId: churchId, periodId: period.id);
      await logPillrActivity(
        ref,
        churchId: churchId,
        action: 'period.activate',
        entityType: 'period',
        entityId: period.id,
        entitySnapshot: {'name': period.name},
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Period activated.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  static Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String churchId,
    PartnershipPeriod period,
  ) async {
    final repo = ref.read(periodsRepositoryProvider);
    final hasEntries = await repo.hasEntriesForPeriod(churchId, period.id);
    if (!context.mounted) return;
    if (hasEntries) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot delete: entries exist for this period.')),
        );
      }
      return;
    }
    final ok = await showPillrConfirmationDialog(
      context: context,
      title: 'Delete period?',
      message: 'Remove “${period.name}”?',
    );
    if (ok != true || !context.mounted) return;
    try {
      await repo.deletePeriod(churchId: churchId, periodId: period.id);
      await logPillrActivity(
        ref,
        churchId: churchId,
        action: 'period.delete',
        entityType: 'period',
        entityId: period.id,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Period deleted.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  static Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    required String churchId,
    required String uid,
    required PartnershipPeriod? existing,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _PeriodEditorDialog(
        churchId: churchId,
        uid: uid,
        existing: existing,
      ),
    );
  }
}

class _PeriodEditorDialog extends ConsumerStatefulWidget {
  const _PeriodEditorDialog({
    required this.churchId,
    required this.uid,
    this.existing,
  });

  final String churchId;
  final String uid;
  final PartnershipPeriod? existing;

  @override
  ConsumerState<_PeriodEditorDialog> createState() => _PeriodEditorDialogState();
}

class _PeriodEditorDialogState extends ConsumerState<_PeriodEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  DateTime? _start;
  DateTime? _end;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _start = e?.startDate;
    _end = e?.endDate;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    if (_start == null || _end == null) {
      setState(() => _error = 'Start and end dates are required.');
      return;
    }
    if (!_end!.isAfter(_start!)) {
      setState(() => _error = 'End date must be after start date.');
      return;
    }
    setState(() => _loading = true);
    final repo = ref.read(periodsRepositoryProvider);
    try {
      if (widget.existing == null) {
        await repo.createPeriod(
          churchId: widget.churchId,
          uid: widget.uid,
          name: _name.text,
          description: _description.text,
          startDate: _start!,
          endDate: _end!,
        );
        await logPillrActivity(
          ref,
          churchId: widget.churchId,
          action: 'period.create',
          entityType: 'period',
        );
      } else {
        await repo.updatePeriod(
          churchId: widget.churchId,
          period: widget.existing!,
          name: _name.text,
          description: _description.text,
          startDate: _start!,
          endDate: _end!,
        );
        await logPillrActivity(
          ref,
          churchId: widget.churchId,
          action: 'period.update',
          entityType: 'period',
          entityId: widget.existing!.id,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _start ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (d != null) setState(() => _start = d);
  }

  Future<void> _pickEnd() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _end ?? _start ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 6),
    );
    if (d != null) setState(() => _end = d);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit period' : 'Add period', style: AppTypography.heading3),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PillrTextField(controller: _name, label: 'Name', hint: 'e.g. Q1 2026'),
            const SizedBox(height: AppSpacing.md),
            PillrTextField(controller: _description, label: 'Description (optional)', maxLines: 2),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickStart,
                    child: Text(_start == null ? 'Start date' : DateFormat.yMMMd().format(_start!)),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickEnd,
                    child: Text(_end == null ? 'End date' : DateFormat.yMMMd().format(_end!)),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: AppTypography.caption.copyWith(color: AppColors.dangerColor)),
            ],
          ],
        ),
      ),
      actions: [
        PillrButton(
          label: 'Cancel',
          variant: PillrButtonVariant.ghost,
          onPressed: _loading ? null : () => Navigator.pop(context),
        ),
        PillrButton(
          label: isEdit ? 'Save' : 'Create',
          loading: _loading,
          onPressed: _loading ? null : _save,
          variant: PillrButtonVariant.primary,
        ),
      ],
    );
  }
}
