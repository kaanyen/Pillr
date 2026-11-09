import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../features/activity/activity_action_label.dart';
import '../core/navigation/panel_flows.dart';
import '../core/utils/text_case_utils.dart';
import '../design/seline.dart';
import '../features/activity/domain/activity_log_row.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/entries/bulk_import/bulk_import_draft_provider.dart';
import '../features/entries/bulk_import/bulk_import_session_store.dart';
import '../features/entries/bulk_import/bulk_import_screen.dart' show describeWhen;
import '../features/entries/providers/entries_providers.dart';
import '../features/goals/providers/goals_providers.dart';
import '../features/arms/providers/arms_providers.dart';
import '../features/logs/providers/activity_logs_providers.dart';
import '../features/partners/providers/partners_providers.dart';
import '../features/periods/providers/periods_providers.dart';
import '../features/maintenance/providers/duplicate_health_provider.dart';
import 'arm_palette.dart';
import 'views/overview_pastor.dart';
import 'views/overview_roles.dart';
import 'views/overview_shortcuts.dart';

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
    final money = ref.watch(churchMoneyFormatProvider);

    final isPastor = idx?.isPastor ?? false;
    final isAdmin = idx?.isAdmin ?? false;
    final pendingCount = isPastor
        ? (ref.watch(pendingEntriesProvider).valueOrNull?.length ?? 0)
        : 0;

    return SelPageBody(
      onRefresh: () async {
        ref.invalidate(rankingEntriesProvider);
        invalidateEntryDerivedData(ref);
        ref.invalidate(goalsListProvider);
        ref.invalidate(partnersStreamProvider(false));
        ref.invalidate(activityLogsPreviewProvider);
      },
      children: [
        SelPageTitle(
          title: 'Overview',
          subtitle: overviewSubtitle(ref.watch(activePeriodProvider)?.name),
          actions: [
            if (isAdmin) ...[
              SelButton(
                label: 'Configuration',
                onPressed: () => context.go('/configuration'),
              ),
              const SizedBox(width: SelSpace.x2),
              SelButton.cyan(
                label: 'Invite someone',
                onPressed: () => context.go('/people'),
              ),
            ] else if (!isPastor && (idx?.isStaff ?? false)) ...[
              SelButton(
                label: 'Bring in a sheet',
                onPressed: () => context.go('/entries/bulk-import'),
              ),
              const SizedBox(width: SelSpace.x2),
              SelButton.cyan(
                label: 'Record giving',
                onPressed: () => showEntryFormPanel(context),
              ),
            ] else if (isPastor)
              SelButton(
                label: 'New entry',
                icon: LucideIcons.plus,
                onPressed: () => showEntryFormPanel(context),
              ),
            if (isPastor && pendingCount > 0) ...[
              const SizedBox(width: SelSpace.x2),
              SelButton.cyan(
                label: 'Review $pendingCount waiting',
                onPressed: () => context.go('/queue?filter=pending'),
              ),
            ],
          ],
        ),

        if (isPastor || (idx?.isStaff ?? false)) ...[
          OverviewShortcuts(isPastor: isPastor),
          const SelSectionGap(factor: 0.5),
        ],

        const _UnfinishedImport(),

        if (isAdmin) ...[
          const _AdminShortcuts(),
          const SelSectionGap(factor: 0.5),
          const AdminOverview(),
        ] else if (isPastor) ...[
          const PastorOverview(extra: _ActivityBlock(card: true)),
          _PastorGoals(money: money),
        ] else
          const StaffOverview(),
      ],
    );
  }

}

// ---------------------------------------------------------------------------
// Pastor
// ---------------------------------------------------------------------------

/// The church's goals for the period, under the Overview cards.
class _PastorGoals extends ConsumerWidget {
  const _PastorGoals({required this.money});

