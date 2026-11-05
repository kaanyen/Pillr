import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../design/seline.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/entries/domain/partnership_entry.dart';
import '../features/entries/providers/entries_providers.dart';
import '../features/maintenance/providers/duplicate_health_provider.dart';
import 'settings_screen.dart';

/// Notifications — things that want your attention right now, as on the
/// canvas: what needs you, with the action beside it, and how you hear about
/// each kind of thing.
///
/// Not a feed of everything that happened; that is Activity.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final money = ref.watch(churchMoneyFormatProvider);
    final pending =
        ref.watch(pendingEntriesProvider).valueOrNull ?? const <PartnershipEntry>[];
    final duplicates = ref.watch(duplicateBadgeCountProvider);
    final digest = ref.watch(notificationDigestProvider).valueOrNull ?? true;
    final goals = ref.watch(notificationGoalsProvider).valueOrNull ?? true;
    final isPastor = idx?.isPastor ?? false;
    final isAdmin = idx?.isAdmin ?? false;
    final mine = [
      for (final e in pending)
        if (e.createdBy == idx?.uid) e,
    ];

    final oldest = pending.isEmpty
        ? null
        : pending.reduce((a, b) => a.createdAt.isBefore(b.createdAt) ? a : b);
    final total = pending.fold<double>(0, (s, e) => s + e.amountCedis);

    final items = <Widget>[
      if (isPastor && pending.isNotEmpty)
        _Item(
          badge: '${pending.length}',
          strong: true,
          title:
              '${pending.length} ${pending.length == 1 ? 'entry is' : 'entries are'} waiting for review',
          body:
              '${money(total)} in all · the oldest, ${oldest!.partnerSnapshot['fullName'] ?? 'a partner'}\'s ${money(oldest.amountCedis)}, '
              'has waited ${DateTime.now().difference(oldest.createdAt).inDays} days',
          action: SelButton.cyan(
            label: 'Open the queue',
            onPressed: () => context.go('/queue'),
          ),
        ),
      if (!isPastor && mine.isNotEmpty)
        _Item(
          badge: '${mine.length}',
          strong: true,
          title:
              '${mine.length} of your ${mine.length == 1 ? 'entry is' : 'entries are'} waiting for a pastor',
          body: '${money(mine.fold<double>(0, (s, e) => s + e.amountCedis))} in all. '
              'They count once a pastor approves them.',
          action: SelButton(
            label: 'See them',
            onPressed: () => context.go('/queue'),
          ),
        ),
      if (!isAdmin && duplicates > 0)
        _Item(
          badge: '$duplicates',
          title:
              '$duplicates possible ${duplicates == 1 ? 'duplicate' : 'duplicates'} found',
          body: 'Partners who may be the same person. Check them in Tools.',
          action: SelButton(
            label: 'Review',
            onPressed: () => context.go('/tools'),
          ),
        ),
    ];

    final needs = SelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Needs you', style: SelType.subtitle),
          const SizedBox(height: SelSpace.x3),
          if (items.isEmpty)
            const SelEmpty(
              title: 'Nothing needs you',
              message: 'You are all caught up.',
              icon: LucideIcons.check,
            )
          else
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: Sel.rowLine),
              items[i],
            ],
        ],
      ),
    );

    Widget pref(String label, String how) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: SelType.bodySm.copyWith(color: Sel.text)),
          ),
          Text(how, style: SelType.small),
        ],
      ),
    );
    final how = SelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('How you hear about these', style: SelType.subtitle),
          const SizedBox(height: SelSpace.x2),
          pref('New entries to review', digest ? 'Daily summary' : 'Here only'),
          const Divider(height: 1, color: Sel.rowLine),
          pref('Possible duplicates', 'Here only'),
          const Divider(height: 1, color: Sel.rowLine),
          pref('Goal milestones', goals ? 'On' : 'Off'),
          const SizedBox(height: SelSpace.x3),
          Align(
            alignment: Alignment.centerLeft,
            child: SelLink(
              label: 'Change in Settings',
              onTap: () => context.go('/settings'),
            ),
          ),
        ],
      ),
    );

    return SelPageBody(
      children: [
        SelPageTitle(
          title: 'Notifications',
          subtitle: 'Anything waiting on you, and what happened to what you sent.',
          actions: [
            SelButton(
              label: 'Choose what you get',
              onPressed: () => context.go('/settings'),
            ),
          ],
        ),
        LayoutBuilder(
          builder: (context, c) => c.maxWidth < 900
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [needs, const SizedBox(height: SelSpace.x4), how],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: needs),
                    const SizedBox(width: SelSpace.x4),
                    SizedBox(width: 300, child: how),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.badge,
    required this.title,
    required this.body,
    required this.action,
    this.strong = false,
  });

  final String badge;
  final String title;
  final String body;
  final Widget action;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: Sel.sky, shape: BoxShape.circle),
          ),
          const SizedBox(width: SelSpace.x3),
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: strong ? Sel.ink : Sel.skyWash,
              shape: BoxShape.circle,
            ),
            child: Text(
              badge,
              style: SelType.small.copyWith(
                color: strong ? Sel.card : Sel.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: SelSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: SelType.body.copyWith(
                    color: Sel.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(body, style: SelType.bodySm),
              ],
            ),
          ),
          const SizedBox(width: SelSpace.x4),
          action,
        ],
      ),
    );
  }
}
