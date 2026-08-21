import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/utils/date_utils.dart';
import '../design/seline.dart';
import '../features/arms/domain/partnership_arm.dart';
import '../features/arms/providers/arms_providers.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/periods/domain/partnership_period.dart';
import '../features/periods/providers/periods_providers.dart';

/// Configuration — Partnership arms and Periods, merged.
///
/// Both are set-up-once structures that a church touches at the start of a
/// season and then leaves alone, and neither was ever used without the other:
/// a goal needs an arm *and* a period to mean anything. One screen, two
/// sections, on the same page.
class ConfigurationScreen extends ConsumerWidget {
  const ConfigurationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final money = ref.watch(churchMoneyFormatProvider);
    final arms = ref.watch(armsStreamProvider);
    final periods = ref.watch(periodsStreamProvider);
    final canEdit = (idx?.isPastor ?? false) || (idx?.isAdmin ?? false);

    return SelPageBody(
      onRefresh: () async {
        ref.invalidate(armsStreamProvider);
        ref.invalidate(periodsStreamProvider);
      },
      children: [
        const SelPageTitle(
          title: 'Configuration',
          subtitle:
              'The partnership arms your church gives to, and the periods you '
              'measure them over.',
        ),

        SelPanel(
          title: 'Partnership arms',
          subtitle: 'What partners can give toward.',
          trailing: canEdit
              ? SelButton(
                  label: 'Add arm',
                  icon: LucideIcons.plus,
                  dense: true,
                  onPressed: () => _armDialog(context, ref, idx!.churchId, idx.uid),
                )
              : null,
          contentPadding: EdgeInsets.zero,
          child: arms.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(SelSpace.cardPad),
              child: SelSkeletonRows(count: 3),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(SelSpace.cardPad),
              child: SelError(message: '$e'),
            ),
            data: (list) => list.isEmpty
                ? const SelEmpty(
                    title: 'No arms yet',
                    message: 'Add the causes your church partners toward.',
                    icon: LucideIcons.heartHandshake,
                  )
                : Column(
                    children: [
                      for (var i = 0; i < list.length; i++) ...[
                        if (i > 0) const Divider(height: 1, color: Sel.border),
                        _ArmRow(
                          arm: list[i],
                          canEdit: canEdit,
                          churchId: idx!.churchId,
                          uid: idx.uid,
                        ),
                      ],
                    ],
                  ),
          ),
        ),

        const SelSectionGap(factor: 0.5),

