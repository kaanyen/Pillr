import 'package:cloud_firestore/cloud_firestore.dart';

/// Cached church flags for router redirects (suspended tenant, onboarding).
class ChurchTenantGateCache {
  ChurchTenantGateCache._();

  static String? _cachedUid;
  static String? _cachedChurchId;
  static bool? _isActive;
  static bool? _setupComplete;

  static void clear() {
    _cachedUid = null;
    _cachedChurchId = null;
    _isActive = null;
    _setupComplete = null;
  }

  /// Fetches [churches/churchId] once per (uid, churchId) until [clear].
  static Future<({bool isActive, bool setupComplete})> getOrFetch({
    required String uid,
    required String churchId,
  }) async {
    if (_cachedUid == uid && _cachedChurchId == churchId && _isActive != null && _setupComplete != null) {
      return (isActive: _isActive!, setupComplete: _setupComplete!);
    }
    final snap = await FirebaseFirestore.instance.collection('churches').doc(churchId).get();
    final data = snap.data();
    final isActive = data?['isActive'] != false;
    final ts = data?['churchSetupCompletedAt'];
    final setupComplete = ts != null;
    _cachedUid = uid;
    _cachedChurchId = churchId;
    _isActive = isActive;
    _setupComplete = setupComplete;
    return (isActive: isActive, setupComplete: setupComplete);
  }
}
