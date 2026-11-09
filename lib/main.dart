import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'core/errors/app_exception.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/constants/app_environment.dart';
import 'core/router/auth_boot_gate.dart';
import 'services/analytics_service.dart';
import 'services/firebase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Real paths (/queue) rather than hash routes (/#/queue). The Firebase
  // Hosting config already rewrites ** to index.html, which is what this
  // needs; without it the address bar does not track in-app navigation, so
  // browser back/forward and copied links behave unpredictably.
  usePathUrlStrategy();
  await Hive.initFlutter();
  await ensureFirebaseInitialized();
  if (!kIsWeb) {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode ? const AndroidDebugProvider() : const AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode ? const AppleDebugProvider() : const AppleDeviceCheckProvider(),
    );
  }
  AuthBootGate.start();

  await logPillrAppOpen();

  if (kDebugMode) {
    debugPrint('Pillr APP_ENV=${AppEnvironmentConfig.current.name}');
  }

  // Release web paints a gray box when a widget throws. Fellowships did that
  // and looked like an empty tab. Show the exception so the page is readable.
  if (kIsWeb) {
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return ColoredBox(
        color: const Color(0xFFF9F9F9),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              details.exceptionAsString(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF1B2045),
                fontSize: 16,
              ),
            ),
          ),
        ),
      );
    };
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

  runApp(const ProviderScope(retry: retryOnlyWhatCanSucceed, child: PillrApp()));
}

/// Riverpod retries a failed provider, showing it as loading meanwhile. An
/// answer that cannot change on a second try — refused, missing, signed out,
/// wrong input — is shown at once instead, so a page says what happened
/// rather than spinning. Anything else (no connection, a busy server) is
/// retried a few times, as before.
Duration? retryOnlyWhatCanSucceed(int retryCount, Object error) {
  if (error is FirebaseException &&
      const {
        'permission-denied',
        'unauthenticated',
        'not-found',
        'invalid-argument',
        'failed-precondition',
        'already-exists',
        'unimplemented',
        'unauthorized',
        'object-not-found',
      }.contains(error.code)) {
    return null;
  }
  if (error is AppException || error is StateError || error is ArgumentError || error is TypeError) {
    return null;
  }
  if (retryCount >= 3) return null;
  return Duration(milliseconds: 400 * (1 << retryCount));
}

