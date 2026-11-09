// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

/// Firebase Auth's web SDK keeps the signed-in user in this IndexedDB
/// database (and falls back to Web Storage keys starting `firebase:`).
const _authDatabase = 'firebaseLocalStorageDb';

Future<void> forgetSavedAuthSession() async {
  for (final storage in [html.window.localStorage, html.window.sessionStorage]) {
    final keys = storage.keys.where((k) => k.startsWith('firebase:')).toList();
    for (final k in keys) {
      storage.remove(k);
    }
  }
  final idb = html.window.indexedDB;
  if (idb == null) return;
  try {
    // Nothing has opened the database yet (Firebase hasn't started), so the
    // delete is not blocked. Bounded anyway: a stuck delete must not stop the
    // app from starting.
    await idb.deleteDatabase(_authDatabase).timeout(const Duration(seconds: 3));
  } catch (_) {
    // A database that can't be deleted is one we can't vouch for: refuse to
    // carry on and let Auth restore it against the live project.
    throw StateError(
      'Could not clear the saved Firebase sign-in before connecting to the '
      'emulator. Close other tabs of this app and reload.',
    );
  }
}
