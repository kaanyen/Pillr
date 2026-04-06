import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/extensions/async_value_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../features/auth/domain/user_church_index.dart';
import '../../features/auth/providers/auth_providers.dart';

class NavItemData {
  const NavItemData(this.path, this.label, this.icon);

  final String path;
  final String label;
  final IconData icon;
}

class NavSectionData {
  const NavSectionData(this.title, this.items);

  final String? title;
  final List<NavItemData> items;
}

List<NavSectionData> navSectionsForRole(UserChurchIndex? idx) {
  if (idx == null) return [];
  if (idx.isAdmin) {
    return [
      const NavSectionData('MAIN', [
        NavItemData('/dashboard', 'Dashboard', Icons.dashboard_outlined),
      ]),
      const NavSectionData('ADMIN', [
        NavItemData('/users', 'Users', Icons.manage_accounts_outlined),
        NavItemData('/invitations', 'Invitations', Icons.mail_outline),
        NavItemData('/logs', 'Activity logs', Icons.history),
      ]),
      NavSectionData(null, [
        const NavItemData('/settings', 'Settings', Icons.settings_outlined),
      ]),
    ];
  }
  if (idx.isPastor) {
    return [
      const NavSectionData('MAIN', [
        NavItemData('/dashboard', 'Dashboard', Icons.home_outlined),
        NavItemData('/entries', 'Entries', Icons.receipt_long_outlined),
      ]),
      const NavSectionData('PARTNERSHIP', [
        NavItemData('/partners', 'Partners', Icons.people_outline),
        NavItemData('/leaderboard', 'Leaderboard', Icons.emoji_events_outlined),
        NavItemData('/goals', 'Goals', Icons.flag_outlined),
      ]),
      const NavSectionData('CONFIGURATION', [
        NavItemData('/arms', 'Partnership arms', Icons.volunteer_activism_outlined),
        NavItemData('/periods', 'Periods', Icons.calendar_month_outlined),
      ]),
      const NavSectionData('ADMIN', [
        NavItemData('/users', 'Users', Icons.manage_accounts_outlined),
        NavItemData('/invitations', 'Invitations', Icons.mail_outline),
      ]),
      NavSectionData(null, [
        const NavItemData('/settings', 'Settings', Icons.settings_outlined),
      ]),
    ];
  }
  return [
    const NavSectionData('MAIN', [
      NavItemData('/dashboard', 'Dashboard', Icons.home_outlined),
      NavItemData('/entries', 'Entries', Icons.receipt_long_outlined),
    ]),
    NavSectionData(null, [
      const NavItemData('/settings', 'Settings', Icons.settings_outlined),
    ]),
  ];
}

/// Sidebar: Reference 2–3 — grouped sections, soft active pill, Inter typography.
class AdaptiveSidebar extends ConsumerWidget {
  const AdaptiveSidebar({
    super.key,
    required this.currentPath,
    this.collapsed = false,
  });

  final String currentPath;
  final bool collapsed;

  bool _isActive(String path) {
    if (currentPath == path) return true;
    if (path != '/dashboard' && currentPath.startsWith('$path/')) return true;
    return false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final churchName = ref.watch(churchNameProvider).valueOrNull ?? 'Your church';
    final profile = ref.watch(churchUserProfileProvider).valueOrNull;
    final sections = navSectionsForRole(idx);

    final width = collapsed
        ? AppConstants.sidebarWidthCollapsed
        : AppConstants.sidebarWidthExpanded;

    return Container(
      width: width,
      color: AppColors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: const Icon(Icons.church_outlined, color: AppColors.primaryColor, size: 22),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Pillr',
                      style: AppTypography.heading3.copyWith(color: AppColors.gray900),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.gray50,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.gray200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      churchName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body.copyWith(
                        color: AppColors.gray900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Private workspace',
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: true),
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                children: [
                  for (final section in sections) ...[
                    if (section.title != null && !collapsed)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.sm,
                          AppSpacing.md,
                          AppSpacing.sm,
                          AppSpacing.sm,
                        ),
                        child: Text(
                          section.title!,
                          style: AppTypography.caption.copyWith(
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700,
                            color: AppColors.gray400,
                          ),
                        ),
                      ),
                    for (final item in section.items)
                      _SidebarTile(
                        icon: item.icon,
                        label: item.label,
                        path: item.path,
                        collapsed: collapsed,
                        active: _isActive(item.path),
                        onTap: () => context.go(item.path),
                      ),
                  ],
                ],
              ),
            ),
          ),
          if (profile != null && !collapsed)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.primaryLight,
                    child: Text(
                      profile.fullName.isNotEmpty
                          ? profile.fullName[0].toUpperCase()
                          : '?',
                      style: AppTypography.label.copyWith(color: AppColors.primaryColor),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.body.copyWith(
                            color: AppColors.gray900,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          profile.role[0].toUpperCase() + profile.role.substring(1),
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.icon,
    required this.label,
    required this.path,
    required this.collapsed,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String path;
  final bool collapsed;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = active ? AppColors.primaryLight : Colors.transparent;
    final fg = active ? AppColors.primaryColor : AppColors.gray600;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 0 : AppSpacing.sm,
              vertical: AppSpacing.sm + 2,
            ),
            child: Row(
              mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Icon(icon, size: 22, color: fg),
                if (!collapsed) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      label,
                      style: AppTypography.body.copyWith(
                        color: fg,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
