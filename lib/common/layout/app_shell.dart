import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/extensions/async_value_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../features/auth/domain/user_church_index.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../services/connectivity_service.dart';
import '../widgets/offline_banner.dart';
import 'adaptive_bottom_nav.dart';
import 'adaptive_sidebar.dart';
import 'responsive_layout.dart';

String _titleForPath(String path) {
  if (path.startsWith('/dashboard')) return 'Dashboard';
  if (path.startsWith('/entries')) return 'Entries';
  if (path.startsWith('/partners')) return 'Partners';
  if (path.startsWith('/leaderboard')) return 'Leaderboard';
  if (path.startsWith('/goals')) return 'Goals';
  if (path.startsWith('/arms')) return 'Partnership arms';
  if (path.startsWith('/periods')) return 'Periods';
  if (path.startsWith('/users')) return 'Users';
  if (path.startsWith('/invitations')) return 'Invitations';
  if (path.startsWith('/logs')) return 'Activity logs';
  if (path.startsWith('/settings')) return 'Settings';
  return 'Pillr';
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _TopBar(
                            title: _titleForPath(loc),
                            showSearch: c.maxWidth >= 900,
                            onSignOut: () async {
                              await ref.read(authRepositoryProvider).signOut();
                              if (context.mounted) context.go('/login');
                            },
                          ),
                          Expanded(child: child),
                        ],
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
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: 'Settings',
      path: '/settings',
    ),
  ];
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.onSignOut,
    required this.showSearch,
  });

  final String title;
  final VoidCallback onSignOut;
  final bool showSearch;

  @override
  Widget build(BuildContext context) {
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
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: () => context.pop(),
              ),
            Expanded(
              flex: showSearch ? 1 : 2,
              child: Text(title, style: AppTypography.heading2),
            ),
            if (showSearch) ...[
              Expanded(
                flex: 2,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search for anything here…',
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
              const SizedBox(width: AppSpacing.md),
            ],
            IconButton(
              onPressed: () {},
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.notifications_outlined),
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.dangerColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (v) {
                if (v == 'logout') onSignOut();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'logout', child: Text('Sign out')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
