import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../navigation/last_route_storage.dart';
import 'church_tenant_gate_cache.dart';
import 'platform_admin_cache.dart';
import 'role_route_access.dart';
import 'user_church_index_cache.dart';

/// Global redirect: `/` landing, `/sign-in` for returning users, incomplete registration → `/join`,
/// role-based access (build doc §6).
FutureOr<String?> appRouterRedirect(BuildContext context, GoRouterState state) async {
  final loc = state.matchedLocation;
  final auth = FirebaseAuth.instance.currentUser;

  if (auth == null) {
    UserChurchIndexCache.clear();
    ChurchTenantGateCache.clear();
    PlatformAdminCache.clear();
  }

  if (auth == null) {
    if (loc == '/' ||
        loc.startsWith('/join') ||
        loc.startsWith('/bootstrap-join') ||
        loc == '/sign-in') {
      return null;
    }
    return '/';
  }

  final isPlatform = await PlatformAdminCache.isPlatformAdmin(auth.uid);

  final idx = await UserChurchIndexCache.getOrFetch(auth.uid);
  if (idx == null) {
    if (loc.startsWith('/join') || loc.startsWith('/bootstrap-join')) return null;
    if (isPlatform && loc.startsWith('/platform')) return null;
    if (isPlatform && (loc == '/' || loc == '/sign-in' || loc == '/login')) {
      return '/platform/churches';
    }
    return '/join';
  }

  final gate = await ChurchTenantGateCache.getOrFetch(uid: auth.uid, churchId: idx.churchId);
  if (!gate.isActive) {
    if (isPlatform && loc.startsWith('/platform')) return null;
    if (loc.startsWith('/workspace-suspended')) return null;
    return '/workspace-suspended';
  }

  final needsOnboarding =
      (idx.role == 'admin' || idx.role == 'pastor') && !gate.setupComplete;
  if (needsOnboarding) {
    if (isPlatform && loc.startsWith('/platform')) return null;
    if (loc.startsWith('/onboarding')) return null;
    return '/onboarding';
  }

  if (loc.startsWith('/platform') && !isPlatform) {
    return '/overview';
  }

  if (loc == '/' || loc == '/sign-in' || loc == '/login') {
    final last = await LastRouteStorage.load(auth.uid);
    if (last != null && !isPathForbiddenForRole(last, idx.role)) {
      return last;
    }
    return '/overview';
  }

  if (isPlatform && loc.startsWith('/platform')) {
    return null;
  }

  if (isPathForbiddenForRole(loc, idx.role)) {
    return '/overview';
  }

  return null;
}
