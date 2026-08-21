import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../design/seline.dart';
import 'auth_shell.dart';

/// Public entry. Pillr is invite-only, so this screen's whole job is to route
/// someone to the right door: a code they were emailed, or an account.
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: 'Partnership giving, ',
      highlight: 'accounted for',
      subtitle:
          'Pillr is invite-only. Use the code your church emailed you, or sign '
          'in to an account you already have.',
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Starting a new church? '),
          GestureDetector(
            onTap: () => context.go('/bootstrap-join'),
            child: Text(
              'Use your setup code',
              style: SelType.small.copyWith(
                color: Sel.cyanEdge,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SelButton.cyan(
            label: 'Join with an invite code',
            icon: LucideIcons.mail,
            expanded: true,
            onPressed: () => context.go('/join'),
          ),
          const SizedBox(height: SelSpace.x3),
          SelButton(
            label: 'Sign in',
            expanded: true,
            onPressed: () => context.go('/sign-in'),
          ),
        ],
      ),
    );
  }
}
