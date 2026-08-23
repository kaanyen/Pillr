import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/utils/date_utils.dart';
import '../core/utils/text_case_utils.dart';
import '../design/seline.dart';
import '../features/activity/providers/activity_log_providers.dart';
import '../features/auth/providers/auth_providers.dart';

/// Activity — the church's audit trail.
class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    if (idx == null) return const SizedBox.shrink();

    final logs = ref.watch(activityLogsFullProvider);

    return SelPageBody(
      onRefresh: () async => ref.invalidate(activityLogsFullProvider),
      children: [
        const SelPageTitle(
          title: 'Activity',
          subtitle: 'Who changed what, most recent first.',
        ),
        logs.when(
          loading: () => const SelCard(child: SelSkeletonRows(count: 8)),
          error: (e, _) => SelError(message: '$e'),
          data: (rows) => SelLedger(
            minWidth: 680,
            columns: const [
              SelColumn('Who', flex: 2),
              SelColumn('Did what', flex: 3),
              SelColumn('On', flex: 2),
              SelColumn('When', fit: SelColFit.fixed, width: 150),
            ],
            emptyState: const SelEmpty(
              title: 'Nothing logged yet',
              message: 'Actions your team takes will be recorded here.',
              icon: LucideIcons.history,
            ),
            rows: [
              for (final r in rows)
                SelRow(
                  cells: [
                    SelCell.stacked(
                      TextCaseUtils.toTitleCase(r.actorName),
                      r.actorRole,
                    ),
                    SelCell.secondary(
                      r.action.replaceAll('.', ' ').replaceAll('_', ' '),
                    ),
                    SelCell.secondary(r.entityType),
                    SelCell.secondary(
                      formatFirestoreDate(r.createdAt, pattern: 'd MMM, HH:mm'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Full log, distinct from the short dashboard preview.
final activityLogsFullProvider = StreamProvider.autoDispose((ref) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null) return Stream.value([]);
  return ref
      .watch(activityLogRepositoryProvider)
      .watchActivityLogs(idx.churchId, limit: 200);
});
