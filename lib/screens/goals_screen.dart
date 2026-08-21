import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../design/seline.dart';
import '../features/arms/providers/arms_providers.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/goals/domain/partnership_goal.dart';
import '../features/goals/providers/goals_providers.dart';
import '../features/periods/providers/periods_providers.dart';

/// Goals — targets per arm for the active period.
///
/// Progress is a plain ink bar. A goal at 97% and a goal at 12% differ by bar
/// length and by the figure beneath, never by colour: turning a lagging goal
/// red would spend the accent budget on something the number already says.
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final money = ref.watch(churchMoneyFormatProvider);
    final goalsAsync = ref.watch(goalsListProvider);
    final arms = ref.watch(armsStreamProvider).valueOrNull ?? [];
    final period = ref.watch(activePeriodProvider);
    final canEdit = idx?.isPastor ?? false;

    String armName(String id) =>
        arms.where((a) => a.id == id).firstOrNull?.name ?? 'Partnership arm';

    return SelPageBody(
      onRefresh: () async => ref.invalidate(goalsListProvider),
      children: [
        SelPageTitle(
          title: 'Goals',
          subtitle: period == null
              ? 'No active period. Set one up in Configuration first.'
              : 'Targets for ${period.name}.',
          actions: [
            if (canEdit && period != null)
              SelButton.cyan(
                label: 'Set a target',
                icon: LucideIcons.plus,
                onPressed: () => _goalDialog(
                  context,
                  ref,
                  churchId: idx!.churchId,
                  uid: idx.uid,
                  periodId: period.id,
                  arms: arms,
                ),
              ),
          ],
        ),
        goalsAsync.when(
          loading: () => const SelCard(child: SelSkeletonRows(count: 3)),
          error: (e, _) => SelError(message: '$e'),
          data: (all) {
            final goals = period == null
                ? <PartnershipGoal>[]
                : all.where((g) => g.partnershipPeriodId == period.id).toList();

            if (goals.isEmpty) {
              return SelCard(
                child: SelEmpty(
                  title: 'No targets set',
                  message: period == null
                      ? 'Create an active period before setting targets.'
                      : 'Set a target for each arm you want to track this period.',
                  icon: LucideIcons.target,
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < goals.length; i++) ...[
                  if (i > 0) const SizedBox(height: SelSpace.x4),
                  SelCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SelGoalLine(
                            label: armName(goals[i].partnershipArmId),
                            value: goals[i].currentAmountCedis,
                            target: goals[i].targetAmountCedis,
                            valueText: money(goals[i].currentAmountCedis),
                            targetText: money(goals[i].targetAmountCedis),
                          ),
                        ),
                        if (canEdit) ...[
                          const SizedBox(width: SelSpace.x6),
                          SelButton(
                            label: 'Edit',
                            kind: SelButtonKind.quiet,
                            dense: true,
                            onPressed: () => _goalDialog(
                              context,
                              ref,
                              churchId: idx!.churchId,
                              uid: idx.uid,
                              periodId: period!.id,
                              arms: arms,
                              existing: goals[i],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

Future<void> _goalDialog(
  BuildContext context,
  WidgetRef ref, {
  required String churchId,
  required String uid,
  required String periodId,
  required List<dynamic> arms,
  PartnershipGoal? existing,
}) async {
  final amount = TextEditingController(
    text: existing == null ? '' : existing.targetAmountCedis.toStringAsFixed(0),
  );
  var armId = existing?.partnershipArmId ??
      (arms.isNotEmpty ? arms.first.id as String : null);

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => SelDialog(
        title: existing == null ? 'Set a target' : 'Edit target',
        width: 440,
        scrollable: false,
        actions: [
          SelButton(
            label: 'Cancel',
            kind: SelButtonKind.quiet,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          SelButton.cyan(
            label: 'Save',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (existing == null)
              SelSelect<String>(
                value: armId,
                label: 'Partnership arm',
                onChanged: (v) => setState(() => armId = v),
                items: [
                  for (final a in arms)
                    DropdownMenuItem(
                      value: a.id as String,
                      child: Text(a.name as String),
                    ),
                ],
              ),
            if (existing == null) const SizedBox(height: SelSpace.x4),
            SelField(
              controller: amount,
              label: 'Target amount',
              hint: '50000',
              keyboardType: TextInputType.number,
              autofocus: true,
            ),
          ],
        ),
      ),
    ),
  );

  if (saved != true) return;
  final value = double.tryParse(amount.text.replaceAll(',', '').trim());
  if (value == null || value <= 0) return;

  final repo = ref.read(goalsRepositoryProvider);
  if (existing == null) {
    if (armId == null) return;
    await repo.createGoal(
      churchId: churchId,
      uid: uid,
      partnershipPeriodId: periodId,
      partnershipArmId: armId!,
      targetAmountCedis: value,
    );
  } else {
    await repo.updateGoalTarget(
      churchId: churchId,
      goal: existing,
      targetAmountCedis: value,
    );
  }
}
