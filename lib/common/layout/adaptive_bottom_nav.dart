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
    return NavigationBar(
      selectedIndex: idx >= 0 ? idx : 0,
      height: 64,
      backgroundColor: AppColors.white,
      indicatorColor: AppColors.navActiveBackground,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      onDestinationSelected: (i) => context.go(items[i].path),
      destinations: [
        for (final item in items)
          NavigationDestination(
            icon: Icon(item.icon),
            selectedIcon: Icon(item.selectedIcon, color: AppColors.navActiveForeground),
            label: item.label,
          ),
      ],
    );
  }
}
