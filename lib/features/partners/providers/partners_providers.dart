import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/partners_repository.dart';
import '../domain/partner.dart';

final partnersRepositoryProvider = Provider<PartnersRepository>((ref) {
  return PartnersRepository(ref.watch(firestoreProvider));
});

final partnersStreamProvider =
    StreamProvider.autoDispose.family<List<Partner>, bool>((ref, includeInactive) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null) return Stream.value([]);
  return ref.watch(partnersRepositoryProvider).watchPartners(idx.churchId, includeInactive: includeInactive);
});

final partnerStreamProvider = StreamProvider.autoDispose.family<Partner?, String>((ref, partnerId) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null) return Stream.value(null);
  return ref.watch(partnersRepositoryProvider).watchPartner(idx.churchId, partnerId);
});
