import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../design/seline.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/entries/providers/entries_providers.dart';

/// Notifications — things that want your attention right now.
///
/// Not a feed of everything that happened; that is Activity. This lists only
/// items with an action attached, so an empty state here is genuinely good
/// news rather than a gap.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final pending = ref.watch(pendingApprovalCountProvider);

    final items = <Widget>[
      if (idx?.isPastor == true && pending > 0)
        _Item(
          icon: LucideIcons.inbox,
          title: '$pending ${pending == 1 ? "entry" : "entries"} awaiting review',
          body: 'Approve or send them back from the queue.',
          actionLabel: 'Open queue',
          onTap: () => context.go('/queue?filter=pending'),
        ),
      if (idx?.isStaff == true)
        _Item(
          icon: LucideIcons.fileText,
          title: 'Your submissions',
          body: 'Track what is still pending and what was sent back.',
          actionLabel: 'View',
          onTap: () => context.go('/queue'),
        ),
    ];

    return SelPageBody(
      maxWidth: 720,
      children: [
        const SelPageTitle(
          title: 'Notifications',
          subtitle: 'Anything waiting on you.',
        ),
        if (items.isEmpty)
          const SelCard(
            child: SelEmpty(
              title: 'Nothing needs you',
              message: 'You are all caught up.',
              icon: LucideIcons.check,
            ),
          )
        else
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: SelSpace.x3),
            items[i],
          ],
        const SizedBox(height: SelSpace.x6),
        Text(
          'Push and digest preferences live under Settings → Notifications.',
          style: SelType.small,
        ),
      ],
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SelCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            height: 34,
            width: 34,
            decoration: BoxDecoration(
              color: Sel.canvas,
              borderRadius: BorderRadius.circular(SelRadius.icon),
              border: Border.all(color: Sel.border),
            ),
            child: Icon(icon, size: 15, color: Sel.ash),
          ),
          const SizedBox(width: SelSpace.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: SelType.bodyMedium),
                Text(body, style: SelType.bodySm),
              ],
            ),
          ),
          const SizedBox(width: SelSpace.x4),
          SelButton(label: actionLabel, kind: SelButtonKind.edge, dense: true, onPressed: onTap),
        ],
      ),
    );
  }
}
