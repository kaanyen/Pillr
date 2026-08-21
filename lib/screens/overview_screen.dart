import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/utils/text_case_utils.dart';
import '../design/seline.dart';
import '../features/activity/domain/activity_log_row.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/dashboard/providers/dashboard_stats_providers.dart';
import '../features/entries/domain/partnership_entry.dart';
import '../features/entries/providers/entries_providers.dart';
import '../features/goals/providers/goals_providers.dart';
import '../features/arms/providers/arms_providers.dart';
import '../features/dashboard/providers/admin_dashboard_providers.dart';
import '../features/logs/providers/activity_logs_providers.dart';
import '../features/users/providers/users_providers.dart';
import '../features/partners/providers/partners_providers.dart';
import '../features/periods/providers/periods_providers.dart';

/// Overview — one screen for every role.
///
/// This replaces four near-duplicate dashboards. Rather than routing by role,
/// it composes blocks and shows only the ones the viewer has data and
/// permission for: a pastor gets the review queue and goals, an admin gets
/// people and configuration health, staff get their own submissions. The
/// greeting and the period figure are common to all three.
class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final profile = ref.watch(churchUserProfileProvider).valueOrNull;
    final money = ref.watch(churchMoneyFormatProvider);
    final church = ref.watch(churchNameProvider) ?? 'your church';

    final full = profile?.fullName.trim() ?? '';
    final first = full.isEmpty
        ? 'there'
        : TextCaseUtils.toTitleCase(full.split(RegExp(r'\s+')).first);

    final isPastor = idx?.isPastor ?? false;
    final isAdmin = idx?.isAdmin ?? false;

    return SelPageBody(
      onRefresh: () async {
        ref.invalidate(entriesListProvider);
        ref.invalidate(goalsListProvider);
        ref.invalidate(partnersStreamProvider(false));
        ref.invalidate(activityLogsPreviewProvider);
      },
      children: [
        SelPageTitle.hero(
          title: _greeting(),
          highlight: first,
          subtitle: 'Partnership activity across $church, updating live.',
          actions: [
            if (isPastor || (idx?.isStaff ?? false))
              SelButton.cyan(
                label: 'New entry',
                icon: LucideIcons.plus,
                onPressed: () => context.go('/entries/new'),
              ),
          ],
        ),

        if (isAdmin)
          const _AdminBlocks()
        else if (isPastor)
          _PastorBlocks(money: money)
        else
          _StaffBlocks(money: money),

        const SelSectionGap(factor: 0.5),
        const _ActivityBlock(),
      ],
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning, ';
    if (h < 17) return 'Good afternoon, ';
    return 'Good evening, ';
  }
}

// ---------------------------------------------------------------------------
// Pastor
// ---------------------------------------------------------------------------

class _PastorBlocks extends ConsumerWidget {
  const _PastorBlocks({required this.money});

  final String Function(num) money;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(pastorEntryStatsProvider);
    final partners = ref.watch(activePartnerCountProvider);
    final goalPct = ref.watch(pastorGoalProgressPercentProvider);
    final goals = ref.watch(activePeriodGoalsProvider);
    final period = ref.watch(activePeriodProvider);
    final pending = ref.watch(pendingEntriesProvider).valueOrNull ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelStatRow(stats: [
          SelStat(
            label: 'Approved',
            value: money(stats.totalApprovedCedis),
            footnote: '${stats.approvedCount} entries',
          ),
          SelStat(
            label: 'Awaiting review',
            value: '${stats.pendingCount}',
            footnote: stats.pendingCount == 0 ? 'Queue is clear' : 'In your queue',
            onTap: () => context.go('/queue'),
          ),
          SelStat(
            label: 'Active partners',
            value: '$partners',
            footnote: 'Giving records',
            onTap: () => context.go('/partners'),
          ),
          SelStat(
            label: 'Goal progress',
            value: goalPct == null ? '—' : '${goalPct.round()}%',
            footnote: period?.name ?? 'No active period',
          ),
        ]),

        if (pending.isNotEmpty) ...[
          const SelSectionGap(factor: 0.5),
          _PendingPreview(entries: pending, money: money),
        ],

