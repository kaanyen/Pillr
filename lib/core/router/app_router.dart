import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_router_redirect.dart';
import '../../features/arms/presentation/arms_screen.dart';
import '../../features/auth/presentation/join_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/dashboard/presentation/role_dashboard_screen.dart';
import '../../features/entries/presentation/entries_list_screen.dart';
import '../../features/entries/presentation/entry_detail_placeholder_screen.dart';
import '../../features/entries/presentation/entry_form_placeholder_screen.dart';
import '../../features/goals/presentation/goals_screen.dart';
import '../../features/leaderboard/presentation/leaderboard_screen.dart';
import '../../features/logs/presentation/activity_logs_screen.dart';
import '../../features/partners/presentation/partner_profile_placeholder_screen.dart';
import '../../features/partners/presentation/partners_list_screen.dart';
import '../../features/periods/presentation/periods_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/users/presentation/invitations_screen.dart';
import '../../features/users/presentation/users_list_screen.dart';
import '../../common/layout/app_shell.dart';
import 'route_guards.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

GoRouter createRouter() {
  final refresh = GoRouterRefreshStream(FirebaseAuth.instance.authStateChanges());

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: appRouterRedirect,
    routes: [
      GoRoute(
        path: '/login',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => const NoTransitionPage(child: LoginScreen()),
      ),
      GoRoute(
        path: '/join',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final code = state.uri.queryParameters['code'];
          return NoTransitionPage(child: JoinScreen(prefilledCode: code));
        },
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: RoleDashboardScreen()),
          ),
          GoRoute(
            path: '/entries',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: EntriesListScreen()),
          ),
          GoRoute(
            path: '/entries/new',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: EntryFormPlaceholderScreen()),
          ),
          GoRoute(
            path: '/entries/:id',
            pageBuilder: (context, state) {
              final id = state.pathParameters['id']!;
              return NoTransitionPage(child: EntryDetailPlaceholderScreen(entryId: id));
            },
          ),
          GoRoute(
            path: '/partners/:id',
            pageBuilder: (context, state) {
              final id = state.pathParameters['id']!;
              return NoTransitionPage(child: PartnerProfilePlaceholderScreen(partnerId: id));
            },
          ),
          GoRoute(
            path: '/partners',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: PartnersListScreen()),
          ),
          GoRoute(
            path: '/leaderboard',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: LeaderboardScreen()),
          ),
          GoRoute(
            path: '/goals',
            pageBuilder: (context, state) => const NoTransitionPage(child: GoalsScreen()),
          ),
          GoRoute(
            path: '/arms',
            pageBuilder: (context, state) => const NoTransitionPage(child: ArmsScreen()),
          ),
          GoRoute(
            path: '/periods',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: PeriodsScreen()),
          ),
          GoRoute(
            path: '/users',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: UsersListScreen()),
          ),
          GoRoute(
            path: '/invitations',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: InvitationsScreen()),
          ),
          GoRoute(
            path: '/logs',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ActivityLogsScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SettingsScreen()),
          ),
        ],
      ),
    ],
  );
}

/// Single app router instance (GoRouter is not const-safe to rebuild).
final GoRouter appRouter = createRouter();
