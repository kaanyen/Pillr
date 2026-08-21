import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter/widgets.dart';

import '../features/auth/domain/user_church_index.dart';

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
List<SelNavGroup> navGroupsFor(UserChurchIndex? idx, {bool platformAdmin = false}) {
  if (idx == null) return const [];

  final groups = <SelNavGroup>[];

  if (platformAdmin) {
    groups.add(const SelNavGroup('Platform', [
      SelNavItem('/platform/churches', 'All churches', LucideIcons.building2),
    ]));
  }

  if (idx.isAdmin) {
    groups.addAll(const [
      SelNavGroup(null, [
        SelNavItem('/overview', 'Overview', LucideIcons.layoutDashboard),
      ]),
      SelNavGroup('Church', [
        SelNavItem('/people', 'People', LucideIcons.users),
        SelNavItem('/configuration', 'Configuration', LucideIcons.sliders),
        SelNavItem('/activity', 'Activity', LucideIcons.history),
      ]),
    ]);
  } else if (idx.isPastor) {
    groups.addAll(const [
      SelNavGroup(null, [
        SelNavItem('/overview', 'Overview', LucideIcons.layoutDashboard),
        SelNavItem('/queue', 'Queue', LucideIcons.inbox, badgeKey: 'pending'),
        SelNavItem('/records', 'Records', LucideIcons.fileText),
      ]),
      SelNavGroup('Partnership', [
        SelNavItem('/partners', 'Partners', LucideIcons.users),
        SelNavItem('/goals', 'Goals', LucideIcons.target),
      ]),
      SelNavGroup('Church', [
        SelNavItem('/people', 'People', LucideIcons.userPlus),
        SelNavItem('/configuration', 'Configuration', LucideIcons.sliders),
      ]),
    ]);
  } else {
    groups.addAll(const [
      SelNavGroup(null, [
        SelNavItem('/overview', 'Overview', LucideIcons.layoutDashboard),
        SelNavItem('/queue', 'Queue', LucideIcons.inbox),
        SelNavItem('/records', 'Records', LucideIcons.fileText),
        SelNavItem('/partners', 'Partners', LucideIcons.users),
      ]),
    ]);
  }

  // Utility group — no title, reads as a footer.
  groups.add(const SelNavGroup(null, [
    SelNavItem('/help', 'Help', LucideIcons.helpCircle),
    SelNavItem('/settings', 'Settings', LucideIcons.settings),
  ]));

  return groups;
}

/// Compact-width destinations. Caps at five so the bar never wraps.
List<SelNavItem> mobileNavFor(UserChurchIndex? idx) {
  if (idx == null) return const [];
  if (idx.isAdmin) {
    return const [
      SelNavItem('/overview', 'Overview', LucideIcons.layoutDashboard),
      SelNavItem('/people', 'People', LucideIcons.users),
      SelNavItem('/configuration', 'Config', LucideIcons.sliders),
      SelNavItem('/settings', 'Settings', LucideIcons.settings),
    ];
  }
  if (idx.isPastor) {
    return const [
      SelNavItem('/overview', 'Overview', LucideIcons.layoutDashboard),
      SelNavItem('/queue', 'Queue', LucideIcons.inbox, badgeKey: 'pending'),
      SelNavItem('/records', 'Records', LucideIcons.fileText),
      SelNavItem('/partners', 'Partners', LucideIcons.users),
      SelNavItem('/settings', 'Settings', LucideIcons.settings),
    ];
  }
  return const [
    SelNavItem('/overview', 'Overview', LucideIcons.layoutDashboard),
    SelNavItem('/queue', 'Queue', LucideIcons.inbox),
    SelNavItem('/records', 'Records', LucideIcons.fileText),
    SelNavItem('/partners', 'Partners', LucideIcons.users),
    SelNavItem('/settings', 'Settings', LucideIcons.settings),
  ];
}
