import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/constants/app_environment.dart';
import 'services/analytics_service.dart';
import 'services/firebase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ensureFirebaseInitialized();
  await logPillrAppOpen();

  if (kDebugMode) {
    debugPrint('Pillr APP_ENV=${AppEnvironmentConfig.current.name}');
  }

  // firebase_crashlytics has no web implementation; calling it on web throws
  // MissingPluginException and prevents runApp (blank page).
  if (!kIsWeb) {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(kReleaseMode);
    FlutterError.onError = (details) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  runApp(const ProviderScope(child: PillrApp()));
}
