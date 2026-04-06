import 'package:firebase_messaging/firebase_messaging.dart';

/// FCM wiring for approval notifications — expanded in Phase 2+.
Future<void> initPushNotifications() async {
  await FirebaseMessaging.instance.requestPermission();
}
