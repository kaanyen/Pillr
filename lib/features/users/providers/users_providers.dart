import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../auth/domain/church_user.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/users_repository.dart';

final usersRepositoryProvider = Provider<UsersRepository>((ref) {
  return UsersRepository(
    ref.watch(firestoreProvider),
    ref.watch(firebaseFunctionsProvider),
  );
});

final churchUsersProvider = StreamProvider<List<ChurchUser>>((ref) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null) return Stream.value([]);
  return ref.watch(usersRepositoryProvider).watchUsers(idx.churchId);
});
