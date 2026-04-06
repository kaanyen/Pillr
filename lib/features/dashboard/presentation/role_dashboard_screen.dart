import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import 'admin_dashboard_screen.dart';
import 'pastor_dashboard_screen.dart';
import 'staff_dashboard_screen.dart';

class RoleDashboardScreen extends ConsumerWidget {
  const RoleDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = ref.watch(userChurchIndexProvider);
    return idx.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (data) {
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (data.isAdmin) return const AdminDashboardScreen();
        if (data.isPastor) return const PastorDashboardScreen();
        return const StaffDashboardScreen();
      },
    );
  }
}