        SelPanel(
          title: 'Periods',
          subtitle: 'Exactly one period is active at a time.',
          trailing: canEdit
              ? SelButton(
                  label: 'Add period',
                  icon: LucideIcons.plus,
                  dense: true,
                  onPressed: () => _periodDialog(context, ref, idx!.churchId, idx.uid),
                )
              : null,
          contentPadding: EdgeInsets.zero,
          child: periods.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(SelSpace.cardPad),
              child: SelSkeletonRows(count: 2),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(SelSpace.cardPad),
              child: SelError(message: '$e'),
            ),
            data: (list) => list.isEmpty
                ? const SelEmpty(
                    title: 'No periods yet',
                    message: 'Create a period to start measuring partnership.',
                    icon: LucideIcons.calendar,
                  )
                : Column(
                    children: [
                      for (var i = 0; i < list.length; i++) ...[
                        if (i > 0) const Divider(height: 1, color: Sel.border),
                        _PeriodRow(
                          period: list[i],
                          canEdit: canEdit,
                          churchId: idx!.churchId,
                          money: money,
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _ArmRow extends ConsumerWidget {
  const _ArmRow({
    required this.arm,
    required this.canEdit,
    required this.churchId,
    required this.uid,
  });

  final PartnershipArm arm;
  final bool canEdit;
  final String churchId;
  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SelSpace.cardPad,
        vertical: SelSpace.x3,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(arm.name, style: SelType.bodyMedium),
                if (arm.description != null && arm.description!.isNotEmpty)
                  Text(arm.description!, style: SelType.small),
              ],
            ),
          ),
          SelStatusMark(
            status: arm.isActive ? SelStatus.active : SelStatus.inactive,
            label: arm.isActive ? 'Active' : 'Inactive',
          ),
          if (canEdit) ...[
            const SizedBox(width: SelSpace.x4),
            SelButton(
              label: 'Edit',
              kind: SelButtonKind.quiet,
              dense: true,
              onPressed: () => _armDialog(context, ref, churchId, uid, existing: arm),
            ),
            SelButton(
              label: arm.isActive ? 'Deactivate' : 'Activate',
              kind: SelButtonKind.quiet,
              dense: true,
              onPressed: () => ref.read(armsRepositoryProvider).setActive(
                    churchId: churchId,
                    armId: arm.id,
                    isActive: !arm.isActive,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PeriodRow extends ConsumerWidget {
  const _PeriodRow({
    required this.period,
    required this.canEdit,
    required this.churchId,
    required this.money,
  });

  final PartnershipPeriod period;
  final bool canEdit;
  final String churchId;
  final String Function(num) money;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range =
        '${formatFirestoreDate(period.startDate, pattern: 'd MMM y')} — '
        '${formatFirestoreDate(period.endDate, pattern: 'd MMM y')}';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SelSpace.cardPad,
        vertical: SelSpace.x3,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(period.name, style: SelType.bodyMedium),
                Text(range, style: SelType.small),
              ],
            ),
          ),
          Text(money(period.totalApprovedAmount), style: SelType.bodyMuted),
          const SizedBox(width: SelSpace.x6),
          SelStatusMark(
            status: period.isActive ? SelStatus.active : SelStatus.inactive,
            label: period.isActive ? 'Active' : 'Closed',
          ),
          if (canEdit && !period.isActive) ...[
            const SizedBox(width: SelSpace.x4),
            SelButton(
              label: 'Make active',
              kind: SelButtonKind.edge,
              dense: true,
              onPressed: () async {
                final ok = await selConfirm(
                  context,
                  title: 'Activate ${period.name}?',
                  message:
                      'The current active period will be closed. New entries '
                      'will be recorded against this one.',
                  confirmLabel: 'Activate',
                );
                if (!ok) return;
                await ref.read(periodsRepositoryProvider).activatePeriod(
                      churchId: churchId,
                      periodId: period.id,
                    );
              },
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _armDialog(
  BuildContext context,
  WidgetRef ref,
  String churchId,
  String uid, {
  PartnershipArm? existing,
}) async {
  final name = TextEditingController(text: existing?.name ?? '');
  final desc = TextEditingController(text: existing?.description ?? '');

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => SelDialog(
      title: existing == null ? 'New partnership arm' : 'Edit arm',
      width: 460,
      scrollable: false,
      actions: [
        SelButton(
          label: 'Cancel',
          kind: SelButtonKind.quiet,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        SelButton.cyan(
          label: existing == null ? 'Create' : 'Save',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SelField(controller: name, label: 'Name', hint: 'Missions', autofocus: true),
          const SizedBox(height: SelSpace.x4),
          SelField(
            controller: desc,
            label: 'Description',
            hint: 'Optional — what this arm supports',
            maxLines: 2,
          ),
        ],
      ),
    ),
  );

  if (saved != true || name.text.trim().isEmpty) return;
  final repo = ref.read(armsRepositoryProvider);
  if (existing == null) {
    await repo.createArm(
      churchId: churchId,
      uid: uid,
      name: name.text,
      description: desc.text,
    );
  } else {
    await repo.updateArm(
      churchId: churchId,
      arm: existing,
      name: name.text,
      description: desc.text,
      isActive: existing.isActive,
      colorHex: existing.colorHex,
    );
  }
}

Future<void> _periodDialog(
  BuildContext context,
  WidgetRef ref,
  String churchId,
  String uid,
) async {
  final name = TextEditingController();
  var start = DateTime.now();
  var end = DateTime.now().add(const Duration(days: 90));

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => SelDialog(
        title: 'New period',
        width: 460,
        scrollable: false,
        actions: [
          SelButton(
            label: 'Cancel',
            kind: SelButtonKind.quiet,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          SelButton.cyan(
            label: 'Create',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SelField(
              controller: name,
              label: 'Name',
              hint: 'Q1 2027 Partnership',
              autofocus: true,
            ),
            const SizedBox(height: SelSpace.x4),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'Starts',
                    value: start,
                    onPick: (d) => setState(() => start = d),
                  ),
                ),
                const SizedBox(width: SelSpace.x3),
                Expanded(
                  child: _DateField(
                    label: 'Ends',
                    value: end,
                    onPick: (d) => setState(() => end = d),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  if (saved != true || name.text.trim().isEmpty) return;
  await ref.read(periodsRepositoryProvider).createPeriod(
        churchId: churchId,
        uid: uid,
        name: name.text,
        startDate: start,
        endDate: end,
      );
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onPick,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    return SelField(
      label: label,
      readOnly: true,
      controller: TextEditingController(
        text: formatFirestoreDate(value, pattern: 'd MMM y'),
      ),
      suffixIcon: const Icon(LucideIcons.calendar, size: 14, color: Sel.ash),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (picked != null) onPick(picked);
      },
    );
  }
}
