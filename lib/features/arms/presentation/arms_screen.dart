import 'package:flutter/material.dart';

import '../../../common/widgets/feature_placeholder_scaffold.dart';

class ArmsScreen extends StatelessWidget {
  const ArmsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScaffold(
      title: 'Partnership arms',
      message: 'CRUD, toggles, and activity logging are defined for Phase 2.',
    );
  }
}
