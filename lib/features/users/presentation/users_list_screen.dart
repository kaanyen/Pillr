import 'package:flutter/material.dart';

import '../../../common/widgets/feature_placeholder_scaffold.dart';

class UsersListScreen extends StatelessWidget {
  const UsersListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScaffold(
      title: 'Users',
      message: 'Directory of church members and roles expands in Phase 4.',
      phaseLabel: 'Phase 4',
    );
  }
}
