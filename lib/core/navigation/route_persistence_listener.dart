import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'last_route_storage.dart';

/// Saves the current shell route whenever navigation changes (for resume-after-login).
class RoutePersistenceListener extends StatefulWidget {
  const RoutePersistenceListener({super.key, required this.child});

  final Widget child;

  @override
  State<RoutePersistenceListener> createState() => _RoutePersistenceListenerState();
}

class _RoutePersistenceListenerState extends State<RoutePersistenceListener> {
  String? _lastSavedPath;

  void _maybeSave(String path) {
    if (path == _lastSavedPath) return;
    if (!LastRouteStorage.isRestorable(path)) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _lastSavedPath = path;
    LastRouteStorage.save(uid, path);
  }

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).matchedLocation;
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeSave(path));
    return widget.child;
  }
}
