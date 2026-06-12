import 'package:shared_preferences/shared_preferences.dart';

/// Persists the last in-app shell route per user so sign-in can resume where they left off.
abstract final class LastRouteStorage {
  static String _key(String uid) => 'pillr_last_route_$uid';

  static const _maxLength = 256;

  /// Paths we never restore (auth, onboarding, platform).
  static bool isRestorable(String path) {
    if (path.isEmpty || path == '/') return false;
    if (path.startsWith('/sign-in') ||
        path.startsWith('/login') ||
        path.startsWith('/join') ||
        path.startsWith('/bootstrap-join') ||
        path.startsWith('/onboarding') ||
        path.startsWith('/workspace-suspended') ||
        path.startsWith('/platform')) {
      return false;
    }
    return path.startsWith('/');
  }

  static Future<void> save(String uid, String path) async {
    if (!isRestorable(path)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(uid), path.length > _maxLength ? path.substring(0, _maxLength) : path);
  }

  static Future<String?> load(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_key(uid));
    if (v == null || v.isEmpty || !isRestorable(v)) return null;
    return v;
  }

  static Future<void> clear(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(uid));
  }
}
