import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'role_route_access.dart';
import 'user_church_index_cache.dart';

/// Global redirect: auth gate, `/` → login|dashboard, incomplete registration → `/join`,
/// role-based access (build doc §6).
FutureOr<String?> appRouterRedirect(BuildContext context, GoRouterState state) async {
  final loc = state.matchedLocation;
  final auth = FirebaseAuth.instance.currentUser;

  if (auth == null) {
    UserChurchIndexCache.clear();
  }

  if (loc == '/') {
    return auth == null ? '/login' : '/dashboard';
  }

  if (auth == null) {
    if (loc == '/login' || loc.startsWith('/join')) return null;
    return '/login';
  }

  if (loc == '/login') return '/dashboard';

  final idx = await UserChurchIndexCache.getOrFetch(auth.uid);
  if (idx == null) {
    if (loc.startsWith('/join')) return null;
    return '/join';
  }

  if (isPathForbiddenForRole(loc, idx.role)) {
    return '/dashboard';
  }

  return null;
}
