import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../data/auth_repository.dart';
import '../data/invite_repository.dart';
import '../domain/church_user.dart';
import '../domain/user_church_index.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

final firebaseFunctionsProvider = Provider<FirebaseFunctions>((ref) {
  return FirebaseFunctions.instanceFor(region: 'us-central1');
});

final firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(firebaseAuthProvider),
    ref.watch(firebaseFunctionsProvider),
  );
});

final inviteRepositoryProvider = Provider<InviteRepository>((ref) {
  return InviteRepository(
    ref.watch(firestoreProvider),
    ref.watch(firebaseFunctionsProvider),
  );
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

final userChurchIndexProvider = StreamProvider<UserChurchIndex?>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(null);
  return ref
      .watch(firestoreProvider)
      .collection('user_church_index')
      .doc(user.uid)
      .snapshots()
      .map(UserChurchIndex.fromSnapshot);
});

final churchUserProfileProvider = StreamProvider<ChurchUser?>((ref) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  final user = ref.watch(authStateProvider).valueOrNull;
  if (idx == null || user == null) return Stream.value(null);
  return ref
      .watch(firestoreProvider)
      .doc('churches/${idx.churchId}/users/${user.uid}')
      .snapshots()
      .map(ChurchUser.fromSnapshot);
});

final churchNameProvider = StreamProvider<String?>((ref) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null) return Stream.value(null);
  return ref.watch(firestoreProvider).doc('churches/${idx.churchId}').snapshots().map(
        (s) => s.data()?['name'] as String?,
      );
});
