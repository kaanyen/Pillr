import 'package:flutter/material.dart';
import 'package:the_pillr/l10n/app_localizations.dart';

import '../design/seline.dart';

/// Help — long-form copy on the narrow reading measure.
///
/// The only screen in the app that is prose rather than records, so it drops
/// the ledger and card grid entirely: one column, one panel per topic, at the
/// system's 16px lead size for readability rather than 14px UI size.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final topics = <(String, String)>[
      (l10n.helpSectionPeriodTitle, l10n.helpSectionPeriodBody),
      (l10n.helpSectionArmTitle, l10n.helpSectionArmBody),
      (l10n.helpSectionPartnerTitle, l10n.helpSectionPartnerBody),
      (l10n.helpSectionApprovalTitle, l10n.helpSectionApprovalBody),
      (l10n.helpSectionGoalsTitle, l10n.helpSectionGoalsBody),
      (l10n.helpSectionNotificationsTitle, l10n.helpSectionNotificationsBody),
    ];

    return SelPageBody(
      maxWidth: 720,
      children: [
        SelPageTitle(
          title: l10n.titleHelp,
          subtitle: l10n.helpIntro,
        ),
        for (var i = 0; i < topics.length; i++) ...[
          if (i > 0) const SizedBox(height: SelSpace.x4),
          SelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(topics[i].$1, style: SelType.subtitle),
                const SizedBox(height: SelSpace.x2),
                Text(topics[i].$2, style: SelType.lead),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
