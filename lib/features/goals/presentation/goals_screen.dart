import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../common/widgets/pillr_button.dart';
import '../../../common/widgets/pillr_card.dart';
import '../../../common/widgets/pillr_loading_shimmer.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_utils.dart';
import '../../activity/activity_log_helper.dart';
import '../../arms/domain/partnership_arm.dart';
import '../../arms/providers/arms_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../periods/domain/partnership_period.dart';
import '../../periods/providers/periods_providers.dart';
import '../domain/partnership_goal.dart';
import '../providers/goals_providers.dart';

class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key});

  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen> {
  final List<PartnershipGoal> _items = [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  bool _scheduledInitial = false;

  void _ensureInitialLoad() {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null || !idx.isPastor || _scheduledInitial) return;
    _scheduledInitial = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadFirst();
    });
  }

  Future<void> _loadFirst() async {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null || !idx.isPastor) return;
    setState(() => _loading = true);
    try {
      final page = await ref.read(goalsRepositoryProvider).fetchGoalsPage(
            idx.churchId,
            pageSize: 20,
          );
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _cursor = page.lastDoc;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null || !idx.isPastor) return;
    setState(() => _loadingMore = true);
    try {
      final page = await ref.read(goalsRepositoryProvider).fetchGoalsPage(
            idx.churchId,
            pageSize: 20,
            startAfter: _cursor,
          );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.lastDoc;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  String _periodName(List<PartnershipPeriod> periods, String id) {
    for (final p in periods) {
      if (p.id == id) return p.name;
    }
    return id;
  }

  String _armName(List<PartnershipArm> arms, String id) {
    for (final a in arms) {
      if (a.id == id) return a.name;
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final periodsAsync = ref.watch(periodsStreamProvider);
    final armsAsync = ref.watch(armsStreamProvider);

    ref.listen(userChurchIndexProvider, (prev, next) {
      final pa = prev?.valueOrNull?.churchId;
      final na = next.valueOrNull?.churchId;
      if (pa != na) {
        _items.clear();
        _cursor = null;
        _hasMore = true;
        _scheduledInitial = false;
        _ensureInitialLoad();
      }
    });

    return periodsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (periods) {
        return armsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (arms) {
            final idx = ref.watch(userChurchIndexProvider).valueOrNull;
            final profile = ref.watch(churchUserProfileProvider).valueOrNull;
            if (idx != null && idx.isPastor) {
              _ensureInitialLoad();
            }

            return Scaffold(
              body: RefreshIndicator(
                onRefresh: () async {
                  await _loadFirst();
                  ref.invalidate(goalsListProvider);
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Goals', style: AppTypography.heading2),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Set a target per period and arm. Approved entries update progress automatically.',
                      style: AppTypography.body,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_loading)
                      const PillrLoadingShimmer(height: 120)
                    else if (_items.isEmpty)
                      PillrCard(
                        child: Text('No goals yet. Add one to track progress.', style: AppTypography.body),
                      )
                    else ...[
                      for (final g in _items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: PillrCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${_periodName(periods, g.partnershipPeriodId)} · ${_armName(arms, g.partnershipArmId)}',
                                        style: AppTypography.heading3,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Edit target',
                                      icon: const Icon(LucideIcons.pencil),
                                      onPressed: idx == null || profile == null
                                          ? null
                                          : () => _editGoal(context, ref, idx.churchId, g),
                                    ),
                                    IconButton(
                                      tooltip: 'Delete',
                                      icon: Icon(LucideIcons.trash2, color: AppColors.dangerColor),
                                      onPressed: idx == null || profile == null
                                          ? null
                                          : () => _confirmDelete(context, ref, idx.churchId, g),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(AppRadius.full),
                                  child: LinearProgressIndicator(
                                    value: g.progressFraction,
                                    minHeight: 10,
                                    backgroundColor: AppColors.gray100,
                                    color: AppColors.primaryColor,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  '${formatCedis(g.currentAmountCedis)} of ${formatCedis(g.targetAmountCedis)} '
                                  '(${g.progressFraction >= 1 ? 100 : (g.progressFraction * 100).round()}%)',
                                  style: AppTypography.caption,
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_hasMore) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Center(
                          child: PillrButton(
                            label: _loadingMore ? 'Loading…' : 'Load more',
                            onPressed: _loadingMore ? null : _loadMore,
                            variant: PillrButtonVariant.secondary,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
                ),
              ),
              floatingActionButton: idx == null || profile == null
                  ? null
                  : FloatingActionButton.extended(
                      onPressed: () => _showCreateGoal(
                        context,
                        ref,
                        churchId: idx.churchId,
                        uid: profile.uid,
                        periods: periods,
                        arms: arms,
                        existingGoalKeys: _items.map((g) => '${g.partnershipPeriodId}__${g.partnershipArmId}').toSet(),
                      ),
                      icon: const Icon(LucideIcons.plus),
                      label: const Text('Add goal'),
                    ),
            );
          },
        );
      },
    );
  }

  Future<void> _showCreateGoal(
    BuildContext context,
    WidgetRef ref, {
    required String churchId,
    required String uid,
    required List<PartnershipPeriod> periods,
    required List<PartnershipArm> arms,
    required Set<String> existingGoalKeys,
  }) async {
    if (periods.isEmpty || arms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create at least one period and one arm first.')),
      );
      return;
    }

    var period = periods.firstWhere((p) => p.isActive, orElse: () => periods.first);
    var arm = arms.firstWhere((a) => a.isActive, orElse: () => arms.first);
    final target = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('New goal', style: AppTypography.heading3),
          content: SizedBox(
            width: 420,
            child: StatefulBuilder(
              builder: (context, setSt) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<PartnershipPeriod>(
                      key: ValueKey(period.id),
                      initialValue: period,
                      decoration: const InputDecoration(labelText: 'Period'),
                      items: [
                        for (final p in periods)
                          DropdownMenuItem(value: p, child: Text(p.name)),
                      ],
                      onChanged: (v) {
                        if (v != null) setSt(() => period = v);
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<PartnershipArm>(
                      key: ValueKey(arm.id),
                      initialValue: arm,
                      decoration: const InputDecoration(labelText: 'Arm'),
                      items: [
                        for (final a in arms)
                          DropdownMenuItem(value: a, child: Text(a.name)),
                      ],
                      onChanged: (v) {
                        if (v != null) setSt(() => arm = v);
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: target,
                      decoration: const InputDecoration(
                        labelText: 'Target amount (₵)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            PillrButton(
              label: 'Create',
              onPressed: () => Navigator.pop(ctx, true),
              variant: PillrButtonVariant.primary,
            ),
          ],
        );
      },
    );

    if (ok != true) return;
    final amount = double.tryParse(target.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid target amount.')),
        );
      }
      return;
    }

    final key = '${period.id}__${arm.id}';
    if (existingGoalKeys.contains(key)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A goal already exists for that period and arm.')),
        );
      }
      return;
    }

    try {
      await ref.read(goalsRepositoryProvider).createGoal(
            churchId: churchId,
            uid: uid,
            partnershipPeriodId: period.id,
            partnershipArmId: arm.id,
            targetAmountCedis: amount,
          );
      ref.invalidate(goalsListProvider);
      await logPillrActivity(
        ref,
        churchId: churchId,
        action: 'goal.create',
        entityType: 'goal',
        entityId: key,
        entitySnapshot: {
          'partnershipPeriodId': period.id,
          'partnershipArmId': arm.id,
          'targetAmountCedis': amount,
        },
      );
      await _loadFirst();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _editGoal(
    BuildContext context,
    WidgetRef ref,
    String churchId,
    PartnershipGoal goal,
  ) async {
    final target = TextEditingController(text: goal.targetAmountCedis.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit target', style: AppTypography.heading3),
        content: TextField(
          controller: target,
          decoration: const InputDecoration(
            labelText: 'Target amount (₵)',
            border: OutlineInputBorder(),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          PillrButton(
            label: 'Save',
            onPressed: () => Navigator.pop(ctx, true),
            variant: PillrButtonVariant.primary,
          ),
        ],
      ),
    );
    if (ok != true) return;
    final amount = double.tryParse(target.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) return;
    try {
      await ref.read(goalsRepositoryProvider).updateGoalTarget(
            churchId: churchId,
            goal: goal,
            targetAmountCedis: amount,
          );
      ref.invalidate(goalsListProvider);
      await logPillrActivity(
        ref,
        churchId: churchId,
        action: 'goal.update',
        entityType: 'goal',
        entityId: goal.id,
        metadata: {
          'before': {'targetAmountCedis': goal.targetAmountCedis},
          'after': {'targetAmountCedis': amount},
        },
      );
      await _loadFirst();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String churchId,
    PartnershipGoal goal,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete goal?', style: AppTypography.heading3),
        content: const Text('This does not delete entries — only the target row.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          PillrButton(
            label: 'Delete',
            onPressed: () => Navigator.pop(ctx, true),
            variant: PillrButtonVariant.danger,
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(goalsRepositoryProvider).deleteGoal(churchId: churchId, goalId: goal.id);
      ref.invalidate(goalsListProvider);
      await logPillrActivity(
        ref,
        churchId: churchId,
        action: 'goal.delete',
        entityType: 'goal',
        entityId: goal.id,
        entitySnapshot: {
          'partnershipPeriodId': goal.partnershipPeriodId,
          'partnershipArmId': goal.partnershipArmId,
        },
      );
      await _loadFirst();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}
