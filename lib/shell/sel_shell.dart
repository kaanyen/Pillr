import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/navigation/route_persistence_listener.dart';
import '../core/utils/text_case_utils.dart';
import '../design/seline.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/entries/providers/entries_providers.dart';
import '../features/goals/presentation/goal_milestone_listener.dart';
import '../features/platform/providers/platform_providers.dart';
import '../services/connectivity_service.dart';
import 'nav_model.dart';
import 'sel_rail.dart';

/// The application shell.
///
/// Structurally this is just two columns on one continuous warm canvas: the
/// bare rail, and the content. There is no app bar, no sidebar panel, and no
/// divider between them — the page is a single sheet of paper with links in
/// its left margin. Utility controls float top-right directly on the canvas.
///
/// Below [SelLayout.compact] the rail is replaced by a bottom bar, which is
/// the only place in the app that uses a surface for navigation.
class SelShell extends ConsumerWidget {
  const SelShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = GoRouterState.of(context).uri.path;
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final offline = ref.watch(connectivityProvider).maybeWhen(
          data: listIndicatesOffline,
          orElse: () => false,
        );

    return LayoutBuilder(
      builder: (context, c) {
        final compact = c.maxWidth < 900;

        final body = Stack(
          children: [
            Positioned.fill(
              child: compact
                  ? child
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: SelSpace.x6),
                          child: SelRail(currentPath: path),
                        ),
                        Expanded(child: child),
                      ],
                    ),
            ),
            // Utility cluster floats on the canvas — no bar, no fill.
            Positioned(
              top: SelSpace.x6,
              right: compact ? SelSpace.x4 : SelSpace.x8,
              child: _UtilityCluster(compact: compact, path: path),
            ),
          ],
        );

        return GoalMilestoneListener(
          child: RoutePersistenceListener(
            child: Scaffold(
              backgroundColor: Sel.canvas,
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (offline) const _OfflineStrip(),
                  Expanded(child: SafeArea(child: body)),
                ],
              ),
              bottomNavigationBar:
                  compact ? _BottomBar(path: path, idx: idx) : null,
            ),
          ),
        );
      },
    );
  }
}

/// Search, notifications, account — floating on the canvas, top right.
class _UtilityCluster extends ConsumerWidget {
  const _UtilityCluster({required this.compact, required this.path});

  final bool compact;
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(churchUserProfileProvider).valueOrNull;
    final pending = ref.watch(pendingApprovalCountProvider);
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final isPlatform = ref.watch(isPlatformAdminProvider).valueOrNull == true;

    final full = profile?.fullName.trim() ?? '';
    final first = full.isEmpty
        ? ''
        : TextCaseUtils.toTitleCase(full.split(RegExp(r'\s+')).first);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (idx?.isPastor == true)
          SelIconButton(
            icon: LucideIcons.search,
            tooltip: 'Search',
            onPressed: () => context.push('/search'),
          ),
        SelIconButton(
          icon: LucideIcons.bell,
          tooltip: 'Notifications',
          badge: idx?.isPastor == true ? pending : null,
          onPressed: () => context.push('/notifications'),
        ),
        if (isPlatform && !compact)
          SelIconButton(
            icon: LucideIcons.layoutGrid,
            tooltip: 'Platform',
            onPressed: () => context.go('/platform/churches'),
          ),
        const SizedBox(width: SelSpace.x1),
        _AccountChip(name: first, initial: full.isNotEmpty ? full[0] : '?'),
      ],
    );
  }
}

/// Ghost pill with the user's initial — the reference's signed-in cluster,
/// reduced to one avatar.
class _AccountChip extends ConsumerWidget {
  const _AccountChip({required this.name, required this.initial});

  final String name;
  final String initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, 40),
      position: PopupMenuPosition.under,
      onSelected: (v) async {
        if (v == 'settings') {
          if (context.mounted) context.push('/settings');
        } else if (v == 'signout') {
          await ref.read(authRepositoryProvider).signOut();
          if (context.mounted) context.go('/');
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'settings',
          height: 38,
          child: Text('Settings', style: SelType.body),
        ),
        PopupMenuItem(
          value: 'signout',
          height: 38,
          child: Text('Sign out', style: SelType.body),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 4, SelSpace.x3, 4),
        decoration: BoxDecoration(
          color: Sel.card,
          borderRadius: BorderRadius.circular(SelRadius.pill),
          border: Border.all(color: Sel.border),
          boxShadow: SelShadow.hairline,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 22,
              width: 22,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Sel.canvas,
                shape: BoxShape.circle,
              ),
              child: Text(
                initial.toUpperCase(),
                style: SelType.small.copyWith(
                  color: Sel.ink,
                  fontWeight: FontWeight.w500,
                  height: 1,
                ),
              ),
            ),
            if (name.isNotEmpty) ...[
              const SizedBox(width: SelSpace.x2),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: Text(
                  name,
                  style: SelType.button,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const SizedBox(width: SelSpace.x1),
            const Icon(LucideIcons.chevronDown, size: 13, color: Sel.ash),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.path, required this.idx});

  final String path;
  final dynamic idx;

  @override
  Widget build(BuildContext context) {
    final items = mobileNavFor(idx);
    if (items.isEmpty) return const SizedBox.shrink();

    final current = items.indexWhere(
      (e) => path == e.path || path.startsWith('${e.path}/'),
    );

    return Container(
      decoration: const BoxDecoration(
        color: Sel.card,
        border: Border(top: BorderSide(color: Sel.border)),
      ),
      child: SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: current >= 0 ? current : 0,
          backgroundColor: Sel.card,
          onDestinationSelected: (i) => context.go(items[i].path),
          destinations: [
            for (final it in items)
              NavigationDestination(
                icon: Icon(it.icon, size: 18, color: Sel.ash),
                selectedIcon: Icon(it.icon, size: 18, color: Sel.ink),
                label: it.label,
              ),
          ],
        ),
      ),
    );
  }
}

/// Offline notice. A quiet inverted strip — this is information, not an alarm.
class _OfflineStrip extends StatelessWidget {
  const _OfflineStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Sel.soot,
      padding: const EdgeInsets.symmetric(
        horizontal: SelSpace.x4,
        vertical: SelSpace.x2,
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.wifiOff, size: 13, color: Sel.card),
            const SizedBox(width: SelSpace.x2),
            Text(
              'Offline — changes will sync when you reconnect.',
              style: SelType.small.copyWith(color: Sel.card),
            ),
          ],
        ),
      ),
    );
  }
}
