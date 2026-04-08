import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../activity/domain/activity_log_row.dart';
import '../../activity/providers/activity_log_providers.dart';
import '../../auth/providers/auth_providers.dart';

/// Short preview for dashboards (admin + pastor; staff: empty).
final activityLogsPreviewProvider = StreamProvider.autoDispose<List<ActivityLogRow>>((ref) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null) return Stream.value([]);
  if (idx.isStaff) return Stream.value([]);
  return ref.watch(activityLogRepositoryProvider).watchActivityLogs(idx.churchId, limit: 20);
});
