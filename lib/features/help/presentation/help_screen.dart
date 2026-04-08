import 'package:flutter/material.dart';
import 'package:the_pillr/l10n/app_localizations.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// Short reference for how partnership recording works (build doc tone).
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.titleHelp, style: AppTypography.heading2),
              const SizedBox(height: AppSpacing.md),
              Text(l10n.helpIntro, style: AppTypography.body),
              const SizedBox(height: AppSpacing.xl),
              _HelpSection(title: l10n.helpSectionPeriodTitle, body: l10n.helpSectionPeriodBody),
              _HelpSection(title: l10n.helpSectionArmTitle, body: l10n.helpSectionArmBody),
              _HelpSection(title: l10n.helpSectionPartnerTitle, body: l10n.helpSectionPartnerBody),
              _HelpSection(title: l10n.helpSectionApprovalTitle, body: l10n.helpSectionApprovalBody),
              _HelpSection(title: l10n.helpSectionGoalsTitle, body: l10n.helpSectionGoalsBody),
              _HelpSection(title: l10n.helpSectionNotificationsTitle, body: l10n.helpSectionNotificationsBody),
            ],
          ),
        ),
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.heading3),
          const SizedBox(height: AppSpacing.sm),
          Text(body, style: AppTypography.body),
        ],
      ),
    );
  }
}
