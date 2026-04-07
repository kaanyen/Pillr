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
}) async {
  final user = ref.read(authStateProvider).valueOrNull;
  final profile = ref.read(churchUserProfileProvider).valueOrNull;
  if (user == null || profile == null) return;
  await ref.read(activityLogRepositoryProvider).log(
        churchId: churchId,
        actorUid: user.uid,
        actorSnapshot: {
          'fullName': profile.fullName,
          'role': profile.role,
          'email': profile.email,
        },
        action: action,
        entityType: entityType,
        entityId: entityId,
        entitySnapshot: entitySnapshot,
      );
}
