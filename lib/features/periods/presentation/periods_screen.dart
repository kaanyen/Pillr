import 'package:flutter/material.dart';

import '../../../common/widgets/feature_placeholder_scaffold.dart';

class PeriodsScreen extends StatelessWidget {
  const PeriodsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScaffold(
      title: 'Partnership periods',
      message: 'Single active period enforcement uses a Cloud Function in Phase 2.',
    );
  }
}
