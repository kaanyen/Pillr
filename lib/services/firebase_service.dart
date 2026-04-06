import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';

/// Ensures Firebase is initialized exactly once per process.
Future<void> ensureFirebaseInitialized() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
}
