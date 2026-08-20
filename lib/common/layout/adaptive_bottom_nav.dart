import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

class BottomNavItem {
  const BottomNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.path,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String path;
}

/// Bottom navigation for compact widths.
///
/// A Fog hairline on top rather than elevation, a Mist pill on the active
/// destination, and weight (not color) marking selection — the same grammar
/// the sidebar uses.
class AdaptiveBottomNav extends StatelessWidget {
  const AdaptiveBottomNav({
    super.key,
    required this.items,
    required this.currentPath,
  });

  final List<BottomNavItem> items;
  final String currentPath;

  @override
  Widget build(BuildContext context) {
    final idx = items.indexWhere((e) => currentPath == e.path || currentPath.startsWith('${e.path}/'));
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.paper,
        border: Border(
          top: BorderSide(color: AppColors.fog, width: AppBorders.hairline),
        ),
      ),
      child: NavigationBar(
        selectedIndex: idx >= 0 ? idx : 0,
        height: 64,
        elevation: 0,
        backgroundColor: AppColors.paper,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        indicatorColor: AppColors.mist,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) => context.go(items[i].path),
        destinations: [
          for (final item in items)
            NavigationDestination(
              icon: Icon(item.icon, color: AppColors.smoke, size: 20),
              selectedIcon: Icon(item.selectedIcon, color: AppColors.ink, size: 20),
              label: item.label,
            ),
        ],
      ),
    );
  }
}
