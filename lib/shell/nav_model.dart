import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter/widgets.dart';

import '../features/auth/domain/user_church_index.dart';
import '../l10n/app_localizations.dart';

/// One destination in the rail.
@immutable
class SelNavItem {
  const SelNavItem(this.path, this.label, this.icon, {this.badgeKey});

  final String path;
  final String label;
  final IconData icon;

  /// Identifies a live count to render beside the label. Only `pending` is
  /// wired today; the indirection keeps the rail free of provider imports.
  final String? badgeKey;
}

/// A titled cluster of destinations. [title] is null for the trailing utility
/// group, which reads as a footer rather than a section.
@immutable
class SelNavGroup {
  const SelNavGroup(this.title, this.items);

  final String? title;
  final List<SelNavItem> items;
}

/// The consolidated information architecture.
///
/// Twelve destinations became seven. The merges:
///
/// * **Overview** replaces four separate role dashboards with one screen that
///   adapts its blocks to the viewer's role.
/// * **Queue** merges Entries and Approvals. They were the same collection
///   filtered two ways; now it is one list with a status filter, and the
///   pastor's review actions appear inline on pending rows.
/// * **Partners** absorbs Leaderboard as a ranked view of the same records.
/// * **Configuration** merges Partnership arms and Periods — both are
///   setup-once structures, and they were never used independently.
/// * **People** merges Users and Invitations, which are two states of the
///   same thing: someone who is in the church, or on their way in.
List<SelNavGroup> navGroupsFor(
  UserChurchIndex? idx,
  AppLocalizations l10n, {
  bool platformAdmin = false,
}) {
  if (idx == null) return const [];

  final groups = <SelNavGroup>[];

  if (platformAdmin) {
    groups.add(
      SelNavGroup(l10n.navSectionPlatform, [
        SelNavItem(
          '/platform/churches',
          l10n.navPlatformChurches,
          LucideIcons.building2,
        ),
      ]),
    );
  }

  if (idx.isAdmin) {
    groups.addAll([
      SelNavGroup(null, [
        SelNavItem('/overview', l10n.navOverview, LucideIcons.layoutDashboard),
      ]),
      SelNavGroup(l10n.navSectionChurch, [
        SelNavItem('/people', l10n.navPeople, LucideIcons.users),
        SelNavItem(
          '/configuration',
          l10n.navConfiguration,
          LucideIcons.sliders,
        ),
        SelNavItem('/activity', l10n.navActivity, LucideIcons.history),
      ]),
    ]);
  } else if (idx.isPastor) {
    groups.addAll([
      SelNavGroup(null, [
        SelNavItem('/overview', l10n.navOverview, LucideIcons.layoutDashboard),
        SelNavItem(
          '/queue',
          l10n.navQueue,
          LucideIcons.inbox,
          badgeKey: 'pending',
        ),
        SelNavItem('/records', l10n.navRecords, LucideIcons.fileText),
      ]),
      SelNavGroup(l10n.navSectionPartnership, [
        SelNavItem('/partners', l10n.navPartners, LucideIcons.users),
        SelNavItem('/goals', l10n.navGoals, LucideIcons.target),
      ]),
      SelNavGroup(l10n.navSectionChurch, [
        SelNavItem('/people', l10n.navPeople, LucideIcons.userPlus),
        SelNavItem(
          '/configuration',
          l10n.navConfiguration,
          LucideIcons.sliders,
        ),
      ]),
    ]);
  } else {
    groups.addAll([
      SelNavGroup(null, [
        SelNavItem('/overview', l10n.navOverview, LucideIcons.layoutDashboard),
        SelNavItem('/queue', l10n.navQueue, LucideIcons.inbox),
        SelNavItem('/records', l10n.navRecords, LucideIcons.fileText),
        SelNavItem('/partners', l10n.navPartners, LucideIcons.users),
      ]),
    ]);
  }

  // Utility group — no title, reads as a footer.
  groups.add(
    SelNavGroup(null, [
      SelNavItem('/help', l10n.navHelp, LucideIcons.helpCircle),
      SelNavItem('/settings', l10n.navSettings, LucideIcons.settings),
    ]),
  );

  return groups;
}

/// Compact-width destinations. Caps at five so the bar never wraps.
List<SelNavItem> mobileNavFor(UserChurchIndex? idx, AppLocalizations l10n) {
  if (idx == null) return const [];
  if (idx.isAdmin) {
    return [
      SelNavItem('/overview', l10n.navOverview, LucideIcons.layoutDashboard),
      SelNavItem('/people', l10n.navPeople, LucideIcons.users),
      SelNavItem('/configuration', l10n.navConfigShort, LucideIcons.sliders),
      SelNavItem('/settings', l10n.navSettings, LucideIcons.settings),
    ];
  }
  if (idx.isPastor) {
    return [
      SelNavItem('/overview', l10n.navOverview, LucideIcons.layoutDashboard),
      SelNavItem(
        '/queue',
        l10n.navQueue,
        LucideIcons.inbox,
        badgeKey: 'pending',
      ),
      SelNavItem('/records', l10n.navRecords, LucideIcons.fileText),
      SelNavItem('/partners', l10n.navPartners, LucideIcons.users),
      SelNavItem('/settings', l10n.navSettings, LucideIcons.settings),
    ];
  }
  return [
    SelNavItem('/overview', l10n.navOverview, LucideIcons.layoutDashboard),
    SelNavItem('/queue', l10n.navQueue, LucideIcons.inbox),
    SelNavItem('/records', l10n.navRecords, LucideIcons.fileText),
    SelNavItem('/partners', l10n.navPartners, LucideIcons.users),
    SelNavItem('/settings', l10n.navSettings, LucideIcons.settings),
  ];
}
