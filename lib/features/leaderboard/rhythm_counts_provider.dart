import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/firebase_constants.dart';
import '../auth/providers/auth_providers.dart';
import 'fellowship_rhythm.dart';

/// The giving rhythm as counts from the server, for staff, who cannot read
/// the church's giving themselves. No names and no amounts.
final rhythmCountsProvider = FutureProvider.autoDispose<({List<int> months, List<RhythmCounts> fellowships})>((ref) async {
  final r = await ref
      .watch(firebaseFunctionsProvider)
      .httpsCallable(FirebaseConstants.fellowshipRhythmCounts)
      .call(<String, dynamic>{});
  final d = Map<String, dynamic>.from(r.data as Map);
  return (
    months: [for (final m in (d['months'] as List? ?? const [])) (m as num).toInt()],
    fellowships: [
      for (final f in (d['fellowships'] as List? ?? const []))
        () {
          final m = Map<String, dynamic>.from(f as Map);
          return RhythmCounts(
            key: m['key'] as String? ?? '',
            name: m['name'] as String? ?? 'No fellowship',
            partners: (m['partners'] as num?)?.toInt() ?? 0,
            gave: {
              for (final e in Map<String, dynamic>.from(m['gave'] as Map? ?? const {}).entries)
                int.parse(e.key): (e.value as num).toInt(),
            },
          );
        }(),
    ],
  );
});
