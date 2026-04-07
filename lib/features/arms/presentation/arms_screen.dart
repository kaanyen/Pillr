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
import '../domain/partnership_arm.dart';
import '../providers/arms_providers.dart';

class ArmsScreen extends ConsumerWidget {
  const ArmsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final arms = ref.watch(armsStreamProvider);
    final width = MediaQuery.sizeOf(context).width;

    if (idx != null && !idx.isPastor) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            'Partnership arms are managed by pastors.',
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
                    Text('Partnership arms', style: AppTypography.heading2),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Categories for giving (e.g. Venue, Rhapsody). Toggle inactive arms to hide them from new entries.',
                      style: AppTypography.body,
                    ),
                  ],
                ),
              ),
              PillrButton(
                label: '+ Add arm',
                icon: Icons.add,
                onPressed: idx == null
                    ? null
                    : () => _openEditor(
                          context,
                          ref,
                          churchId: idx.churchId,
                          uid: idx.uid,
                          existing: null,
                        ),
                variant: PillrButtonVariant.primary,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          arms.when(
            loading: () => const PillrLoadingShimmer(height: 200),
            error: (e, _) => PillrErrorState(
              message: e.toString(),
              onRetry: () => ref.invalidate(armsStreamProvider),
            ),
            data: (rows) {
              if (rows.isEmpty) {
                return PillrEmptyState(
                  title: 'No arms yet',
                  message: 'Add your first partnership arm to start recording entries against it.',
                  actionLabel: 'Add arm',
                  onAction: idx == null
                      ? null
                      : () => _openEditor(
                            context,
                            ref,
                            churchId: idx.churchId,
                            uid: idx.uid,
                            existing: null,
                          ),
                );
              }
              final df = DateFormat.MMMd().add_jm();
              return PillrDataTable(
                minWidth: width > 800 ? width - AppSpacing.lg * 2 : 720,
                sortColumnIndex: 0,
                sortAscending: true,
                columns: [
                  DataColumn2(
                    label: Text('NAME', style: AppTypography.tableHeader),
                    size: ColumnSize.L,
                  ),
                  DataColumn2(label: Text('COLOR', style: AppTypography.tableHeader)),
                  DataColumn2(label: Text('STATUS', style: AppTypography.tableHeader)),
                  DataColumn2(label: Text('UPDATED', style: AppTypography.tableHeader)),
                  DataColumn2(
                    label: Text('ACTIONS', style: AppTypography.tableHeader),
                    fixedWidth: 140,
                  ),
                ],
                rows: [
                  for (final r in rows)
                    DataRow(
                      cells: [
                        DataCell(
                          Text(
                            r.name,
                            style: AppTypography.body.copyWith(
                              color: AppColors.gray900,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        DataCell(_colorSwatch(r.colorHex)),
                        DataCell(
                          Switch.adaptive(
                            value: r.isActive,
                            onChanged: idx == null
                                ? null
                                : (v) => _setActive(context, ref, idx.churchId, r, v),
                          ),
                        ),
                        DataCell(Text(df.format(r.updatedAt.toLocal()), style: AppTypography.body)),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: idx == null
                                    ? null
                                    : () => _openEditor(
                                          context,
                                          ref,
                                          churchId: idx.churchId,
                                          uid: idx.uid,
                                          existing: r,
                                        ),
                                child: const Text('Edit'),
                              ),
                              TextButton(
                                onPressed: idx == null
                                    ? null
                                    : () => _confirmDelete(context, ref, idx.churchId, r),
                                child: Text(
                                  'Delete',
                                  style: AppTypography.caption.copyWith(color: AppColors.dangerColor),
                                ),
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

  static Widget _colorSwatch(String? hex) {
    if (hex == null || hex.isEmpty) {
      return Text('—', style: AppTypography.caption.copyWith(color: AppColors.gray400));
    }
    Color? c;
    try {
      final h = hex.replaceFirst('#', '');
      c = Color(int.parse('FF$h', radix: 16));
    } catch (_) {
      c = null;
    }
    if (c == null) {
      return Text(hex, style: AppTypography.caption);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.gray200),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(hex, style: AppTypography.caption),
      ],
    );
  }

  static Future<void> _setActive(
    BuildContext context,
    WidgetRef ref,
    String churchId,
    PartnershipArm arm,
    bool value,
  ) async {
    try {
      await ref.read(armsRepositoryProvider).setActive(
            churchId: churchId,
            armId: arm.id,
            isActive: value,
          );
      await logPillrActivity(
        ref,
        churchId: churchId,
        action: value ? 'arm.activate' : 'arm.deactivate',
        entityType: 'arm',
        entityId: arm.id,
        entitySnapshot: {'name': arm.name},
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update: $e')),
        );
      }
    }
  }

  static Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String churchId,
    PartnershipArm arm,
  ) async {
    final ok = await showPillrConfirmationDialog(
      context: context,
      title: 'Delete arm?',
      message: 'Remove “${arm.name}”? Existing entries that reference this arm are not deleted.',
      confirmLabel: 'Delete',
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(armsRepositoryProvider).deleteArm(churchId: churchId, armId: arm.id);
      await logPillrActivity(
        ref,
        churchId: churchId,
        action: 'arm.delete',
        entityType: 'arm',
        entityId: arm.id,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Arm deleted.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete: $e')),
        );
      }
    }
  }

  static Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    required String churchId,
    required String uid,
    required PartnershipArm? existing,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ArmEditorDialog(
        churchId: churchId,
        uid: uid,
        existing: existing,
      ),
    );
  }
}

class _ArmEditorDialog extends ConsumerStatefulWidget {
  const _ArmEditorDialog({
    required this.churchId,
    required this.uid,
    this.existing,
  });

  final String churchId;
  final String uid;
  final PartnershipArm? existing;

  @override
  ConsumerState<_ArmEditorDialog> createState() => _ArmEditorDialogState();
}

class _ArmEditorDialogState extends ConsumerState<_ArmEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _color;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _color = TextEditingController(text: e?.colorHex ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _color.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _error = null;
    });
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    final hex = normalizeArmColorHex(_color.text.trim().isEmpty ? null : _color.text.trim());
    if (_color.text.trim().isNotEmpty && hex == null) {
      setState(() => _error = 'Use a 6-digit hex color, e.g. 1A56DB or #1A56DB.');
      return;
    }
    setState(() => _loading = true);
    final repo = ref.read(armsRepositoryProvider);
    try {
      if (widget.existing == null) {
        await repo.createArm(
          churchId: widget.churchId,
          uid: widget.uid,
          name: name,
          description: _description.text,
          colorHex: _color.text.trim().isEmpty ? null : _color.text,
        );
        await logPillrActivity(
          ref,
          churchId: widget.churchId,
          action: 'arm.create',
          entityType: 'arm',
        );
      } else {
        await repo.updateArm(
          churchId: widget.churchId,
          arm: widget.existing!,
          name: name,
          description: _description.text,
          isActive: widget.existing!.isActive,
          colorHex: _color.text.trim().isEmpty ? null : _color.text,
        );
        await logPillrActivity(
          ref,
          churchId: widget.churchId,
          action: 'arm.update',
          entityType: 'arm',
          entityId: widget.existing!.id,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit arm' : 'Add partnership arm', style: AppTypography.heading3),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PillrTextField(
              controller: _name,
              label: 'Name',
              hint: 'e.g. Venue',
            ),
            const SizedBox(height: AppSpacing.md),
            PillrTextField(
              controller: _description,
              label: 'Description (optional)',
              maxLines: 2,
            ),
            const SizedBox(height: AppSpacing.md),
            PillrTextField(
              controller: _color,
              label: 'Color (optional)',
              hint: '#1A56DB',
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
