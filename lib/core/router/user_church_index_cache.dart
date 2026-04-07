import 'package:cloud_firestore/cloud_firestore.dart';

import '../../features/auth/domain/user_church_index.dart';

/// Caches [UserChurchIndex] for [GoRouter] redirect (async) to avoid repeated reads.
/// Cleared on sign-out or when [clear] is called.
class UserChurchIndexCache {
  UserChurchIndexCache._();

  static String? _cachedUid;
  static UserChurchIndex? _cachedIndex;

  static void clear() {
    _cachedUid = null;
    _cachedIndex = null;
  }

  static Future<UserChurchIndex?> getOrFetch(String uid) async {
    if (_cachedUid != null && _cachedUid != uid) {
      clear();
    }
    if (_cachedUid == uid && _cachedIndex != null) {
      return _cachedIndex;
    }
    final snap = await FirebaseFirestore.instance
        .collection('user_church_index')
        .doc(uid)
        .get();
    final idx = UserChurchIndex.fromSnapshot(snap);
    _cachedUid = uid;
    _cachedIndex = idx;
    return idx;
  }
}
