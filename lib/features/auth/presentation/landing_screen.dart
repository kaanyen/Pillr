import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import 'widgets/auth_primary_button.dart';
import 'widgets/auth_split_shell.dart';

/// Public entry — invite-based signup CTA only.
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthSplitShell(
      formChild: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Get started',
              style: AppTypography.heading,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Create your account now with an invite from your church.',
              style: AppTypography.bodyMuted,
            ),
            const SizedBox(height: AppSpacing.xl),
            AuthPrimaryButton(
              label: 'Join with invite',
              loading: false,
              onPressed: () => context.go('/join'),
            ),
            const SizedBox(height: AppSpacing.md),
            Center(
              child: TextButton(
                onPressed: () => context.go('/bootstrap-join'),
                child: Text(
                  'Starting a new church? Use your setup code',
                  style: AppTypography.label,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: [
                  Text(
                    'Have an account?',
                    style: AppTypography.caption.copyWith(color: AppColors.smoke),
                  ),
                  TextButton(
                    onPressed: () => context.go('/sign-in'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Sign in',
                      style: AppTypography.labelStrong,
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
