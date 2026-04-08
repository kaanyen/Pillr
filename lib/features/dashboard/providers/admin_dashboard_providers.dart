import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../auth/domain/invite_models.dart';
import '../../auth/providers/auth_providers.dart';

final invitesListForAdminProvider =
    StreamProvider.autoDispose<List<InviteRecord>>((ref) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null || !idx.isAdmin) return Stream.value([]);
  return ref.watch(inviteRepositoryProvider).watchInvites(idx.churchId);
});

final pendingInvitesCountProvider = Provider<int>((ref) {
  final list = ref.watch(invitesListForAdminProvider).valueOrNull ?? [];
  return list.where((i) => i.status == 'pending').length;
});

final churchUsersCountProvider = StreamProvider.autoDispose<int>((ref) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null || !idx.isAdmin) return Stream.value(0);
  return ref
      .watch(firestoreProvider)
      .collection('churches')
      .doc(idx.churchId)
      .collection('users')
      .snapshots()
      .map((s) => s.docs.length);
});
