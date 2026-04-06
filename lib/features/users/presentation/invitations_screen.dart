import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../common/layout/responsive_layout.dart';
import '../../../common/widgets/pillr_badge.dart';
import '../../../common/widgets/pillr_button.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../../common/widgets/pillr_data_table.dart';
import '../../../common/widgets/pillr_empty_state.dart';
import '../../../common/widgets/pillr_error_state.dart';
import '../../../common/widgets/pillr_loading_shimmer.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/domain/invite_models.dart';
import '../../auth/providers/auth_providers.dart';

final _invitesStreamProvider = StreamProvider.autoDispose<List<InviteRecord>>((ref) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null) return Stream.value([]);
  return ref.watch(inviteRepositoryProvider).watchInvites(idx.churchId);
});

class InvitationsScreen extends ConsumerWidget {
  const InvitationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invites = ref.watch(_invitesStreamProvider);
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final width = MediaQuery.sizeOf(context).width;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Invitations', style: AppTypography.heading2),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Invite teammates with expiring codes — emails are sent from Cloud Functions.',
                      style: AppTypography.body,
                    ),
                  ],
                ),
              ),
              PillrButton(
                label: '+ Send invite',
                icon: Icons.add,
                onPressed: idx == null ? null : () => _openSendDialog(context, ref, idx.churchId),
                variant: PillrButtonVariant.primary,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          invites.when(
            loading: () => const PillrLoadingShimmer(height: 200),
            error: (e, _) => PillrErrorState(
              message: e.toString(),
              onRetry: () => ref.invalidate(_invitesStreamProvider),
            ),
            data: (rows) {
              if (rows.isEmpty) {
                return PillrEmptyState(
                  title: 'No invitations yet',
                  message: 'Send an invite to onboard pastors, staff, or admins.',
                  actionLabel: 'Send invite',
                  onAction: idx == null ? null : () => _openSendDialog(context, ref, idx.churchId),
                );
              }
              final df = DateFormat.MMMd().add_jm();
              return PillrDataTable(
                minWidth: width > 800 ? width - AppSpacing.lg * 2 : 800,
                sortColumnIndex: 3,
                sortAscending: false,
                columns: [
                  DataColumn2(label: Text('EMAIL', style: AppTypography.tableHeader), size: ColumnSize.L),
                  DataColumn2(label: Text('ROLE', style: AppTypography.tableHeader)),
                  DataColumn2(label: Text('STATUS', style: AppTypography.tableHeader)),
                  DataColumn2(label: Text('EXPIRES', style: AppTypography.tableHeader)),
                  DataColumn2(label: Text('ACTIONS', style: AppTypography.tableHeader), fixedWidth: 120),
                ],
                rows: [
                  for (final r in rows)
                    DataRow(
                      cells: [
                        DataCell(
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(r.email, style: AppTypography.body.copyWith(
                                    color: AppColors.gray900,
                                    fontWeight: FontWeight.w600,
                                  )),
                              Text('Code ${r.code}', style: AppTypography.caption),
                            ],
                          ),
                        ),
                        DataCell(Text(r.role, style: AppTypography.body)),
                        DataCell(_statusBadge(r.status)),
                        DataCell(Text(df.format(r.expiresAt.toLocal()), style: AppTypography.body)),
                        DataCell(
                          r.status == 'pending'
                              ? TextButton(
                                  onPressed: () => _resend(context, ref, idx!.churchId, r),
                                  child: const Text('Resend'),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static Widget _statusBadge(String status) {
    final s = status.toLowerCase();
    if (s == 'accepted') {
      return const PillrBadge(label: 'Accepted', kind: PillrBadgeKind.approved, compact: true);
    }
    if (s == 'expired') {
      return const PillrBadge(label: 'Expired', kind: PillrBadgeKind.inactive, compact: true);
    }
    return const PillrBadge(label: 'Pending', kind: PillrBadgeKind.pending, compact: true);
  }

  Future<void> _openSendDialog(BuildContext context, WidgetRef ref, String churchId) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _SendInviteDialog(churchId: churchId),
    );
  }

  Future<void> _resend(
    BuildContext context,
    WidgetRef ref,
    String churchId,
    InviteRecord record,
  ) async {
    final repo = ref.read(inviteRepositoryProvider);
    try {
      await repo.deleteInvite(churchId: churchId, inviteId: record.id);
      await repo.sendInvite(churchId: churchId, email: record.email, role: record.role);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New invite sent.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }
}

class _SendInviteDialog extends ConsumerStatefulWidget {
  const _SendInviteDialog({required this.churchId});

  final String churchId;

  @override
  ConsumerState<_SendInviteDialog> createState() => _SendInviteDialogState();
}

class _SendInviteDialogState extends ConsumerState<_SendInviteDialog> {
  final _email = TextEditingController();
  String _role = 'staff';
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _error = null);
    if (_email.text.trim().isEmpty) {
      setState(() => _error = 'Email required');
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(inviteRepositoryProvider).sendInvite(
            churchId: widget.churchId,
            email: _email.text.trim(),
            role: _role,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Send invitation', style: AppTypography.heading3),
      content: SizedBox(
        width: breakpointFor(MediaQuery.sizeOf(context).width) == AppBreakpoint.mobile
            ? double.infinity
            : 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'staff', label: Text('Staff')),
                  ButtonSegment(value: 'pastor', label: Text('Pastor')),
                  ButtonSegment(value: 'admin', label: Text('Admin')),
                ],
                selected: {_role},
                onSelectionChanged: (s) => setState(() => _role = s.first),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: AppTypography.caption.copyWith(color: AppColors.dangerColor)),
            ],
          ],
        ),
      ),
      actions: [
        PillrButton(
          label: 'Cancel',
          variant: PillrButtonVariant.ghost,
          onPressed: _loading ? null : () => Navigator.pop(context),
        ),
        PillrButton(
          label: 'Send',
          loading: _loading,
          onPressed: _loading ? null : _send,
          variant: PillrButtonVariant.primary,
        ),
      ],
    );
  }
}
