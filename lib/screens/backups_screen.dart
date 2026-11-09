import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../core/constants/firebase_constants.dart';
import '../core/notifications/sel_notice.dart';
import '../design/seline.dart';
import '../features/auth/providers/auth_providers.dart';
import '../core/errors/plain_error.dart';

/// One backup of the whole database.
class BackupRow {
  BackupRow(Map<String, dynamic> m)
    : id = m['id'] as String? ?? '',
      manual = m['kind'] == 'manual',
      state = m['state'] as String? ?? 'PROCESSING',
      startedAt = _date(m['startedAt']),
      completedAt = _date(m['completedAt']),
      documents = (m['documents'] as num?)?.toInt(),
      byName = m['byName'] as String?,
      error = m['error'] as String?;

  final String id;
  final bool manual;
  final String state;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int? documents;
  final String? byName;
  final String? error;

  bool get running => state == 'PROCESSING';
  bool get ok => state == 'SUCCESSFUL';

  static DateTime? _date(Object? ms) =>
      ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()) : null;
}

final backupsProvider = FutureProvider.autoDispose<({int keepDays, List<BackupRow> rows})>((ref) async {
  final r = await ref
      .watch(firebaseFunctionsProvider)
      .httpsCallable(FirebaseConstants.listBackups)
      .call(<String, dynamic>{});
  final d = Map<String, dynamic>.from(r.data as Map);
  return (
    keepDays: (d['keepDays'] as num?)?.toInt() ?? 365,
    rows: [
      for (final b in (d['backups'] as List? ?? const [])) BackupRow(Map<String, dynamic>.from(b as Map)),
    ],
  );
});

/// Backups, as on the canvas (board 57): every copy of the database, weekly
/// and by hand, and a button to make one now. A backup is a copy; it never
/// changes anything, and putting one back is done by the platform, not here.
class BackupsScreen extends ConsumerStatefulWidget {
  const BackupsScreen({super.key});

  @override
  ConsumerState<BackupsScreen> createState() => _BackupsScreenState();
}

class _BackupsScreenState extends ConsumerState<BackupsScreen> {
  bool _busy = false;

  Future<void> _backUpNow() async {
    final ok = await selConfirm(
      context,
      title: 'Back up now?',
      message:
          'Pillr copies everything to safe storage. It takes a few minutes and changes nothing. '
          'You can do this once an hour.',
      confirmLabel: 'Back up now',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await ref.read(firebaseFunctionsProvider).httpsCallable(FirebaseConstants.startBackup).call(<String, dynamic>{});
      if (mounted) {
        selNotice(context, 'Backing up. It shows as finished here in a few minutes.');
        ref.invalidate(backupsProvider);
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) selNotice(context, plainError(e), kind: SelNoticeKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(backupsProvider);
    final count = NumberFormat('#,##0');
    String when(DateTime? d) => d == null ? '—' : DateFormat('EEE d MMM y, HH:mm').format(d);

    return SelPageBody(
      onRefresh: () async => ref.invalidate(backupsProvider),
      children: [
        SelPageTitle(
          title: 'Backups',
          subtitle: 'A full copy of Pillr every Sunday at 03:00, and whenever someone backs up by hand.',
          actions: [
            SelButton(label: 'Check again', onPressed: () => ref.invalidate(backupsProvider)),
            const SizedBox(width: SelSpace.x2),
            SelButton.cyan(
              label: 'Back up now',
              loading: _busy,
              onPressed: _busy ? null : _backUpNow,
            ),
          ],
        ),
        async.when(
          loading: () => const SelCard(child: SelSkeletonRows(count: 6)),
          error: (e, _) => SelError(message: plainError(e)),
          data: (data) {
            final rows = data.rows;
            final last = rows.where((r) => r.ok).firstOrNull;
            final running = rows.where((r) => r.running).firstOrNull;
            final failed = rows.where((r) => r.state == 'FAILED').length;
            final stale = last == null || DateTime.now().difference(last.startedAt ?? DateTime(2000)).inDays > 8;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                  decoration: BoxDecoration(
                    color: stale ? Sel.ink : Sel.skyTint,
                    borderRadius: BorderRadius.circular(SelRadius.card),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        running != null
                            ? 'A backup is running now'
                            : last == null
                            ? 'No backup has finished yet'
                            : 'Last backup ${when(last.completedAt ?? last.startedAt)}',
                        style: SelType.subtitle.copyWith(color: stale ? Sel.card : Sel.ink),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (last?.documents != null) '${count.format(last!.documents)} records copied',
                          'Each backup is kept for ${data.keepDays} days',
                          if (failed > 0) '$failed failed',
                          if (stale && running == null) 'More than a week since the last one: back up now',
                        ].join(' · '),
                        style: SelType.bodySm.copyWith(color: stale ? SelNavyCard.soft : Sel.ink),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: SelSpace.x4),
                SelCard(
                  padding: EdgeInsets.zero,
                  clip: true,
                  child: SelLedger(
                    bare: true,
                    minWidth: 720,
                    columns: const [
                      SelColumn('Started', flex: 3),
                      SelColumn('How', flex: 2),
                      SelColumn('Status', flex: 3),
                      SelColumn.numeric('Records', width: 120),
                    ],
                    emptyState: const SelEmpty(
                      title: 'No backups yet',
                      message: 'The first weekly backup runs on Sunday at 03:00, or back up now.',
                    ),
                    rows: [
                      for (final b in data.rows)
                        SelRow(
                          cells: [
                            SelCell.secondary(when(b.startedAt)),
                            SelCell.secondary(
                              b.manual ? 'By hand${(b.byName ?? '').isEmpty ? '' : ' · ${b.byName}'}' : 'Weekly',
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: switch (b.state) {
                                'SUCCESSFUL' => const SelTag('Finished'),
                                'PROCESSING' => const SelTag('Running', tone: SelTagTone.waiting),
                                'FAILED' => SelTag(
                                  'Failed${(b.error ?? '').isEmpty ? '' : ': ${b.error}'}',
                                  tone: SelTagTone.strong,
                                ),
                                _ => const SelTag('Not known'),
                              },
                            ),
                            SelCell.numeric(b.documents == null ? '—' : count.format(b.documents)),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: SelSpace.x3),
                Text(
                  'A backup is a copy of every church on Pillr. Making one changes nothing. '
                  'Putting one back is done by whoever runs the Pillr platform, on request.',
                  style: SelType.small,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
