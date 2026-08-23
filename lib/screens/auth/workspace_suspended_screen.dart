import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../design/seline.dart';
import '../../features/auth/providers/auth_providers.dart';
import 'auth_shell.dart';

/// Shown when `churches/{id}.isActive` is false. Read-only and calm — the
/// person seeing this did nothing wrong and cannot fix it themselves.
class WorkspaceSuspendedScreen extends ConsumerWidget {
  const WorkspaceSuspendedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AuthShell(
      title: 'Workspace unavailable',
      subtitle:
          'Your church workspace is currently paused. Your data is safe — a '
          'platform administrator can restore access.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                height: 34,
                width: 34,
                decoration: BoxDecoration(
                  color: Sel.canvas,
                  borderRadius: BorderRadius.circular(SelRadius.icon),
                  border: Border.all(color: Sel.border),
                ),
                child: const Icon(LucideIcons.pauseCircle, size: 15, color: Sel.ash),
              ),
              const SizedBox(width: SelSpace.x3),
              Expanded(
                child: Text(
                  'Contact whoever set up your church on Pillr.',
                  style: SelType.bodyMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: SelSpace.x6),
          SelButton(
            label: 'Sign out',
            expanded: true,
            onPressed: () async {
              await ref.read(authRepositoryProvider).signOut();
              if (context.mounted) context.go('/');
            },
          ),
        ],
      ),
    );
  }
}
