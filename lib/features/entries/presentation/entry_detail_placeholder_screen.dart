import 'package:flutter/material.dart';

import '../../../common/widgets/feature_placeholder_scaffold.dart';

class EntryDetailPlaceholderScreen extends StatelessWidget {
  const EntryDetailPlaceholderScreen({super.key, required this.entryId});

  final String entryId;

  @override
  Widget build(BuildContext context) {
    return FeaturePlaceholderScaffold(
      title: 'Entry $entryId',
      message: 'Detail view, history, and actions are part of Phase 2.',
    );
  }
}
