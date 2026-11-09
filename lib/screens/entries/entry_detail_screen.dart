import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/extensions/async_value_ext.dart';
import '../../core/notifications/sel_notice.dart';
import '../../core/utils/date_utils.dart';
import '../../design/seline.dart';
import '../pdf_actions.dart';
import '../../features/activity/activity_log_helper.dart';
import '../../features/arms/providers/arms_providers.dart';
import '../../features/auth/domain/church_user.dart';
import '../../features/auth/domain/user_church_index.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/church/providers/church_settings_providers.dart';
import '../../features/entries/domain/partnership_entry.dart';
import '../../features/entries/providers/entries_providers.dart';
import '../../features/leaderboard/giving_view.dart';
import '../../core/errors/plain_error.dart';

bool _canEdit(UserChurchIndex? idx, PartnershipEntry e) {
  if (idx == null) return false;
  if (idx.isPastor) return true;
  return idx.isStaff &&
      e.createdBy == idx.uid &&
      (e.status == 'pending' || e.status == 'declined' || e.status == 'approved');
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
        children: [
          if (e is FirebaseException && e.code == 'permission-denied')
            SelEmpty(
              title: "This entry isn't yours to open",
              message: 'Someone else recorded it. You can open the giving you recorded yourself.',
              actionLabel: 'Back to records',
              onAction: () => context.go('/records'),
            )
          else
            SelError(message: plainError(e)),
        ],
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

        final partner = entry.partnerSnapshot['fullName']?.toString() ?? '—';
        final tree = ref.watch(armTreeProvider);
        final arm = tree.fullNameOf(entry.partnershipArmId) ??
            entry.armSnapshot['name']?.toString() ??
            '—';
        final waitingDays = DateTime.now().difference(entry.createdAt).inDays;
        final (tag, tagStatus) = switch (entry.status) {
          'approved' => ('Approved', SelStatus.approved),
          'declined' => ('Sent back', SelStatus.declined),
          'voided' => ('Voided', SelStatus.voided),
          _ => (
            waitingDays == 0
                ? 'Waiting since today'
                : 'Waiting $waitingDays ${waitingDays == 1 ? 'day' : 'days'}',
            SelStatus.pending,
          ),
        };
        final full = money(entry.amountCedis);
        final dot = full.lastIndexOf('.');
        final whole = dot < 0 ? full : full.substring(0, dot);
        final cents = dot < 0 ? '' : full.substring(dot);
        final fromQueue = entry.status == 'pending';
        final view = ref.watch(givingViewProvider);
        final mine = view.partners
            .where((p) => p.partnerId == entry.partnerId)
            .firstOrNull;
        final waitingForPartner =
            (ref.watch(pendingEntriesProvider).valueOrNull ?? const [])
                .where((e) => e.partnerId == entry.partnerId)
                .fold<double>(0, (s, e) => s + e.amountCedis);
        final first = partner.split(' ').first;

        final record = SelCard(
          padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelStatusTag(status: tagStatus, label: tag),
                  const Spacer(),
                  if (_canEdit(idx, entry))
                    SelButton(
                      label: idx?.isStaff == true ? 'Edit and resubmit' : 'Edit',
                      kind: SelButtonKind.quiet,
                      dense: true,
                      onPressed: () => context.go('/entries/${entry.id}/edit'),
                    ),
                ],
              ),
              const SizedBox(height: SelSpace.x2),
              Text.rich(
                TextSpan(
                  text: whole,
                  style: SelType.hero.copyWith(
                    fontSize: 46,
                    height: 1.1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  children: [
                    TextSpan(
                      text: cents,
                      style: SelType.subtitle.copyWith(
                        fontSize: 26,
                        color: Sel.warm,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: SelSpace.x1),
              Row(
                children: [
                  Text('$arm · from ', style: SelType.lead),
                  Flexible(
                    child: InkWell(
                      onTap: () => context.go('/partners/${entry.partnerId}'),
                      child: Text(
                        partner,
                        style: SelType.lead.copyWith(
                          color: Sel.cyanEdge,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                          decorationColor: Sel.cyanEdge,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SelSpace.x4),
              _Row(
                'Member ID',
                entry.partnerSnapshot['memberId']?.toString() ?? '—',
                mono: true,
              ),
              _Row(
                'Fellowship',
                entry.partnerSnapshot['fellowship']?.toString() ?? '—',
              ),
              _Row(
                'Date given',
                formatFirestoreDate(entry.dateGiven, pattern: 'EEEE, d MMM y'),
              ),
              _Row('Period', entry.periodSnapshot['name']?.toString() ?? '—'),
              _Row(
                'Recorded by',
                '${entry.createdBySnapshot['fullName'] ?? '—'} · '
                    '${formatFirestoreDate(entry.createdAt, pattern: 'd MMM, HH:mm')}',
              ),
              if (entry.reviewedBySnapshot != null)
                _Row(
                  entry.status == 'declined' ? 'Sent back by' : 'Approved by',
                  entry.reviewedBySnapshot!['fullName']?.toString() ?? '—',
                ),
              if (entry.hasForeignSource)
                _Row(
                  'Recorded as',
                  '${entry.displaySourceAmount.toStringAsFixed(2)} '
                      '${entry.displaySourceCurrency} '
                      '@ ${entry.displayExchangeRate}',
                ),
              if (entry.notes != null && entry.notes!.isNotEmpty)
                _Row('Notes', entry.notes!),
              if (entry.declineReason != null &&
                  entry.declineReason!.isNotEmpty)
                _Row('Sent back because', entry.declineReason!),
              if (idx != null && profile != null) ...[
                const SizedBox(height: SelSpace.x6),
                _Actions(entry: entry, idx: idx, profile: profile),
                if (entry.status == 'approved') ...[
                  const SizedBox(height: SelSpace.x3),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelButton(
                      label: 'Receipt',
                      onPressed: () => shareEntryReceipt(context, ref, entry: entry),
                    ),
                  ),
                ],
              ],
            ],
          ),
        );

        final history = SelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Edit history', style: SelType.subtitle),
              const SizedBox(height: SelSpace.x4),
              _Step(
                title: 'Recorded',
                note:
                    '${entry.createdBySnapshot['fullName'] ?? '—'} · ${formatFirestoreDate(entry.createdAt, pattern: 'd MMM, HH:mm')}',
                last: entry.editHistory.isEmpty && entry.status != 'pending',
              ),
              for (var i = 0; i < entry.editHistory.length; i++)
                _Step(
                  title: entry.editHistory[i]['changeDescription']?.toString() ??
                      'Edited',
                  note: switch (timestampToDateTime(
                    entry.editHistory[i]['editedAt'],
                  )) {
                    final DateTime at => formatFirestoreDate(
                      at,
                      pattern: 'd MMM, HH:mm',
                    ),
                    _ => '',
                  },
                  last: i == entry.editHistory.length - 1 &&
                      entry.status != 'pending',
                ),
              if (entry.status == 'pending')
                _Step(
                  title: 'Waiting for a pastor',
                  note:
                      'Since ${formatFirestoreDate(entry.createdAt, pattern: 'd MMM')}',
                  last: true,
                ),
            ],
          ),
        );

        final giving = SelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text("$first's giving", style: SelType.subtitle),
              const SizedBox(height: SelSpace.x3),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Approved this period',
                      style: SelType.bodySm,
                    ),
                  ),
                  Text(money(mine?.total ?? 0), style: SelType.bodyMedium.copyWith(fontSize: 17)),
                ],
              ),
              const Divider(height: SelSpace.x6, color: Sel.rowLine),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      fromQueue ? 'Waiting, with this one' : 'Waiting',
                      style: SelType.bodySm,
                    ),
                  ),
                  Text(money(waitingForPartner), style: SelType.bodyMedium.copyWith(fontSize: 17)),
                ],
              ),
              const Divider(height: SelSpace.x6, color: Sel.rowLine),
              Align(
                alignment: Alignment.centerLeft,
                child: SelLink(
                  label: 'Open their record',
                  onTap: () => context.go('/partners/${entry.partnerId}'),
                ),
              ),
            ],
          ),
        );

        return SelPageBody(
          children: [
            SelBreadcrumb([
              (
                fromQueue ? 'Queue' : 'Records',
                () => context.go(fromQueue ? '/queue' : '/records'),
              ),
              (
                '$partner, ${formatFirestoreDate(entry.dateGiven, pattern: 'd MMM')}',
                null,
              ),
            ]),
            const SizedBox(height: SelSpace.x4),
            LayoutBuilder(
              builder: (context, c) => c.maxWidth < 980
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        record,
                        const SizedBox(height: SelSpace.x4),
                        history,
                        const SizedBox(height: SelSpace.x4),
                        giving,
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: record),
                        const SizedBox(width: SelSpace.x4),
                        SizedBox(
                          width: 300,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              history,
                              const SizedBox(height: SelSpace.x4),
                              giving,
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Sel.rowLine)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 160, child: Text(label, style: SelType.bodySm)),
          Expanded(
            child: Text(
              value,
              style: SelType.body.copyWith(
                color: Sel.text,
                fontWeight: mono ? FontWeight.w700 : FontWeight.w500,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One step on the history line: a sky dot joined to the next by a line.
class _Step extends StatelessWidget {
  const _Step({required this.title, required this.note, required this.last});

  final String title;
  final String note;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 5),
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Sel.sky,
                  shape: BoxShape.circle,
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(width: 2, color: Sel.skyWash),
                ),
            ],
          ),
          const SizedBox(width: SelSpace.x4),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : SelSpace.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: SelType.bodyMedium),
                  if (note.isNotEmpty) Text(note, style: SelType.small),
                ],
              ),
            ),
          ),
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

    if (idx.isPastor &&
        (entry.status == 'approved' || entry.status == 'declined')) {
      return Wrap(
        spacing: SelSpace.x2,
        runSpacing: SelSpace.x2,
        children: [
          SelButton(
            label: entry.status == 'approved'
                ? 'Undo approval'
                : 'Undo send-back',
            icon: LucideIcons.undo2,
            kind: SelButtonKind.quiet,
            onPressed: () async {
              final ok = await selConfirm(
                context,
                title: entry.status == 'approved'
                    ? 'Undo this approval?'
                    : 'Undo this send-back?',
                message: 'Puts the entry back on the queue as pending.',
                confirmLabel: 'Undo',
              );
              if (!ok || !context.mounted) return;
              final action = entry.status == 'approved'
                  ? 'entry.approve_undo'
                  : 'entry.decline_undo';
              await repo.reopenEntry(
                churchId: churchId,
                entry: entry,
                actor: profile,
              );
              await logPillrActivity(
                ref,
                churchId: churchId,
                action: action,
                entityType: 'entry',
                entityId: entry.id,
                entitySnapshot: {
                  'amountCedis': entry.amountCedis,
                  'partnerName': entry.partnerSnapshot['fullName'],
                },
              );
              invalidateEntryDerivedData(ref);
              if (context.mounted) context.go('/queue?filter=pending');
            },
          ),
          if (entry.status == 'approved')
            SelButton(
              label: 'Void this entry',
              icon: LucideIcons.ban,
              kind: SelButtonKind.quiet,
              onPressed: () async {
                final reason = await _reasonDialog(
                  context,
                  title: 'Void this entry?',
                  subtitle:
                      'It stays readable but counts toward nothing. You can '
                      'restore it later.',
                  confirmLabel: 'Void',
                  hint: 'Entered against the wrong partner',
                );
                if (reason == null || reason.trim().isEmpty || !context.mounted) {
                  return;
                }
                await repo.voidEntries(
                  churchId: churchId,
                  entries: [entry],
                  actor: profile,
                  reason: reason,
                );
                await logPillrActivity(
                  ref,
                  churchId: churchId,
                  action: 'entry.void',
                  entityType: 'entry',
                  entityId: entry.id,
                  entitySnapshot: {
                    'amountCedis': entry.amountCedis,
                    'reason': reason,
                  },
                );
                invalidateEntryDerivedData(ref);
                if (context.mounted) {
                  selNotice(
                    context,
                    'Entry voided. Restore it from this page if that was a mistake.',
                  );
                }
              },
            ),
        ],
      );
    }

    if ((idx.isPastor || idx.isAdmin) && entry.isVoided) {
      return Align(
        alignment: Alignment.centerLeft,
        child: SelButton(
          label: 'Restore this entry',
          icon: LucideIcons.rotateCcw,
          onPressed: () async {
            final ok = await selConfirm(
              context,
              title: 'Restore this entry?',
              message:
                  'Puts it back to the status it had before it was voided. '
                  'Approved giving returns to the totals.',
              confirmLabel: 'Restore',
            );
            if (!ok || !context.mounted) return;
            await repo.restoreEntries(
              churchId: churchId,
              entries: [entry],
              actor: profile,
            );
            await logPillrActivity(
              ref,
              churchId: churchId,
              action: 'entry.restore',
              entityType: 'entry',
              entityId: entry.id,
              entitySnapshot: {
                'amountCedis': entry.amountCedis,
                'partnerName': entry.partnerSnapshot['fullName'],
              },
            );
            invalidateEntryDerivedData(ref);
            if (context.mounted) {
              selNotice(context, 'Entry restored.', kind: SelNoticeKind.success);
            }
          },
        ),
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
              message:
                  'Pending and sent-back drafts can be deleted. This cannot '
                  'be undone — record it again if you still need it.',
              confirmLabel: 'Delete',
              destructive: true,
            );
            if (!ok || !context.mounted) return;
            await repo.deleteEntry(churchId: churchId, entryId: entry.id);
            await logPillrActivity(
              ref,
              churchId: churchId,
              action: 'entry.delete',
              entityType: 'entry',
              entityId: entry.id,
              entitySnapshot: {
                'amountCedis': entry.amountCedis,
                'status': entry.status,
                'partnerName': entry.partnerSnapshot['fullName'],
              },
            );
            if (context.mounted) context.go('/queue');
          },
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

Future<String?> _reasonDialog(
  BuildContext context, {
  String title = 'Send this entry back',
  String subtitle = 'Your note is shown to whoever submitted it.',
  String confirmLabel = 'Send back',
  String hint = 'Amount does not match the deposit slip',
}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => SelDialog(
      title: title,
      subtitle: subtitle,
      width: 460,
      scrollable: false,
      actions: [
        SelButton(
          label: 'Cancel',
          kind: SelButtonKind.quiet,
          onPressed: () => Navigator.of(context).pop(),
        ),
        SelButton.cyan(
          label: confirmLabel,
          onPressed: () => Navigator.of(context).pop(c.text),
        ),
      ],
      child: SelField(
        controller: c,
        label: 'Reason',
        hint: hint,
        maxLines: 3,
        autofocus: true,
      ),
    ),
  );
}
