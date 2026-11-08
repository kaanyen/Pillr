import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/extensions/async_value_ext.dart';
import '../../core/utils/money.dart';
import '../auth/providers/auth_providers.dart';

/// What a partner or period has received, as the server keeps it.
class StoredTotals {
  const StoredTotals({required this.cedis, required this.count});

  final double cedis;
  final int count;

  static const zero = StoredTotals(cedis: 0, count: 0);

  factory StoredTotals.fromMap(Map<String, dynamic> m) => StoredTotals(
    cedis: storedTotalCedis(m, pesewasKey: 'totalApprovedPesewas', cedisKey: 'totalApprovedAmount'),
    count: ((m['entryCount'] ?? 0) as num).toInt(),
  );
}

Stream<Map<String, StoredTotals>> _watch(Ref ref, String collection) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  // Pastors only: the records are closed to everyone else.
  if (idx == null || !idx.isPastor) return Stream.value(const {});
  return ref
      .watch(firestoreProvider)
      .collection('churches')
      .doc(idx.churchId)
      .collection(collection)
      .snapshots()
      .map((s) => {for (final d in s.docs) d.id: StoredTotals.fromMap(d.data())});
}

/// Each partner's stored total, for pastors. Empty for everyone else.
final partnerTotalsProvider = StreamProvider.autoDispose<Map<String, StoredTotals>>(
  (ref) => _watch(ref, 'partner_totals'),
);

/// Each period's stored total, for pastors. Empty for everyone else.
final periodTotalsProvider = StreamProvider.autoDispose<Map<String, StoredTotals>>(
  (ref) => _watch(ref, 'period_totals'),
);
