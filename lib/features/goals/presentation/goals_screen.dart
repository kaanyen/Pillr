import 'package:flutter/material.dart';

import '../../../common/widgets/feature_placeholder_scaffold.dart';

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScaffold(
      title: 'Goals',
      message: 'Period and arm targets with live progress bars ship in Phase 3.',
      phaseLabel: 'Phase 3',
    );
  }
}
