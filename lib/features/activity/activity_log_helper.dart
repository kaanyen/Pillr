import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/extensions/async_value_ext.dart';
import '../auth/providers/auth_providers.dart';
import 'providers/activity_log_providers.dart';

Future<void> logPillrActivity(
  WidgetRef ref, {
  required String churchId,
  required String action,
  required String entityType,
  String? entityId,
  Map<String, dynamic>? entitySnapshot,
  Map<String, dynamic>? metadata,
}) async {
  final user = ref.read(authStateProvider).valueOrNull;
  if (user == null) return;
  final profile = ref.read(churchUserProfileProvider).valueOrNull;
  final idx = ref.read(userChurchIndexProvider).valueOrNull;
  await ref.read(activityLogRepositoryProvider).log(
        churchId: churchId,
        actorUid: user.uid,
        actorSnapshot: {
          'fullName': (profile?.fullName.trim().isNotEmpty ?? false)
              ? profile!.fullName
              : (user.email ?? user.uid),
          'role': profile?.role ?? idx?.role ?? '',
          'email': profile?.email ?? user.email,
        },
        action: action,
        entityType: entityType,
        entityId: entityId,
        entitySnapshot: entitySnapshot,
        metadata: metadata,
      );
}
