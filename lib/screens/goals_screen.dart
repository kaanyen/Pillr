import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../design/seline.dart';
import '../features/arms/providers/arms_providers.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/entries/providers/entries_providers.dart';
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
    final tree = ref.watch(armTreeProvider);
    final period = ref.watch(activePeriodProvider);
    final canEdit = idx?.isPastor ?? false;

    String armName(String id) =>
        arms.where((a) => a.id == id).firstOrNull?.name ?? 'Partnership arm';

    final now = DateTime.now();
    final daysLeft = period == null
        ? 0
        : period.endDate.difference(now).inDays.clamp(0, 99999);
    final spanDays = period == null
        ? 1
        : period.endDate.difference(period.startDate).inDays.clamp(1, 99999);
    final elapsed = period == null
        ? 0.0
        : (now.difference(period.startDate).inDays / spanDays).clamp(0.0, 1.0);
    final waiting = (ref.watch(pendingEntriesProvider).valueOrNull ?? const [])
        .fold<double>(0, (s, e) => s + e.amountCedis);

    return SelPageBody(
      onRefresh: () async => ref.invalidate(goalsListProvider),
      children: [
        SelPageTitle(
          title: 'Goals',
          subtitle: period == null
              ? 'No active period. Set one up in Configuration first.'
              : '${period.name} · ${DateFormat('d MMM').format(period.startDate)} to '
                    '${DateFormat('d MMM').format(period.endDate)} · $daysLeft days left',
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
                : all
                      .where(
                        (g) =>
                            g.partnershipPeriodId == period.id &&
                            isShownGoal(tree, g),
                      )
                      .toList();

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

            final reached = {
              for (final g in goals) g.id: ref.watch(goalReachedCedisProvider(g)),
            };
            final target = goals.fold<double>(0, (s, g) => s + g.targetAmountCedis);
            final approved = goals.fold<double>(0, (s, g) => s + reached[g.id]!);
            final toGo = (target - approved).clamp(0, double.infinity);
            final paceGap = approved - target * elapsed;
            final behind = goals
                .where((g) => reached[g.id]! < g.targetAmountCedis * elapsed)
                .length;
            final perDay = daysLeft == 0 ? toGo : toGo / daysLeft;
            final armsWord = switch (goals.length) {
              1 => 'one arm',
              2 => 'two arms',
              3 => 'three arms',
              _ => '${goals.length} arms',
            };

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelCard(
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                  child: Wrap(
                    spacing: SelSpace.x8,
                    runSpacing: SelSpace.x4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              toGo == 0
                                  ? 'Every target reached'
                                  : '${money(toGo)} to go across $armsWord',
                              style: SelType.subtitle,
                            ),
                            const SizedBox(height: SelSpace.x1),
                            Text.rich(
                              TextSpan(
                                style: SelType.body.copyWith(color: Sel.text),
                                children: [
                                  TextSpan(
                                    text: behind == 0
                                        ? 'Every arm is ahead of the pace for ${DateFormat('d MMM').format(period!.endDate)}. '
                                        : '${behind == goals.length ? 'Every arm is' : '$behind of ${goals.length} arms are'} behind the pace for '
                                              '${DateFormat('d MMM').format(period!.endDate)}, by ${money(paceGap.abs())} in all. ',
                                  ),
                                  if (toGo > 0) ...[
                                    const TextSpan(
                                      text: 'From today the church needs about ',
                                    ),
                                    TextSpan(
                                      text: '${money(perDay)} a day',
                                      style: const TextStyle(
                                        color: Sel.ink,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const TextSpan(text: '.'),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Figure(label: 'Approved', value: money(approved)),
                          const SizedBox(width: SelSpace.x8),
                          _Figure(label: 'All targets', value: money(target)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: SelSpace.x4),
                SelCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < goals.length; i++) ...[
                        if (i > 0) const Divider(height: 1, color: Sel.rowLine),
                        _GoalRow(
                          name: armName(goals[i].partnershipArmId),
                          target: goals[i].targetAmountCedis,
                          reached: reached[goals[i].id]!,
                          elapsed: elapsed,
                          daysLeft: daysLeft,
                          money: money,
                          onEdit: canEdit
                              ? () => _goalDialog(
                                  context,
                                  ref,
                                  churchId: idx!.churchId,
                                  uid: idx.uid,
                                  periodId: period.id,
                                  arms: arms,
                                  existing: goals[i],
                                )
                              : null,
                        ),
                      ],
                      const Divider(height: 1, color: Sel.border),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 14, 28, 16),
                        child: Wrap(
                          spacing: SelSpace.x6,
                          runSpacing: SelSpace.x2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _Key(
                              swatch: Container(
                                width: 18,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: Sel.sky,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              label: 'Approved so far',
                            ),
                            _Key(
                              swatch: Container(width: 2, height: 14, color: Sel.ink),
                              label: 'Where the arm should be today',
                            ),
                            Text(
                              waiting == 0
                                  ? 'Waiting entries count once approved.'
                                  : "Waiting entries don't count until approved: ${money(waiting)} is in the queue.",
                              style: SelType.small,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: SelType.small),
      Text(
        value,
        style: SelType.subtitle.copyWith(fontSize: 26, fontWeight: FontWeight.w800),
      ),
    ],
  );
}

class _Key extends StatelessWidget {
  const _Key({required this.swatch, required this.label});

  final Widget swatch;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [swatch, const SizedBox(width: SelSpace.x2), Text(label, style: SelType.small)],
  );
}

/// One arm: its target, what is approved, a bar with today's pace marked,
/// what is left, and whether it is ahead or behind.
class _GoalRow extends StatelessWidget {
  const _GoalRow({
    required this.name,
    required this.target,
    required this.reached,
    required this.elapsed,
    required this.daysLeft,
    required this.money,
    this.onEdit,
  });

  final String name;
  final double target;
  final double reached;
  final double elapsed;
  final int daysLeft;
  final String Function(num) money;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final left = (target - reached).clamp(0, double.infinity);
    final gap = reached - target * elapsed;
    final perDay = daysLeft == 0 ? left : left / daysLeft;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
      child: LayoutBuilder(
        builder: (context, c) {
          final head = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: SelType.subtitle),
              Row(
                children: [
                  Text('Target ${money(target)}', style: SelType.small),
                  if (onEdit != null) ...[
                    Text(' · ', style: SelType.small),
                    InkWell(
                      onTap: onEdit,
                      child: Text(
                        'Edit',
                        style: SelType.small.copyWith(
                          color: Sel.cyanEdge,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );
          final bar = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(money(reached), style: SelType.subtitleSm.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 4),
                  Text('approved', style: SelType.bodySm.copyWith(color: Sel.text)),
                  const Spacer(),
                  Text(left == 0 ? 'Reached' : '${money(left)} to go', style: SelType.small),
                ],
              ),
              const SizedBox(height: SelSpace.x2),
              SizedBox(
                height: 24,
                child: LayoutBuilder(
                  builder: (context, b) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: Sel.track,
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      Container(
                        height: 14,
                        width: b.maxWidth * (target == 0 ? 0 : (reached / target).clamp(0.0, 1.0)),
                        decoration: BoxDecoration(
                          color: Sel.sky,
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      Positioned(
                        left: (b.maxWidth * elapsed - 1).clamp(0, b.maxWidth - 2),
                        child: Container(width: 2, height: 24, color: Sel.ink),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
          final pace = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: gap >= 0 ? Sel.successWash : Sel.skyWash,
                  borderRadius: BorderRadius.circular(SelRadius.pill),
                ),
                child: Text(
                  '${money(gap.abs())} ${gap >= 0 ? 'ahead of' : 'behind'} pace',
                  style: SelType.tag,
                ),
              ),
              if (left > 0) ...[
                const SizedBox(height: SelSpace.x1),
                Text('Needs ${money(perDay)} a day', style: SelType.small),
              ],
            ],
          );
          if (c.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [head, const SizedBox(height: SelSpace.x3), bar, const SizedBox(height: SelSpace.x3), pace],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(width: 240, child: head),
              Expanded(child: bar),
              const SizedBox(width: SelSpace.x8),
              SizedBox(width: 220, child: pace),
            ],
          );
        },
      ),
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
  final mains = ref.read(armTreeProvider).mains;
  var armId = existing?.partnershipArmId ?? (mains.isNotEmpty ? mains.first.id : null);

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
                  for (final a in ref.read(armTreeProvider).mains)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
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
