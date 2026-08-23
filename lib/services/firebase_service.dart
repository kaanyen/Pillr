import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

/// Routes every Firebase SDK at the local emulator suite instead of the live
/// project. Off unless the build explicitly opts in:
///
/// ```bash
/// firebase emulators:start
/// flutter run -d chrome --dart-define=USE_EMULATORS=true
/// ```
///
/// Must be `const` — on web, a non-const [bool.fromEnvironment] is evaluated at
/// runtime and would not be tree-shaken out of production builds. As written,
/// a build without the flag compiles this away entirely.
const bool kUseFirebaseEmulators =
    bool.fromEnvironment('USE_EMULATORS', defaultValue: false);

/// Emulator host. `localhost` for desktop/web; Android's loopback is 10.0.2.2.
const String kEmulatorHost =
    String.fromEnvironment('EMULATOR_HOST', defaultValue: 'localhost');

/// Ports mirror the `emulators` block in `firebase.json`.
const int _authPort = 9099;
const int _firestorePort = 8080;
const int _functionsPort = 5001;
const int _storagePort = 9199;

/// Ensures Firebase is initialized exactly once per process.
Future<void> ensureFirebaseInitialized() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
  await _connectToEmulatorsIfEnabled();
  await configureFirestorePersistence();
}

Future<void> _connectToEmulatorsIfEnabled() async {
  if (!kUseFirebaseEmulators) return;

  FirebaseFirestore.instance.useFirestoreEmulator(kEmulatorHost, _firestorePort);
  await FirebaseAuth.instance.useAuthEmulator(kEmulatorHost, _authPort);
  FirebaseStorage.instance.useStorageEmulator(kEmulatorHost, _storagePort);
  FirebaseFunctions.instanceFor(region: 'us-central1')
      .useFunctionsEmulator(kEmulatorHost, _functionsPort);

  debugPrint(
    'Firebase: using LOCAL EMULATORS at $kEmulatorHost '
    '(auth:$_authPort firestore:$_firestorePort '
    'functions:$_functionsPort storage:$_storagePort) — '
    'no production data is being read or written.',
  );
}

/// Offline cache (§16.4.6). Native SDK supports [Settings]; web uses default cache behavior.
Future<void> configureFirestorePersistence() async {
  if (Firebase.apps.isEmpty) return;
  if (kIsWeb) return;
  // Persistence must not be enabled after the emulator override above, and the
  // emulator has no use for an on-disk cache during a screenshot run.
  if (kUseFirebaseEmulators) return;
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
}
