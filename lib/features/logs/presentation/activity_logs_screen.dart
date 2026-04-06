import 'package:flutter/material.dart';

import '../../../common/widgets/feature_placeholder_scaffold.dart';

class ActivityLogsScreen extends StatelessWidget {
  const ActivityLogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScaffold(
      title: 'Activity logs',
      message: 'Filterable audit timeline with exports is planned for Phase 3.',
      phaseLabel: 'Phase 3',
    );
  }
}
