import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_router_redirect.dart';
import '../../features/arms/presentation/arms_screen.dart';
import '../../features/auth/presentation/join_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/dashboard/presentation/role_dashboard_screen.dart';
import '../../features/entries/bulk_import/bulk_import_screen.dart';
import '../../features/entries/presentation/entries_list_screen.dart';
import '../../features/entries/presentation/entry_detail_screen.dart';
import '../../features/entries/presentation/entry_created_success_screen.dart';
import '../../features/entries/presentation/entry_form_screen.dart';
import '../../features/entries/presentation/pending_approvals_screen.dart';
import '../../features/goals/presentation/goals_screen.dart';
import '../../features/help/presentation/help_screen.dart';
import '../../features/leaderboard/presentation/leaderboard_screen.dart';
import '../../features/logs/presentation/activity_logs_screen.dart';
import '../../features/partners/presentation/partner_profile_screen.dart';
import '../../features/partners/presentation/partners_list_screen.dart';
import '../../features/periods/presentation/periods_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/search/presentation/global_search_screen.dart';
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
            path: '/approvals',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: PendingApprovalsScreen()),
          ),
          GoRoute(
            path: '/entries/new',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: EntryFormScreen()),
          ),
          GoRoute(
            path: '/entries/bulk-import',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: BulkImportScreen()),
          ),
          GoRoute(
            path: '/entries/:id/edit',
            pageBuilder: (context, state) {
              final id = state.pathParameters['id']!;
              return NoTransitionPage(child: EntryFormScreen(entryId: id));
            },
          ),
          GoRoute(
            path: '/entries/success/:entryId',
            pageBuilder: (context, state) {
              final entryId = state.pathParameters['entryId']!;
              return NoTransitionPage(child: EntryCreatedSuccessScreen(entryId: entryId));
            },
          ),
          GoRoute(
            path: '/entries',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: EntriesListScreen()),
          ),
          GoRoute(
            path: '/entries/:id',
            pageBuilder: (context, state) {
              final id = state.pathParameters['id']!;
              return NoTransitionPage(child: EntryDetailScreen(entryId: id));
            },
          ),
          GoRoute(
            path: '/partners/:id',
            pageBuilder: (context, state) {
              final id = state.pathParameters['id']!;
              return NoTransitionPage(child: PartnerProfileScreen(partnerId: id));
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
          GoRoute(
            path: '/search',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: GlobalSearchScreen()),
          ),
          GoRoute(
            path: '/notifications',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: NotificationsScreen()),
          ),
          GoRoute(
            path: '/help',
            pageBuilder: (context, state) => const NoTransitionPage(child: HelpScreen()),
          ),
        ],
      ),
    ],
  );
}

/// Single app router instance (GoRouter is not const-safe to rebuild).
final GoRouter appRouter = createRouter();
