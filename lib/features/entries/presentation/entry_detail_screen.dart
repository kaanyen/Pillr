import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../common/widgets/pillr_badge.dart';
import '../../../common/widgets/pillr_button.dart';
import '../../../common/widgets/pillr_confirmation_dialog.dart';
import '../../../common/widgets/pillr_text_field.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
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
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text('Entry', style: AppTypography.heading2),
                      const Spacer(),
                      if (_canEditEntry(idx, entry))
                        TextButton.icon(
                          icon: const Icon(LucideIcons.pencil, size: 18),
                          onPressed: () => context.go('/entries/${entry.id}/edit'),
                          label: Text(idx?.isStaff == true ? 'Edit & resubmit' : 'Edit'),
                        ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(LucideIcons.x, size: 22),
                        onPressed: () => context.go('/entries'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _EntryReceiptCard(entry: entry)
                      .animate()
                      .fade(duration: 400.ms)
                      .slideY(begin: 0.05, curve: Curves.easeOutCubic),
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
            ),
          ),
        );
      },
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
            icon: LucideIcons.checkCircle,
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
            icon: LucideIcons.xCircle,
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
        icon: LucideIcons.trash2,
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

class _EntryReceiptCard extends StatelessWidget {
  const _EntryReceiptCard({required this.entry});

  final PartnershipEntry entry;

  String get _headline {
    switch (entry.status) {
      case 'approved':
        return 'Entry recorded';
      case 'declined':
        return 'Entry declined';
      default:
        return 'Pending review';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.gray200),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 8),
              child: Column(
                children: [
                  _ReceiptStatusIcon(status: entry.status),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _headline,
                    textAlign: TextAlign.center,
                    style: AppTypography.heading2.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Reference · ${entry.id}',
                    textAlign: TextAlign.center,
                    style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const _ReceiptDashedDivider(),
            _ReceiptBlock(
              title: 'Entry details',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ReceiptKvRow(label: 'Amount', value: formatCedis(entry.amountCedis)),
                  _ReceiptKvRow(label: 'Date given', value: formatFirestoreDate(entry.dateGiven)),
                  _ReceiptKvRow(
                    label: 'Partnership arm',
                    value: entry.armSnapshot['name']?.toString() ?? '—',
                  ),
                  _ReceiptKvRow(
                    label: 'Period',
                    value: entry.periodSnapshot['name']?.toString() ?? '—',
                  ),
                ],
              ),
            ),
            const _ReceiptDashedDivider(),
            _ReceiptBlock(
              title: 'Partner',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ReceiptKvRow(
                    label: 'Name',
                    value: entry.partnerSnapshot['fullName']?.toString() ?? '—',
                  ),
                  _ReceiptKvRow(
                    label: 'Member ID',
                    value: entry.partnerSnapshot['memberId']?.toString() ?? '—',
                  ),
                ],
              ),
            ),
            if (entry.declineReason != null && entry.declineReason!.isNotEmpty) ...[
              const _ReceiptDashedDivider(),
              _ReceiptBlock(
                title: 'Review',
                child: _ReceiptKvRow(label: 'Decline reason', value: entry.declineReason!),
              ),
            ],
            if (entry.notes != null && entry.notes!.isNotEmpty) ...[
              const _ReceiptDashedDivider(),
              _ReceiptBlock(
                title: 'Notes',
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(entry.notes!, style: AppTypography.body),
                ),
              ),
            ],
            const _ReceiptDashedDivider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Status:',
                    style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  PillrBadge(
                    label: entry.status.isEmpty
                        ? '—'
                        : '${entry.status[0].toUpperCase()}${entry.status.substring(1)}',
                    kind: switch (entry.status) {
                      'approved' => PillrBadgeKind.approved,
                      'declined' => PillrBadgeKind.declined,
                      _ => PillrBadgeKind.pending,
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
    );
  }
}

class _ReceiptStatusIcon extends StatelessWidget {
  const _ReceiptStatusIcon({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (status) {
      'approved' => (
          AppColors.successLight,
          AppColors.successColor,
          LucideIcons.check,
        ),
      'declined' => (
          AppColors.dangerLight,
          AppColors.dangerColor,
          LucideIcons.x,
        ),
      _ => (
          AppColors.warningLight,
          AppColors.warningColor,
          LucideIcons.clock,
        ),
    };
    return Center(
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.gray200),
          boxShadow: const [
            BoxShadow(color: Color(0x0A000000), blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: Icon(icon, color: fg, size: 32),
      ),
    );
  }
}

class _ReceiptBlock extends StatelessWidget {
  const _ReceiptBlock({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: AppTypography.body.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.gray900,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class _ReceiptKvRow extends StatelessWidget {
  const _ReceiptKvRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              '$label:',
              style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppTypography.body.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.gray900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptDashedDivider extends StatelessWidget {
  const _ReceiptDashedDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
      child: LayoutBuilder(
        builder: (context, c) {
          return CustomPaint(
            size: Size(c.maxWidth, 1),
            painter: _ReceiptDashesPainter(),
          );
        },
      ),
    );
  }
}

class _ReceiptDashesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const dash = 5.0;
    const gap = 4.0;
    final paint = Paint()
      ..color = AppColors.gray200
      ..strokeWidth = 1;
    var x = 0.0;
    while (x < size.width) {
      final end = (x + dash).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, 0.5), Offset(end, 0.5), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