  final String Function(num) money;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(countedActivePeriodGoalsProvider);
    final period = ref.watch(activePeriodProvider);
    if (goals.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: SelSpace.x4),
      child: SelPanel(
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
              Consumer(
                builder: (context, ref, _) {
                  final arms = ref.watch(armsStreamProvider).valueOrNull ?? [];
                  final arm = arms
                      .where((a) => a.id == goals[i].partnershipArmId)
                      .firstOrNull;
                  final reached = ref.watch(goalReachedCedisProvider(goals[i]));
                  return SelGoalLine(
                    color: armColorOf(ref, goals[i].partnershipArmId),
                    label: arm?.name ?? 'Partnership arm',
                    value: reached,
                    target: goals[i].targetAmountCedis,
                    valueText: money(reached),
                    targetText: money(goals[i].targetAmountCedis),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Admin
// ---------------------------------------------------------------------------

/// The admin's four places, fixed: an admin has no giving pages to choose
/// shortcuts from.
class _AdminShortcuts extends ConsumerWidget {
  const _AdminShortcuts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(activePeriodProvider);
    final tree = ref.watch(armTreeProvider);
    final dupes = ref.watch(duplicateBadgeCountProvider);
    final left = period?.endDate.difference(DateTime.now()).inDays;
    final items = <(IconData, String, String, String, int)>[
      (LucideIcons.userPlus, 'Invite someone', 'Pastor or staff', '/people', 0),
      (
        LucideIcons.calendar,
        'Giving period',
        period == null ? 'None open' : (left != null && left >= 0 ? '$left days left' : period.name),
        '/configuration',
        0,
      ),
      (
        LucideIcons.alignLeft,
        'Arms',
        tree.flattened.length > tree.mains.length
            ? '${tree.mains.length} main, ${tree.flattened.length - tree.mains.length} sub-arms'
            : '${tree.mains.length} ${tree.mains.length == 1 ? 'arm' : 'arms'}',
        '/configuration',
        0,
      ),
      (LucideIcons.activity, 'Health', 'Waiting, duplicates, letters', '/health', dupes),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth < 640 ? 2 : 4;
        final w = (c.maxWidth - (cols - 1) * SelSpace.x3) / cols;
        return Wrap(
          spacing: SelSpace.x3,
          runSpacing: SelSpace.x3,
          children: [
            for (final (icon, title, sub, path, n) in items)
              SizedBox(
                width: w,
                child: SelCard(
                  onTap: () => context.go(path),
                  radius: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Sel.skyTint,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(icon, size: 20, color: Sel.ink),
                      ),
                      const SizedBox(width: SelSpace.x3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              overflow: TextOverflow.ellipsis,
                              style: SelType.body.copyWith(color: Sel.ink, fontWeight: FontWeight.w700),
                            ),
                            Text(sub, overflow: TextOverflow.ellipsis, style: SelType.small),
                          ],
                        ),
                      ),
                      if (n > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                          decoration: BoxDecoration(
                            color: Sel.skyWash,
                            borderRadius: BorderRadius.circular(SelRadius.pill),
                          ),
                          child: Text('$n', style: SelType.small.copyWith(color: Sel.ink, fontWeight: FontWeight.w800)),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Activity — shared
// ---------------------------------------------------------------------------

class _ActivityBlock extends ConsumerWidget {
  const _ActivityBlock({this.card = false});

  /// The Overview's third card: shorter, titled Recent changes.
  final bool card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(activityLogsPreviewProvider).valueOrNull ?? [];
    if (rows.isEmpty && !card) return const SizedBox.shrink();

    final show = rows.take(card ? 4 : 6).toList();
    return SelPanel(
      title: card ? 'Recent changes' : 'Recent activity',
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
                    text: activityActionLabel(row.action).toLowerCase(),
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

/// "You left an import half-done" — shown only when there is one.
class _UnfinishedImport extends ConsumerWidget {
  const _UnfinishedImport();

  Future<void> _discard(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard the saved import?'),
        content: const Text(
          'The rows will be thrown away. Nothing has been imported yet, so '
          'nothing else changes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null) return;
    await BulkImportSessionStore.clear(uid: idx.uid, churchId: idx.churchId);
    ref.invalidate(bulkImportDraftProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(bulkImportDraftProvider).valueOrNull;
    if (draft == null) return const SizedBox.shrink();

    final rows = draft.rawRows.length;
    return Padding(
      padding: const EdgeInsets.only(top: SelSpace.x6),
      child: SelCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('An import is waiting', style: SelType.bodyMedium),
                  const SizedBox(height: SelSpace.x1),
                  Text(
                    '$rows ${rows == 1 ? "row" : "rows"} from '
                    '${draft.fileName ?? "a spreadsheet"}'
                    '${draft.savedAt == null ? "" : ", left ${describeWhen(draft.savedAt!)}"}'
                    ' — not imported yet.',
                    style: SelType.bodySm,
                  ),
                ],
              ),
            ),
            const SizedBox(width: SelSpace.x4),
            // Without this the card is permanent furniture: the only way out
            // was to open the importer and clear it from there.
            SelButton(
              label: 'Discard',
              kind: SelButtonKind.quiet,
              onPressed: () => _discard(context, ref),
            ),
            const SizedBox(width: SelSpace.x2),
            SelButton.cyan(
              label: 'Continue import',
              onPressed: () => context.go('/entries/bulk-import'),
            ),
          ],
        ),
      ),
    );
  }
}
