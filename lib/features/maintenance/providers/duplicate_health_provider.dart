import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../../core/utils/date_utils.dart';
import '../../auth/providers/auth_providers.dart';

/// What last night's duplicate check found (functions/src/duplicate_scan.ts).
class DuplicateHealth {
  const DuplicateHealth({
    required this.open,
    required this.groups,
    required this.check,
    this.checkedAt,
  });

  /// Pairs that are very likely or probably one person. The Tools badge.
  final int open;

  /// People entered three or more times.
  final int groups;

  /// Weaker pairs, worth a look but not a badge.
  final int check;
  final DateTime? checkedAt;
}

final duplicateHealthProvider = StreamProvider.autoDispose<DuplicateHealth?>((ref) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null || !idx.canUseTools) return Stream.value(null);
  return ref
      .watch(firestoreProvider)
      .doc('churches/${idx.churchId}/health/duplicates')
      .snapshots()
      .map((s) {
        final m = s.data();
        if (m == null) return null;
        int n(String k) => (m[k] as num?)?.toInt() ?? 0;
        return DuplicateHealth(
          open: n('open'),
          groups: n('groups'),
          check: n('check'),
          checkedAt: timestampToDateTime(m['checkedAt']),
        );
      })
      .handleError((_) {});
});

/// The Tools badge: 0 hides it.
final duplicateBadgeCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(duplicateHealthProvider).valueOrNull?.open ?? 0;
});
