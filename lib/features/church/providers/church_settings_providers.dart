import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/church_settings_repository.dart';
import '../domain/church_settings.dart';

final churchSettingsRepositoryProvider = Provider<ChurchSettingsRepository>((ref) {
  return ChurchSettingsRepository(ref.watch(firestoreProvider));
});

final churchSettingsProvider = StreamProvider<ChurchSettings?>((ref) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null) return Stream.value(null);
  return ref.watch(churchSettingsRepositoryProvider).watchChurch(idx.churchId);
});

/// Church display name (convenience for UI).
final churchNameProvider = Provider<String?>((ref) {
  return ref.watch(churchSettingsProvider).valueOrNull?.name;
});
