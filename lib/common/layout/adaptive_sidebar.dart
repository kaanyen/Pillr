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
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/color_utils.dart';
import '../../features/auth/domain/user_church_index.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/church/providers/church_settings_providers.dart';
import '../../features/entries/providers/entries_providers.dart';
import '../../features/platform/providers/platform_providers.dart';

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
  bool showPlatform = false,
}) {
  if (idx == null) return [];
  List<NavSectionData> withPlatform(List<NavSectionData> inner) {
    if (!showPlatform) return inner;
    return [
      NavSectionData(
        'Platform',
        [NavItemData('/platform/churches', 'All churches', LucideIcons.building)],
      ),
      ...inner,
    ];
  }
  if (idx.isAdmin) {
    return withPlatform([
      NavSectionData(l10n.navSectionMain, [
        NavItemData('/dashboard', l10n.navDashboard, LucideIcons.layoutDashboard),
      ]),
      NavSectionData(l10n.navSectionConfiguration, [
        NavItemData('/arms', l10n.navPartnershipArms, LucideIcons.heartHandshake),
        NavItemData('/periods', l10n.navPeriods, LucideIcons.calendar),
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
    ]);
  }
  if (idx.isPastor) {
    return withPlatform([
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
    ]);
  }
  return withPlatform([
    NavSectionData(l10n.navSectionMain, [
      NavItemData('/dashboard', l10n.navDashboard, LucideIcons.home),
      NavItemData('/entries', l10n.navEntries, LucideIcons.fileText),
      NavItemData('/partners', l10n.navPartners, LucideIcons.users),
    ]),
    NavSectionData(null, [
      NavItemData('/help', l10n.navHelp, LucideIcons.helpCircle),
      NavItemData('/settings', l10n.navSettings, LucideIcons.settings),
    ]),
  ]);
}

/// Sidebar built on the reference's Person Row Card pattern.
///
/// Paper column with a Fog hairline on its right edge. Rows are 14/500 with a
/// Mist wash when active — no colored pill, no accent bar. The only chromatic
/// element is the church's identity mark at the top, which is the one place a
/// tenant's own color is allowed to appear.
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
    final churchName = ref.watch(churchNameProvider) ?? 'Your church';
    final branding = ref.watch(churchSettingsProvider).valueOrNull;
    final profile = ref.watch(churchUserProfileProvider).valueOrNull;
    final pendingCount = ref.watch(pendingApprovalCountProvider);
    final showPlatform = ref.watch(isPlatformAdminProvider).valueOrNull == true;
    final l10n = AppLocalizations.of(context);
    final sections = navSectionsForRole(
      l10n,
      idx,
      pendingApprovalCount: pendingCount,
      showPlatform: showPlatform,
    );

    final width = collapsed
        ? AppConstants.sidebarWidthCollapsed
        : AppConstants.sidebarWidthExpanded;

    // The tenant's own color, confined to the identity mark below.
    final accent = AppTheme.tenantAccent(parseHexColor(branding?.primaryColorHex));

    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: AppColors.paper,
        border: Border(
          right: BorderSide(color: AppColors.fog, width: AppBorders.hairline),
        ),
      ),
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
                // Identity mark — the church's own color lives here and
                // nowhere else in the chrome.
                Container(
                  height: collapsed ? 32 : 36,
                  width: collapsed ? 32 : 36,
                  decoration: BoxDecoration(
                    color: AppColors.mist,
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    border: Border.all(color: AppColors.fog, width: AppBorders.hairline),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: branding?.logoUrl != null && branding!.logoUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: branding.logoUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) =>
                              Icon(LucideIcons.church, color: accent, size: 18),
                        )
                      : Icon(LucideIcons.church, color: accent, size: 18),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Pillr',
                      style: AppTypography.headingSm.copyWith(
                        fontFamily: AppTypography.textFamily,
                      ),
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
                  color: AppColors.mist,
                  borderRadius: BorderRadius.circular(AppRadius.input),
                  border: Border.all(color: AppColors.fog, width: AppBorders.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      churchName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelStrong,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text('Private workspace', style: AppTypography.micro),
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
                          style: AppTypography.micro.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    for (final item in section.items)
                      _SidebarTile(
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
                    radius: 16,
                    backgroundColor: AppColors.mist,
                    child: Text(
                      profile.fullName.isNotEmpty
                          ? profile.fullName[0].toUpperCase()
                          : '?',
                      style: AppTypography.label.copyWith(color: accent),
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
                          style: AppTypography.label,
                        ),
                        Text(
                          profile.role[0].toUpperCase() + profile.role.substring(1),
                          style: AppTypography.micro,
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
    this.badge,
    required this.collapsed,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String path;
  final int? badge;
  final bool collapsed;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = active ? AppColors.mist : Colors.transparent;
    final fg = active ? AppColors.ink : AppColors.smoke;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: Semantics(
          button: true,
          label: label,
          selected: active,
          child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.button),
          hoverColor: AppColors.mist,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 0 : AppSpacing.sm,
              vertical: 10,
            ),
            child: Row(
              mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: fg),
                if (!collapsed) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      label,
                      style: AppTypography.label.copyWith(
                        color: fg,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (badge != null && badge! > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.charcoal,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(
                        '$badge',
                        style: AppTypography.pill.copyWith(
                          color: AppColors.paper,
                          fontWeight: FontWeight.w600,
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
