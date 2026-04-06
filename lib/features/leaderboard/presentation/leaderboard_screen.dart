import 'package:flutter/material.dart';

import '../../../common/widgets/feature_placeholder_scaffold.dart';

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScaffold(
      title: 'Leaderboard',
      message: 'Ranked partners with period and arm filters arrive in Phase 3.',
      phaseLabel: 'Phase 3',
    );
  }
}
