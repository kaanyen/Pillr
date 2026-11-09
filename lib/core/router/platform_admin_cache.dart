import 'package:cloud_firestore/cloud_firestore.dart';

import 'user_church_index_cache.dart' show MembershipUnknown;

class PlatformAdminCache {
  PlatformAdminCache._();

  static String? _uid;
  static bool? _isAdmin;

  static void clear() {
    _uid = null;
    _isAdmin = null;
  }

  /// Throws [MembershipUnknown] when Firestore cannot be reached. Before this
  /// the raw FirebaseException escaped the router's redirect as an uncaught
  /// GoException ("client is offline"), right after a successful sign-in.
  static Future<bool> isPlatformAdmin(String uid) async {
    if (_uid == uid && _isAdmin != null) return _isAdmin!;
    final DocumentSnapshot<Map<String, dynamic>> snap;
    try {
      snap = await FirebaseFirestore.instance
          .collection('platform_admins')
          .doc(uid)
          .get();
    } on FirebaseException catch (e) {
      throw MembershipUnknown(e.code);
    }
    final v = snap.exists;
    _uid = uid;
    _isAdmin = v;
    return v;
  }
}
