import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/periods_repository.dart';
import '../domain/partnership_period.dart';

final periodsRepositoryProvider = Provider<PeriodsRepository>((ref) {
  return PeriodsRepository(
    ref.watch(firestoreProvider),
    ref.watch(firebaseFunctionsProvider),
  );
});

final periodsStreamProvider = StreamProvider.autoDispose<List<PartnershipPeriod>>((ref) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null) return Stream.value([]);
  return ref.watch(periodsRepositoryProvider).watchPeriods(idx.churchId);
});

final activePeriodProvider = Provider<PartnershipPeriod?>((ref) {
  final list = ref.watch(periodsStreamProvider).valueOrNull;
  if (list == null) return null;
  try {
    return list.firstWhere((p) => p.isActive);
  } catch (_) {
    return null;
  }
});
