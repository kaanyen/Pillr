import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

/// Ensures Firebase is initialized exactly once per process.
Future<void> ensureFirebaseInitialized() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
  await configureFirestorePersistence();
}

/// Offline cache (§16.4.6). Native SDK supports [Settings]; web uses default cache behavior.
Future<void> configureFirestorePersistence() async {
  if (Firebase.apps.isEmpty) return;
  if (kIsWeb) return;
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
}
