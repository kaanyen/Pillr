import 'package:cloud_firestore/cloud_firestore.dart';

class PlatformAdminCache {
  PlatformAdminCache._();

  static String? _uid;
  static bool? _isAdmin;

  static void clear() {
    _uid = null;
    _isAdmin = null;
  }

  static Future<bool> isPlatformAdmin(String uid) async {
    if (_uid == uid && _isAdmin != null) return _isAdmin!;
    final snap = await FirebaseFirestore.instance.collection('platform_admins').doc(uid).get();
    final v = snap.exists;
    _uid = uid;
    _isAdmin = v;
    return v;
  }
}
