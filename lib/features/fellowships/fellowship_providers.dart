import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../church/providers/church_settings_providers.dart';
import 'fellowship_ops.dart';

final fellowshipOpsProvider = Provider<FellowshipOps>((ref) {
  return FellowshipOps(ref.watch(churchSettingsRepositoryProvider));
});
