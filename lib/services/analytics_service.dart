import 'package:firebase_analytics/firebase_analytics.dart';

FirebaseAnalytics get analytics => FirebaseAnalytics.instance;

/// Call once after Firebase init so Analytics receives a session (build doc §4.12).
Future<void> logPillrAppOpen() => analytics.logAppOpen();
