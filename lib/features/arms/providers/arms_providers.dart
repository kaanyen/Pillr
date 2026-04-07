import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/arms_repository.dart';
import '../domain/partnership_arm.dart';

final armsRepositoryProvider = Provider<ArmsRepository>((ref) {
  return ArmsRepository(ref.watch(firestoreProvider));
});

final armsStreamProvider = StreamProvider.autoDispose<List<PartnershipArm>>((ref) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null) return Stream.value([]);
  return ref.watch(armsRepositoryProvider).watchArms(idx.churchId);
});
