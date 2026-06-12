import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/platform_repository.dart';

final platformRepositoryProvider = Provider<PlatformRepository>((ref) {
  return PlatformRepository(ref.watch(firebaseFunctionsProvider));
});

final platformChurchesListProvider = FutureProvider<List<PlatformChurchSummary>>((ref) {
  return ref.watch(platformRepositoryProvider).listChurchSummaries();
});

final isPlatformAdminProvider = StreamProvider<bool>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(false);
  return ref
      .watch(firestoreProvider)
      .collection('platform_admins')
      .doc(user.uid)
      .snapshots()
      .map((s) => s.exists);
});
