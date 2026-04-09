import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_providers.dart';
import '../../entries/providers/entries_providers.dart';

/// In-app notification center shell (§16.4.6) — links to actionable areas.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final pending = ref.watch(pendingApprovalCountProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Notifications', style: AppTypography.heading2),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'FCM pushes and daily digests are configured in Cloud Functions. '
            'Use this list for quick links to items that need attention.',
            style: AppTypography.body,
          ),
          const SizedBox(height: AppSpacing.xl),
          if (idx?.isPastor == true && pending > 0)
            Card(
              child: ListTile(
                leading: const Icon(LucideIcons.clipboardCheck),
                title: Text('$pending pending entr${pending == 1 ? 'y' : 'ies'}'),
                subtitle: const Text('Awaiting your approval'),
                trailing: const Icon(LucideIcons.chevronRight),
                onTap: () => context.go('/approvals'),
              ),
            ),
          if (idx?.isStaff == true)
            Card(
              child: ListTile(
                leading: const Icon(LucideIcons.fileText),
                title: const Text('Your entries'),
                subtitle: const Text('Track pending and declined items'),
                trailing: const Icon(LucideIcons.chevronRight),
                onTap: () => context.go('/entries'),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Tip: enable or disable digest-style messages under Settings → Notifications.',
            style: AppTypography.caption,
          ),
        ],
      ),
    );
  }
}