        if (goals.isNotEmpty) ...[
          const SelSectionGap(factor: 0.5),
          SelPanel(
            title: 'Goals',
            subtitle: period?.name,
            trailing: SelButton(
              label: 'Manage',
              kind: SelButtonKind.quiet,
              dense: true,
              onPressed: () => context.go('/goals'),
            ),
            child: Column(
              children: [
                for (var i = 0; i < goals.length; i++) ...[
                  if (i > 0) const SizedBox(height: SelSpace.x6),
                  Consumer(builder: (context, ref, _) {
                    final arms = ref.watch(armsStreamProvider).valueOrNull ?? [];
                    final arm = arms
                        .where((a) => a.id == goals[i].partnershipArmId)
                        .firstOrNull;
                    return SelGoalLine(
                      label: arm?.name ?? 'Partnership arm',
                      value: goals[i].currentAmountCedis,
                      target: goals[i].targetAmountCedis,
                      valueText: money(goals[i].currentAmountCedis),
                      targetText: money(goals[i].targetAmountCedis),
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The top of the review queue, inline. A pastor's most common next action is
/// "approve the oldest pending thing", so it lives on the Overview rather than
/// one navigation step away.
class _PendingPreview extends StatelessWidget {
  const _PendingPreview({required this.entries, required this.money});

  final List<PartnershipEntry> entries;
  final String Function(num) money;

  @override
  Widget build(BuildContext context) {
    final show = entries.take(4).toList();
    return SelPanel(
      title: 'Waiting on you',
      subtitle: '${entries.length} ${entries.length == 1 ? "entry" : "entries"} to review',
      trailing: SelButton(
        label: 'Open queue',
        kind: SelButtonKind.quiet,
        dense: true,
        trailingIcon: LucideIcons.arrowRight,
        onPressed: () => context.go('/queue'),
      ),
      contentPadding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < show.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Sel.border),
            InkWell(
              onTap: () => context.go('/entries/${show[i].id}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SelSpace.cardPad,
                  vertical: SelSpace.x3,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelCell.stacked(
                        show[i].partnerSnapshot['fullName']?.toString() ?? '—',
                        show[i].armSnapshot['name']?.toString() ?? '',
                      ),
                    ),
                    SelCell.numeric(money(show[i].amountCedis)),
                    const SizedBox(width: SelSpace.x6),
                    const SelStatusMark(
                      status: SelStatus.pending,
                      label: 'Pending',
                      iconOnly: true,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Admin
// ---------------------------------------------------------------------------

class _AdminBlocks extends ConsumerWidget {
  const _AdminBlocks();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = (ref.watch(churchUsersProvider).valueOrNull ?? []).length;
    final invites = ref.watch(pendingInvitesCountProvider);
    final arms = (ref.watch(armsStreamProvider).valueOrNull ?? []).length;
    final period = ref.watch(activePeriodProvider);

    return SelStatRow(stats: [
      SelStat(
        label: 'Members',
        value: '$members',
        footnote: 'In this church',
        onTap: () => context.go('/people'),
      ),
      SelStat(
        label: 'Open invites',
        value: '$invites',
        footnote: invites == 0 ? 'None outstanding' : 'Awaiting acceptance',
        onTap: () => context.go('/people'),
      ),
      SelStat(
        label: 'Partnership arms',
        value: '$arms',
        footnote: 'Configured',
        onTap: () => context.go('/configuration'),
      ),
      SelStat(
        label: 'Active period',
        value: period == null ? 'None' : 'Open',
        footnote: period?.name ?? 'Set one up',
        onTap: () => context.go('/configuration'),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Staff
// ---------------------------------------------------------------------------

class _StaffBlocks extends ConsumerWidget {
  const _StaffBlocks({required this.money});

  final String Function(num) money;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(staffMyEntryStatsProvider);
    return SelStatRow(stats: [
      SelStat(
        label: 'Approved',
        value: money(mine.approvedTotalCedis),
        footnote: '${mine.approvedCount} of your entries',
      ),
      SelStat(
        label: 'Submitted',
        value: '${mine.totalCount}',
        footnote: 'Entries you recorded',
        onTap: () => context.go('/queue'),
      ),
      SelStat(
        label: 'Awaiting review',
        value: '${mine.totalCount - mine.approvedCount}',
        footnote: 'With your pastor',
        onTap: () => context.go('/queue'),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Activity — shared
// ---------------------------------------------------------------------------

class _ActivityBlock extends ConsumerWidget {
  const _ActivityBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(activityLogsPreviewProvider).valueOrNull ?? [];
    if (rows.isEmpty) return const SizedBox.shrink();

    final show = rows.take(6).toList();
    return SelPanel(
      title: 'Recent activity',
      contentPadding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < show.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Sel.border),
            _ActivityLine(row: show[i]),
          ],
        ],
      ),
    );
  }
}

/// Compact relative time. Activity rows are scanned, not read — an exact
/// timestamp would cost more attention than it returns.
String _relative(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${(d.inDays / 7).floor()}w ago';
}

class _ActivityLine extends StatelessWidget {
  const _ActivityLine({required this.row});

  final ActivityLogRow row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SelSpace.cardPad,
        vertical: SelSpace.x3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: RichText(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: SelType.body,
                children: [
                  TextSpan(
                    text: TextCaseUtils.toTitleCase(row.actorName),
                    style: SelType.bodyMedium,
                  ),
                  const TextSpan(text: '  '),
                  TextSpan(
                    text: row.action.replaceAll('.', ' ').replaceAll('_', ' '),
                    style: SelType.bodyMuted,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: SelSpace.x4),
          Text(_relative(row.createdAt), style: SelType.small),
        ],
      ),
    );
  }
}
