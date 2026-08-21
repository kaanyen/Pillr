import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_router_redirect.dart';
import '../../features/onboarding/presentation/onboarding_wizard_screen.dart';
import '../../features/platform/presentation/platform_churches_screen.dart';
import '../../features/entries/bulk_import/bulk_import_screen.dart';
import '../../features/entries/presentation/entry_detail_screen.dart';
import '../../features/entries/presentation/entry_created_success_screen.dart';
import '../../features/entries/presentation/entry_form_screen.dart';
import '../../features/partners/presentation/partner_profile_screen.dart';
import '../../shell/sel_shell.dart';
import '../../screens/activity_screen.dart';
import '../../screens/help_screen.dart';
import '../../screens/notifications_screen.dart';
import '../../screens/search_screen.dart';
import '../../screens/settings_screen.dart';
import '../../screens/auth/bootstrap_join_screen.dart';
import '../../screens/auth/join_screen.dart';
import '../../screens/auth/landing_screen.dart';
import '../../screens/auth/sign_in_screen.dart';
import '../../screens/auth/workspace_suspended_screen.dart';
import '../../screens/configuration_screen.dart';
import '../../screens/goals_screen.dart';
import '../../screens/overview_screen.dart';
import '../../screens/partners_screen.dart';
import '../../screens/people_screen.dart';
import '../../screens/queue_screen.dart';
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
        path: '/',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => const NoTransitionPage(child: LandingScreen()),
      ),
      GoRoute(
        path: '/login',
        parentNavigatorKey: rootNavigatorKey,
        redirect: (context, state) => '/sign-in',
      ),
      GoRoute(
        path: '/sign-in',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => const NoTransitionPage(child: SignInScreen()),
      ),
      GoRoute(
        path: '/join',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final code = state.uri.queryParameters['code'];
          return NoTransitionPage(child: JoinScreen(prefilledCode: code));
        },
      ),
      GoRoute(
        path: '/bootstrap-join',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final code = state.uri.queryParameters['code'];
          return NoTransitionPage(child: BootstrapJoinScreen(prefilledCode: code));
        },
      ),
      GoRoute(
        path: '/onboarding',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => const NoTransitionPage(child: OnboardingWizardScreen()),
      ),
      GoRoute(
        path: '/workspace-suspended',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => const NoTransitionPage(child: WorkspaceSuspendedScreen()),
      ),
      GoRoute(
        path: '/platform/churches',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => const NoTransitionPage(child: PlatformChurchesScreen()),
      ),
      ShellRoute(
        builder: (context, state, child) => SelShell(child: child),
        routes: [
          // ---- The seven destinations -------------------------------------
          GoRoute(
            path: '/overview',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: OverviewScreen()),
          ),
          GoRoute(
            path: '/queue',
            pageBuilder: (context, state) => NoTransitionPage(
              child: QueueScreen(
                initialFilter: state.uri.queryParameters['filter'],
              ),
            ),
          ),
          GoRoute(
            path: '/partners',
            pageBuilder: (context, state) => NoTransitionPage(
              child: PartnersScreen(
                initialView: state.uri.queryParameters['view'],
              ),
            ),
          ),
          GoRoute(
            path: '/partners/:id',
            pageBuilder: (context, state) {
              final id = state.pathParameters['id']!;
              return NoTransitionPage(child: PartnerProfileScreen(partnerId: id));
            },
          ),
          GoRoute(
            path: '/goals',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: GoalsScreen()),
          ),
          GoRoute(
            path: '/configuration',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ConfigurationScreen()),
          ),
          GoRoute(
            path: '/people',
            pageBuilder: (context, state) => NoTransitionPage(
              child: PeopleScreen(
                initialSection: state.uri.queryParameters['section'],
              ),
            ),
          ),
          GoRoute(
            path: '/activity',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ActivityScreen()),
          ),

          // ---- Entry flows -------------------------------------------------
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
              return NoTransitionPage(
                child: EntryCreatedSuccessScreen(entryId: entryId),
              );
            },
          ),
          GoRoute(
            path: '/entries/:id',
            pageBuilder: (context, state) {
              final id = state.pathParameters['id']!;
              return NoTransitionPage(child: EntryDetailScreen(entryId: id));
            },
          ),

          // ---- Utility -----------------------------------------------------
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SettingsScreen()),
          ),
          GoRoute(
            path: '/search',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SearchScreen()),
          ),
          GoRoute(
            path: '/notifications',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: NotificationsScreen()),
          ),
          GoRoute(
            path: '/help',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: HelpScreen()),
          ),

          // ---- Legacy paths ------------------------------------------------
          // The IA consolidated twelve destinations into seven. These keep old
          // bookmarks, push notification deep links and the route-persistence
          // cache working by landing on the merged screen, pre-filtered where
          // the old path implied a filter.
          GoRoute(path: '/dashboard', redirect: (_, _) => '/overview'),
          GoRoute(path: '/entries', redirect: (_, _) => '/queue'),
          GoRoute(path: '/approvals', redirect: (_, _) => '/queue?filter=pending'),
          GoRoute(path: '/leaderboard', redirect: (_, _) => '/partners?view=ranked'),
          GoRoute(path: '/arms', redirect: (_, _) => '/configuration'),
          GoRoute(path: '/periods', redirect: (_, _) => '/configuration'),
          GoRoute(path: '/users', redirect: (_, _) => '/people'),
          GoRoute(path: '/invitations', redirect: (_, _) => '/people?section=invites'),
          GoRoute(path: '/logs', redirect: (_, _) => '/activity'),
        ],
      ),
    ],
  );
}

/// Single app router instance (GoRouter is not const-safe to rebuild).
final GoRouter appRouter = createRouter();
