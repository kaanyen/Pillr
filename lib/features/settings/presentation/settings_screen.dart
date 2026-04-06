import 'package:flutter/material.dart';

import '../../../common/widgets/feature_placeholder_scaffold.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScaffold(
      title: 'Settings',
      message: 'Branding, notifications, and security preferences will grow through later phases.',
      phaseLabel: 'Phase 4',
    );
  }
}
