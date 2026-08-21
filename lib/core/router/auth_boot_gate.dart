import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

/// Tracks whether Firebase has reported an initial auth state yet.
///
/// On a cold load of a protected route — a refresh, or a bookmarked link —
/// the router's redirect runs before Firebase has restored the persisted
/// session. `currentUser` is null at that moment, so the redirect concludes
/// the visitor is signed out and sends them to the landing page, losing where
/// they were going.
///
/// Awaiting `authStateChanges().first` in `main()` does not fix it: that
/// stream emits the current (null) value before restoration completes, so the
/// await returns immediately.
///
/// Instead the redirect defers while [settled] is false — returning no
/// redirect leaves the requested route in place — and go_router re-runs it
/// when the auth stream fires, by which point the answer is real.
abstract final class AuthBootGate {
  static bool _settled = false;
  static StreamSubscription<User?>? _sub;
  static Timer? _failsafe;

  /// True once an auth state has actually been reported, or the failsafe has
  /// elapsed. Redirects should not make sign-in decisions before this.
  static bool get settled => _settled;

  /// Call once, after Firebase is initialised.
  static void start() {
    if (_sub != null) return;
    _sub = FirebaseAuth.instance.authStateChanges().listen((_) => _markSettled());
    // If the SDK never reports for some reason, do not strand the router in a
    // permanently undecided state.
    _failsafe = Timer(const Duration(seconds: 3), _markSettled);
  }

  static void _markSettled() {
    if (_settled) return;
    _settled = true;
    _failsafe?.cancel();
    _failsafe = null;
  }

  /// Test seam.
  static void resetForTest({bool settled = false}) {
    _settled = settled;
    _sub?.cancel();
    _sub = null;
    _failsafe?.cancel();
    _failsafe = null;
  }
}
