import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/extensions/async_value_ext.dart';
import '../../core/utils/date_utils.dart';
import '../../design/seline.dart';
import '../../features/activity/activity_log_helper.dart';
import '../../features/auth/domain/church_user.dart';
import '../../features/auth/domain/user_church_index.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/church/providers/church_settings_providers.dart';
import '../../features/entries/domain/partnership_entry.dart';
import '../../features/entries/providers/entries_providers.dart';

bool _canEdit(UserChurchIndex? idx, PartnershipEntry e) {
  if (idx == null) return false;
  if (idx.isPastor) return true;
  return idx.isStaff &&
      e.createdBy == idx.uid &&
      (e.status == 'pending' || e.status == 'declined');
}

/// A single entry, as a record card.
///
/// The amount is the largest thing on the page at display weight 400 — the
/// figure is why anyone opened this screen. Everything else is a labelled
/// row beneath it, and the review actions sit at the bottom where a decision
/// belongs after the facts.
class EntryDetailScreen extends ConsumerWidget {
  const EntryDetailScreen({super.key, required this.entryId});

  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(churchMoneyFormatProvider);
    final entryAsync = ref.watch(entryDetailProvider(entryId));
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final profile = ref.watch(churchUserProfileProvider).valueOrNull;

    return entryAsync.when(
      loading: () => const SelPageBody(
        maxWidth: 640,
        children: [SelCard(child: SelSkeletonRows(count: 5))],
      ),
      error: (e, _) => SelPageBody(
        maxWidth: 640,
        children: [SelError(message: '$e')],
      ),
      data: (entry) {
        if (entry == null) {
          return SelPageBody(
            maxWidth: 640,
            children: [
              SelEmpty(
                title: 'Entry not found',
                message: 'It may have been deleted.',
                actionLabel: 'Back to queue',
                onAction: () => context.go('/queue'),
              ),
            ],
          );
        }

        final status = SelStatusStyle.parse(entry.status);
        final partner = entry.partnerSnapshot['fullName']?.toString() ?? '—';

        return SelPageBody(
          maxWidth: 640,
          children: [
            SelPageTitle(
              title: 'Entry',
              subtitle: partner,
              actions: [
                if (_canEdit(idx, entry))
                  SelButton(
                    label: idx?.isStaff == true ? 'Edit & resubmit' : 'Edit',
                    icon: LucideIcons.pencil,
                    onPressed: () => context.go('/entries/${entry.id}/edit'),
                  ),
                SelButton(
                  label: 'Close',
                  kind: SelButtonKind.quiet,
                  onPressed: () => context.go('/queue'),
                ),
              ],
            ),

            SelCard(
              lift: SelLift.floating,
              radius: SelRadius.feature,
              padding: const EdgeInsets.all(SelSpace.x8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          partner,
                          style: SelType.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SelStatusChip(
                        status: status,
                        label: entry.status[0].toUpperCase() +
                            entry.status.substring(1),
                      ),
                    ],
                  ),
                  const SizedBox(height: SelSpace.x6),
                  Text(
                    money(entry.amountCedis),
                    style: SelType.hero.copyWith(
                      fontSize: 44,
                      letterSpacing: -0.9,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: SelSpace.x8),
                  const Divider(height: 1, color: Sel.border),
                  const SizedBox(height: SelSpace.x6),
                  _Row('Arm', entry.armSnapshot['name']?.toString() ?? '—'),
                  _Row('Period', entry.periodSnapshot['name']?.toString() ?? '—'),
                  _Row(
                    'Member ID',
                    entry.partnerSnapshot['memberId']?.toString() ?? '—',
                  ),
                  _Row(
                    'Date given',
                    formatFirestoreDate(entry.dateGiven, pattern: 'd MMMM y'),
                  ),
                  _Row(
                    'Recorded by',
                    entry.createdBySnapshot['fullName']?.toString() ?? '—',
                  ),
                  _Row(
                    'Recorded on',
                    formatFirestoreDate(entry.createdAt, pattern: 'd MMM y, HH:mm'),
                  ),
                  if (entry.reviewedBySnapshot != null)
                    _Row(
                      'Reviewed by',
                      entry.reviewedBySnapshot!['fullName']?.toString() ?? '—',
                    ),
                  if (entry.notes != null && entry.notes!.isNotEmpty)
                    _Row('Notes', entry.notes!),
                  if (entry.declineReason != null &&
                      entry.declineReason!.isNotEmpty)
                    _Row('Sent back because', entry.declineReason!),
                ],
              ),
            ),

            if (entry.editHistory.isNotEmpty) ...[
              const SelSectionGap(factor: 0.4),
              SelPanel(
                title: 'Edit history',
                contentPadding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < entry.editHistory.length; i++) ...[
                      if (i > 0) const Divider(height: 1, color: Sel.border),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: SelSpace.cardPad,
                          vertical: SelSpace.x3,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                entry.editHistory.reversed
                                        .toList()[i]['editedByName']
                                        ?.toString() ??
                                    'Edited',
                                style: SelType.bodyMedium,
                              ),
                            ),
                            Text('edited', style: SelType.small),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            if (idx != null && profile != null) ...[
              const SelSectionGap(factor: 0.4),
              _Actions(entry: entry, idx: idx, profile: profile),
            ],
          ],
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SelSpace.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label.toUpperCase(), style: SelType.caption),
          ),
          Expanded(child: Text(value, style: SelType.body)),
        ],
      ),
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({
    required this.entry,
    required this.idx,
    required this.profile,
  });

  final PartnershipEntry entry;
  final UserChurchIndex idx;
  final ChurchUser profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(entriesRepositoryProvider);
    final churchId = idx.churchId;

    if (idx.isPastor && entry.status == 'pending') {
      return Row(
        children: [
          SelButton(
            label: 'Send back',
            onPressed: () async {
              final reason = await _reasonDialog(context);
              if (reason == null || reason.trim().isEmpty || !context.mounted) {
                return;
              }
              await repo.declineEntry(
                churchId: churchId,
                entry: entry,
                pastor: profile,
                reason: reason,
              );
              await logPillrActivity(
                ref,
                churchId: churchId,
                action: 'entry.decline',
                entityType: 'entry',
                entityId: entry.id,
                metadata: {
                  'before': {'status': entry.status},
                  'after': {'status': 'declined', 'declineReason': reason},
                  'entrySummary': {
                    'amountCedis': entry.amountCedis,
                    'partnerName': entry.partnerSnapshot['fullName'],
                    'memberId': entry.partnerSnapshot['memberId'],
                  },
                },
              );
              if (context.mounted) context.go('/queue?filter=pending');
            },
          ),
          const Spacer(),
          SelButton.cyan(
            label: 'Approve',
            icon: LucideIcons.check,
            onPressed: () async {
              await repo.approveEntry(
                churchId: churchId,
                entry: entry,
                pastor: profile,
              );
              await logPillrActivity(
                ref,
                churchId: churchId,
                action: 'entry.approve',
                entityType: 'entry',
                entityId: entry.id,
                metadata: {
                  'before': {'status': entry.status},
                  'after': {'status': 'approved'},
                  'entrySummary': {
                    'amountCedis': entry.amountCedis,
                    'partnerName': entry.partnerSnapshot['fullName'],
                    'memberId': entry.partnerSnapshot['memberId'],
                  },
                },
              );
              if (context.mounted) context.go('/queue?filter=pending');
            },
          ),
        ],
      );
    }

    if (idx.isStaff &&
        entry.createdBy == idx.uid &&
        (entry.status == 'pending' || entry.status == 'declined')) {
      return Align(
        alignment: Alignment.centerLeft,
        child: SelButton(
          label: 'Delete this entry',
          icon: LucideIcons.trash2,
          onPressed: () async {
            final ok = await selConfirm(
              context,
              title: 'Delete this entry?',
              message: 'This cannot be undone.',
              confirmLabel: 'Delete',
              destructive: true,
            );
            if (!ok || !context.mounted) return;
            await repo.deleteEntry(churchId: churchId, entryId: entry.id);
            if (context.mounted) context.go('/queue');
          },
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

Future<String?> _reasonDialog(BuildContext context) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => SelDialog(
      title: 'Send this entry back',
      subtitle: 'Your note is shown to whoever submitted it.',
      width: 460,
      scrollable: false,
      actions: [
        SelButton(
          label: 'Cancel',
          kind: SelButtonKind.quiet,
          onPressed: () => Navigator.of(context).pop(),
        ),
        SelButton.cyan(
          label: 'Send back',
          onPressed: () => Navigator.of(context).pop(c.text),
        ),
      ],
      child: SelField(
        controller: c,
        label: 'Reason',
        hint: 'Amount does not match the deposit slip',
        maxLines: 3,
        autofocus: true,
      ),
    ),
  );
}
