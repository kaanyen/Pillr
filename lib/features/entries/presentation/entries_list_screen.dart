import 'package:flutter/material.dart';

import '../../../common/widgets/feature_placeholder_scaffold.dart';

class EntriesListScreen extends StatelessWidget {
  const EntriesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScaffold(
      title: 'Entries',
      message: 'Recording, filters, and real-time lists will connect to Firestore here.',
    );
  }
}
