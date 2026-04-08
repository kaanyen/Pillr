import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../common/widgets/pillr_button.dart';
import '../../../common/widgets/pillr_confirmation_dialog.dart';
import '../../../common/widgets/pillr_text_field.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_utils.dart';
import '../../../core/utils/date_utils.dart';
import '../../activity/activity_log_helper.dart';
import '../../auth/domain/church_user.dart';
import '../../auth/domain/user_church_index.dart';
import '../../auth/providers/auth_providers.dart';
import '../domain/partnership_entry.dart';
import '../providers/entries_providers.dart';

class EntryDetailScreen extends ConsumerWidget {
  const EntryDetailScreen({super.key, required this.entryId});

  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entryAsync = ref.watch(entryDetailProvider(entryId));
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final profile = ref.watch(churchUserProfileProvider).valueOrNull;

    return entryAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (entry) {
        if (entry == null) {
          return Center(
            child: TextButton(onPressed: () => context.go('/entries'), child: const Text('Back')),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('Entry', style: AppTypography.heading2),
                  const Spacer(),
                  if (_canEditEntry(idx, entry))
                    TextButton(
                      onPressed: () => context.go('/entries/${entry.id}/edit'),
                      child: Text(idx?.isStaff == true ? 'Edit & resubmit' : 'Edit'),
                    ),
                  TextButton(onPressed: () => context.go('/entries'), child: const Text('Close')),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _row('Partner', entry.partnerSnapshot['fullName']?.toString() ?? '—'),
              _row('Member ID', entry.partnerSnapshot['memberId']?.toString() ?? '—'),
              _row('Arm', entry.armSnapshot['name']?.toString() ?? '—'),
              _row('Period', entry.periodSnapshot['name']?.toString() ?? '—'),
              _row('Amount', formatCedis(entry.amountCedis)),
              _row('Date given', formatFirestoreDate(entry.dateGiven)),
              _row('Status', entry.status),
              if (entry.declineReason != null && entry.declineReason!.isNotEmpty)
                _row('Decline reason', entry.declineReason!),
              if (entry.notes != null && entry.notes!.isNotEmpty) _row('Notes', entry.notes!),
              if (entry.editHistory.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text('Edit history', style: AppTypography.heading3),
                const SizedBox(height: AppSpacing.sm),
                for (final h in entry.editHistory.reversed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: _editHistoryTile(h),
                  ),
              ],
              const SizedBox(height: AppSpacing.xl),
              if (idx != null && profile != null) _actions(context, ref, entry, idx, profile),
            ],
          ),
        );
      },
    );
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(k, style: AppTypography.caption)),
          Expanded(child: Text(v, style: AppTypography.body)),
        ],
      ),
    );
  }

  Widget _actions(
    BuildContext context,
    WidgetRef ref,
    PartnershipEntry entry,
    UserChurchIndex idx,
    ChurchUser profile,
  ) {
    final churchId = idx.churchId;
    final repo = ref.read(entriesRepositoryProvider);

    if (idx.isPastor && entry.status == 'pending') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PillrButton(
            label: 'Approve',
            variant: PillrButtonVariant.primary,
            onPressed: () async {
              await repo.approveEntry(churchId: churchId, entry: entry, pastor: profile);
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
              if (context.mounted) context.go('/approvals');
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          PillrButton(
            label: 'Decline',
            variant: PillrButtonVariant.danger,
            onPressed: () async {
              final reason = await _declineReasonDialog(context);
              if (reason == null || !context.mounted) return;
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
              if (context.mounted) context.go('/approvals');
            },
          ),
        ],
      );
    }

    if (idx.isStaff && entry.createdBy == idx.uid && (entry.status == 'pending' || entry.status == 'declined')) {
      return PillrButton(
        label: 'Delete pending entry',
        variant: PillrButtonVariant.danger,
        onPressed: () async {
          final ok = await showPillrConfirmationDialog(
            context: context,
            title: 'Delete entry?',
            message: 'This cannot be undone.',
          );
          if (ok != true || !context.mounted) return;
          await repo.deleteEntry(churchId: churchId, entryId: entry.id);
          if (context.mounted) context.go('/entries');
        },
      );
    }

    return const SizedBox.shrink();
  }
}

bool _canEditEntry(UserChurchIndex? idx, PartnershipEntry entry) {
  if (idx == null) return false;
  if (idx.isPastor) return true;
  return idx.isStaff &&
      entry.createdBy == idx.uid &&
      (entry.status == 'pending' || entry.status == 'declined');
}

Widget _editHistoryTile(Map<String, dynamic> h) {
  final desc = h['changeDescription']?.toString() ?? 'Edit';
  final ts = h['editedAt'];
  final when = ts is Timestamp
      ? formatFirestoreDate(ts.toDate(), pattern: 'MMM d, y · h:mm a')
      : '—';
  final prev = h['previousValues'];
  var detail = '';
  if (prev is Map) {
    detail = prev.entries.map((e) => '${e.key}: ${e.value}').join('; ');
  }
  return DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.gray200),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(when, style: AppTypography.caption.copyWith(color: AppColors.gray600)),
          const SizedBox(height: 4),
          Text(desc, style: AppTypography.body),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(detail, style: AppTypography.caption),
          ],
        ],
      ),
    ),
  );
}

Future<String?> _declineReasonDialog(BuildContext context) async {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Decline reason', style: AppTypography.heading3),
      content: PillrTextField(
        controller: c,
        label: 'Reason (required)',
        maxLines: 3,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            if (c.text.trim().isEmpty) return;
            Navigator.pop(ctx, c.text.trim());
          },
          child: const Text('Decline'),
        ),
      ],
    ),
  );
}
