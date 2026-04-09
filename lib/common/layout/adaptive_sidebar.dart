import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:the_pillr/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/extensions/async_value_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../features/auth/domain/user_church_index.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/church/providers/church_settings_providers.dart';
import '../../features/entries/providers/entries_providers.dart';

class NavItemData {
  const NavItemData(this.path, this.label, this.icon, {this.badge});

  final String path;
  final String label;
  final IconData icon;
  final int? badge;
}

class NavSectionData {
  const NavSectionData(this.title, this.items);

  final String? title;
  final List<NavItemData> items;
}

List<NavSectionData> navSectionsForRole(
  AppLocalizations l10n,
  UserChurchIndex? idx, {
  int pendingApprovalCount = 0,
}) {
  if (idx == null) return [];
  if (idx.isAdmin) {
    return [
      NavSectionData(l10n.navSectionMain, [
        NavItemData('/dashboard', l10n.navDashboard, LucideIcons.layoutDashboard),
      ]),
      NavSectionData(l10n.navSectionAdmin, [
        NavItemData('/users', l10n.navUsers, LucideIcons.users),
        NavItemData('/invitations', l10n.navInvitations, LucideIcons.mail),
        NavItemData('/logs', l10n.navActivityLogs, LucideIcons.history),
      ]),
      NavSectionData(null, [
        NavItemData('/help', l10n.navHelp, LucideIcons.helpCircle),
        NavItemData('/settings', l10n.navSettings, LucideIcons.settings),
      ]),
    ];
  }
  if (idx.isPastor) {
    return [
      NavSectionData(l10n.navSectionMain, [
        NavItemData('/dashboard', l10n.navDashboard, LucideIcons.home),
        NavItemData('/entries', l10n.navEntries, LucideIcons.fileText),
        NavItemData(
          '/approvals',
          l10n.navApprovals,
          LucideIcons.clipboardCheck,
          badge: pendingApprovalCount > 0 ? pendingApprovalCount : null,
        ),
      ]),
      NavSectionData(l10n.navSectionPartnership, [
        NavItemData('/partners', l10n.navPartners, LucideIcons.users),
        NavItemData('/leaderboard', l10n.navLeaderboard, LucideIcons.trophy),
        NavItemData('/goals', l10n.navGoals, LucideIcons.flag),
      ]),
      NavSectionData(l10n.navSectionConfiguration, [
        NavItemData('/arms', l10n.navPartnershipArms, LucideIcons.heartHandshake),
        NavItemData('/periods', l10n.navPeriods, LucideIcons.calendar),
      ]),
      NavSectionData(l10n.navSectionAdmin, [
        NavItemData('/users', l10n.navUsers, LucideIcons.users),
        NavItemData('/invitations', l10n.navInvitations, LucideIcons.mail),
      ]),
      NavSectionData(null, [
        NavItemData('/help', l10n.navHelp, LucideIcons.helpCircle),
        NavItemData('/settings', l10n.navSettings, LucideIcons.settings),
      ]),
    ];
  }
  return [
    NavSectionData(l10n.navSectionMain, [
      NavItemData('/dashboard', l10n.navDashboard, LucideIcons.home),
      NavItemData('/entries', l10n.navEntries, LucideIcons.fileText),
      NavItemData('/partners', l10n.navPartners, LucideIcons.users),
    ]),
    NavSectionData(null, [
      NavItemData('/help', l10n.navHelp, LucideIcons.helpCircle),
      NavItemData('/settings', l10n.navSettings, LucideIcons.settings),
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
    final scheme = Theme.of(context).colorScheme;
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final churchName = ref.watch(churchNameProvider) ?? 'Your church';
    final branding = ref.watch(churchSettingsProvider).valueOrNull;
    final profile = ref.watch(churchUserProfileProvider).valueOrNull;
    final pendingCount = ref.watch(pendingApprovalCountProvider);
    final l10n = AppLocalizations.of(context);
    final sections = navSectionsForRole(l10n, idx, pendingApprovalCount: pendingCount);

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
            padding: EdgeInsets.fromLTRB(
              collapsed ? AppSpacing.sm : AppSpacing.md,
              AppSpacing.lg,
              collapsed ? AppSpacing.sm : AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(collapsed ? 8 : 10),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: branding?.logoUrl != null && branding!.logoUrl!.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: CachedNetworkImage(
                            imageUrl: branding.logoUrl!,
                            width: 22,
                            height: 22,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) =>
                                Icon(LucideIcons.church, color: scheme.primary, size: 22),
                          ),
                        )
                      : Icon(LucideIcons.church, color: scheme.primary, size: 22),
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
                          section.title!.toUpperCase(),
                          style: AppTypography.overline,
                        ),
                      ),
                    for (final item in section.items)
                      _SidebarTile(
                        scheme: scheme,
                        icon: item.icon,
                        label: item.label,
                        path: item.path,
                        badge: item.badge,
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
                    backgroundColor: scheme.primaryContainer,
                    child: Text(
                      profile.fullName.isNotEmpty
                          ? profile.fullName[0].toUpperCase()
                          : '?',
                      style: AppTypography.label.copyWith(color: scheme.primary),
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
    required this.scheme,
    required this.icon,
    required this.label,
    required this.path,
    this.badge,
    required this.collapsed,
    required this.active,
    required this.onTap,
  });

  final ColorScheme scheme;
  final IconData icon;
  final String label;
  final String path;
  final int? badge;
  final bool collapsed;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = active ? AppColors.navActiveBackground : Colors.transparent;
    final fg = active ? AppColors.navActiveForeground : AppColors.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Semantics(
          button: true,
          label: label,
          selected: active,
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
                  if (badge != null && badge! > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.dangerColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$badge',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}
