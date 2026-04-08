import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:the_pillr/l10n/app_localizations.dart';

import '../../core/extensions/async_value_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/pillr_layout.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../features/auth/domain/user_church_index.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/entries/providers/entries_providers.dart';
import '../../features/goals/presentation/goal_milestone_listener.dart';
import '../../services/connectivity_service.dart';
import '../widgets/offline_banner.dart';
import 'adaptive_bottom_nav.dart';
import 'adaptive_sidebar.dart';
import 'responsive_layout.dart';

String _titleForPath(BuildContext context, String path) {
  final l10n = AppLocalizations.of(context);
  if (path.startsWith('/dashboard')) return l10n.titleDashboard;
  if (path.startsWith('/approvals')) return l10n.titleApprovals;
  if (path.startsWith('/entries/success')) return l10n.titleEntrySubmitted;
  if (path.startsWith('/entries')) return l10n.titleEntries;
  if (path.startsWith('/partners')) return l10n.titlePartners;
  if (path.startsWith('/leaderboard')) return l10n.titleLeaderboard;
  if (path.startsWith('/goals')) return l10n.titleGoals;
  if (path.startsWith('/arms')) return l10n.titleArms;
  if (path.startsWith('/periods')) return l10n.titlePeriods;
  if (path.startsWith('/users')) return l10n.titleUsers;
  if (path.startsWith('/invitations')) return l10n.titleInvitations;
  if (path.startsWith('/logs')) return l10n.titleActivityLogs;
  if (path.startsWith('/settings')) return l10n.titleSettings;
  if (path.startsWith('/search')) return l10n.titleSearch;
  if (path.startsWith('/notifications')) return l10n.titleNotifications;
  if (path.startsWith('/help')) return l10n.titleHelp;
  return l10n.appTitle;
}

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = GoRouterState.of(context).uri.path;
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final offline = ref.watch(connectivityProvider).maybeWhen(
          data: listIndicatesOffline,
          orElse: () => false,
        );

    return LayoutBuilder(
      builder: (context, c) {
        final bp = breakpointFor(c.maxWidth);
        final showSidebar = bp == AppBreakpoint.desktop;
        final sidebarCollapsed = bp == AppBreakpoint.tablet;

        final bottomItems = _mobileNavItems(idx);

        return Scaffold(
          backgroundColor: AppColors.surfaceColor,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OfflineBanner(visible: offline),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showSidebar || sidebarCollapsed)
                      AdaptiveSidebar(
                        currentPath: loc,
                        collapsed: sidebarCollapsed,
                      ),
                    if (showSidebar || sidebarCollapsed)
                      const VerticalDivider(width: 1, color: AppColors.gray200),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: PillrLayout.contentMaxWidth,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _TopBar(
                                title: _titleForPath(context, loc),
                                showSearch: c.maxWidth >= 900,
                                idx: idx,
                                onSignOut: () async {
                                  await ref.read(authRepositoryProvider).signOut();
                                  if (context.mounted) context.go('/login');
                                },
                              ),
                              Expanded(
                                child: GoalMilestoneListener(child: child),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: bp == AppBreakpoint.mobile && bottomItems.isNotEmpty
              ? AdaptiveBottomNav(
                  items: bottomItems,
                  currentPath: loc,
                )
              : null,
        );
      },
    );
  }
}

List<BottomNavItem> _mobileNavItems(UserChurchIndex? idx) {
  if (idx == null) return [];
  if (idx.isAdmin) {
    return [
      const BottomNavItem(
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
        label: 'Home',
        path: '/dashboard',
      ),
      const BottomNavItem(
        icon: Icons.manage_accounts_outlined,
        selectedIcon: Icons.manage_accounts,
        label: 'Users',
        path: '/users',
      ),
      const BottomNavItem(
        icon: Icons.mail_outline,
        selectedIcon: Icons.mail,
        label: 'Invites',
        path: '/invitations',
      ),
      const BottomNavItem(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: 'Settings',
        path: '/settings',
      ),
    ];
  }
  if (idx.isPastor) {
    return [
      const BottomNavItem(
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        label: 'Home',
        path: '/dashboard',
      ),
      const BottomNavItem(
        icon: Icons.pending_actions_outlined,
        selectedIcon: Icons.pending_actions,
        label: 'Approve',
        path: '/approvals',
      ),
      const BottomNavItem(
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long,
        label: 'Entries',
        path: '/entries',
      ),
      const BottomNavItem(
        icon: Icons.people_outline,
        selectedIcon: Icons.people,
        label: 'Partners',
        path: '/partners',
      ),
      const BottomNavItem(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: 'Settings',
        path: '/settings',
      ),
    ];
  }
  return [
    const BottomNavItem(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      label: 'Home',
      path: '/dashboard',
    ),
    const BottomNavItem(
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
      label: 'Entries',
      path: '/entries',
    ),
    const BottomNavItem(
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
      label: 'Partners',
      path: '/partners',
    ),
    const BottomNavItem(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: 'Settings',
      path: '/settings',
    ),
  ];
}

class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.title,
    required this.onSignOut,
    required this.showSearch,
    required this.idx,
  });

  final String title;
  final VoidCallback onSignOut;
  final bool showSearch;
  final UserChurchIndex? idx;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingApprovalCountProvider);
    final l10n = AppLocalizations.of(context);
    return Material(
      color: AppColors.white,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.gray200)),
        ),
        child: Row(
          children: [
            if (context.canPop())
              IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: () => context.pop(),
              ),
            Expanded(
              flex: showSearch ? 1 : 2,
              child: Text(
                title,
                style: AppTypography.heading2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (showSearch && idx?.isPastor == true) ...[
              Expanded(
                flex: 2,
                child: InkWell(
                  onTap: () => context.push('/search'),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  child: IgnorePointer(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: l10n.searchHint,
                        prefixIcon: const Icon(Icons.search, color: AppColors.gray400),
                        isDense: true,
                        filled: true,
                        fillColor: AppColors.gray50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
            ],
            IconButton(
              tooltip: l10n.toolbarHelp,
              onPressed: () => context.push('/help'),
              icon: const Icon(Icons.help_outline_rounded),
            ),
            IconButton(
              tooltip: l10n.toolbarNotifications,
              onPressed: () => context.push('/notifications'),
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.notifications_outlined),
                  if (idx?.isPastor == true && pending > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.dangerColor,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          '$pending',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Tooltip(
              message: l10n.toolbarMoreOptions,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (v) {
                  if (v == 'logout') onSignOut();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'logout', child: Text(l10n.toolbarSignOut)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
