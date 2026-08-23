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

  /// Membership for [uid], or null when the account genuinely belongs to no
  /// church.
  ///
  /// Throws [MembershipUnknown] when it cannot find out. That distinction
  /// matters: the router sends a null to `/join`, and "we could not reach
  /// Firestore" must never be told to somebody as "you have no church".
  static Future<UserChurchIndex?> getOrFetch(String uid) async {
    if (_cachedUid != null && _cachedUid != uid) {
      clear();
    }
    if (_cachedUid == uid && _cachedIndex != null) {
      return _cachedIndex;
    }

    final ref = FirebaseFirestore.instance
        .collection('user_church_index')
        .doc(uid);

    DocumentSnapshot<Map<String, dynamic>> snap;
    try {
      snap = await ref.get();
      // Persistence is on, so a miss can be served from the local cache when
      // the server is unreachable — indistinguishable, from here, from an
      // account with no membership. Ask the server before believing it.
      if (!snap.exists && snap.metadata.isFromCache) {
        snap = await ref.get(const GetOptions(source: Source.server));
      }
    } on FirebaseException catch (e) {
      throw MembershipUnknown(e.code);
    }

    final idx = UserChurchIndex.fromSnapshot(snap);
    _cachedUid = uid;
    _cachedIndex = idx;
    return idx;
  }
}

/// Raised when membership could not be established — offline, emulator down,
/// a transient permission error. Not the same as having none.
class MembershipUnknown implements Exception {
  const MembershipUnknown(this.cause);

  final String cause;

  @override
  String toString() => 'MembershipUnknown($cause)';
}
