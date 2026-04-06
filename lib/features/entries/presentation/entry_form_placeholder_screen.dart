import 'package:flutter/material.dart';

import '../../../common/widgets/feature_placeholder_scaffold.dart';

class EntryFormPlaceholderScreen extends StatelessWidget {
  const EntryFormPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScaffold(
      title: 'New entry',
      message: 'Partner search, arms, periods, and approval submission ship in Phase 2.',
    );
  }
}
