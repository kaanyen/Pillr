import 'package:flutter/material.dart';

import '../../../common/widgets/feature_placeholder_scaffold.dart';

class PartnerProfilePlaceholderScreen extends StatelessWidget {
  const PartnerProfilePlaceholderScreen({super.key, required this.partnerId});

  final String partnerId;

  @override
  Widget build(BuildContext context) {
    return FeaturePlaceholderScaffold(
      title: 'Partner $partnerId',
      message: 'Giving history and profile editing are scheduled for Phase 3.',
      phaseLabel: 'Phase 3',
    );
  }
}
