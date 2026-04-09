import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:the_pillr/l10n/app_localizations.dart';

import '../../core/extensions/async_value_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/pillr_layout.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/text_case_utils.dart';
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
  if (path.startsWith('/entries/bulk-import')) return l10n.titleBulkImport;
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _TopBar(
                            title: _titleForPath(context, loc),
                            currentPath: loc,
                            showSearch: c.maxWidth >= 900,
                            idx: idx,
                            onSignOut: () async {
                              await ref.read(authRepositoryProvider).signOut();
                              if (context.mounted) context.go('/login');
                            },
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: PillrLayout.contentMaxWidth,
                                ),
                                child: GoalMilestoneListener(child: child),
                              ),
                            ),
                          ),
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
        icon: LucideIcons.layoutDashboard,
        selectedIcon: LucideIcons.layoutDashboard,
        label: 'Home',
        path: '/dashboard',
      ),
      const BottomNavItem(
        icon: LucideIcons.users,
        selectedIcon: LucideIcons.users,
        label: 'Users',
        path: '/users',
      ),
      const BottomNavItem(
        icon: LucideIcons.mail,
        selectedIcon: LucideIcons.mail,
        label: 'Invites',
        path: '/invitations',
      ),
      const BottomNavItem(
        icon: LucideIcons.settings,
        selectedIcon: LucideIcons.settings,
        label: 'Settings',
        path: '/settings',
      ),
    ];
  }
  if (idx.isPastor) {
    return [
      const BottomNavItem(
        icon: LucideIcons.home,
        selectedIcon: LucideIcons.home,
        label: 'Home',
        path: '/dashboard',
      ),
      const BottomNavItem(
        icon: LucideIcons.clipboardCheck,
        selectedIcon: LucideIcons.clipboardCheck,
        label: 'Approve',
        path: '/approvals',
      ),
      const BottomNavItem(
        icon: LucideIcons.fileText,
        selectedIcon: LucideIcons.fileText,
        label: 'Entries',
        path: '/entries',
      ),
      const BottomNavItem(
        icon: LucideIcons.users,
        selectedIcon: LucideIcons.users,
        label: 'Partners',
        path: '/partners',
      ),
      const BottomNavItem(
        icon: LucideIcons.settings,
        selectedIcon: LucideIcons.settings,
        label: 'Settings',
        path: '/settings',
      ),
    ];
  }
  return [
    const BottomNavItem(
      icon: LucideIcons.home,
      selectedIcon: LucideIcons.home,
      label: 'Home',
      path: '/dashboard',
    ),
    const BottomNavItem(
      icon: LucideIcons.fileText,
      selectedIcon: LucideIcons.fileText,
      label: 'Entries',
      path: '/entries',
    ),
    const BottomNavItem(
      icon: LucideIcons.users,
      selectedIcon: LucideIcons.users,
      label: 'Partners',
      path: '/partners',
    ),
    const BottomNavItem(
      icon: LucideIcons.settings,
      selectedIcon: LucideIcons.settings,
      label: 'Settings',
      path: '/settings',
    ),
  ];
}

class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.title,
    required this.currentPath,
    required this.onSignOut,
    required this.showSearch,
    required this.idx,
  });

  final String title;
  final String currentPath;
  final VoidCallback onSignOut;
  final bool showSearch;
  final UserChurchIndex? idx;

  void _handleBack(BuildContext context) {
    if (currentPath == '/entries/bulk-import') {
      context.go('/entries');
      return;
    }
    if (context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingApprovalCountProvider);
    final profile = ref.watch(churchUserProfileProvider).valueOrNull;
    final l10n = AppLocalizations.of(context);
    final showBack = currentPath == '/entries/bulk-import' || context.canPop();
    final fullName = profile?.fullName.trim() ?? '';
    final firstName = fullName.isEmpty
        ? ''
        : TextCaseUtils.toTitleCase(fullName.split(RegExp(r'\s+')).first);

    return Material(
      color: AppColors.white,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.white,
          border: const Border(bottom: BorderSide(color: AppColors.gray200)),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Row(
          children: [
            if (showBack)
              IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: Icon(LucideIcons.arrowLeft, size: 22, color: AppColors.textSecondary),
                onPressed: () => _handleBack(context),
              ),
            Expanded(
              flex: showSearch ? 1 : 2,
              child: Text(
                title,
                style: AppTypography.heading2.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.gray900,
                ),
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
                        suffixIcon: Icon(LucideIcons.search, color: AppColors.textSecondary, size: 20),
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
            if (showSearch && firstName.isNotEmpty) ...[
              Material(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(AppRadius.full),
                child: InkWell(
                  onTap: () => context.push('/settings'),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: AppColors.primaryColor.withValues(alpha: 0.15),
                          child: Text(
                            fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                            style: AppTypography.label.copyWith(
                              color: AppColors.primaryColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 120),
                          child: Text(
                            firstName,
                            style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(LucideIcons.chevronDown, size: 16, color: AppColors.textSecondary),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            IconButton(
              tooltip: l10n.toolbarHelp,
              onPressed: () => context.push('/help'),
              icon: Icon(LucideIcons.helpCircle, color: AppColors.textSecondary),
            ),
            IconButton(
              tooltip: l10n.toolbarNotifications,
              onPressed: () => context.push('/notifications'),
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(LucideIcons.bell, color: AppColors.textSecondary),
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
                icon: Icon(LucideIcons.moreVertical, color: AppColors.textSecondary),
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
