import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../common/layout/responsive_layout.dart';
import '../../../common/widgets/pillr_badge.dart';
import '../../../common/widgets/pillr_button.dart';
import '../../../common/widgets/pillr_data_table.dart';
import '../../../common/widgets/pillr_segmented_control.dart';
import '../../../common/widgets/pillr_entity_card.dart';
import '../../../common/widgets/pillr_empty_state.dart';
import '../../../common/widgets/pillr_error_state.dart';
import '../../../common/widgets/pillr_loading_shimmer.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/pillr_layout.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/domain/invite_models.dart';
import '../../auth/providers/auth_providers.dart';

class InvitationsScreen extends ConsumerStatefulWidget {
  const InvitationsScreen({super.key});

  @override
  ConsumerState<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends ConsumerState<InvitationsScreen> {
  final List<InviteRecord> _items = [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  bool _scheduledInitial = false;

  void _ensureInitialLoad() {
    final i = ref.read(userChurchIndexProvider).valueOrNull;
    if (i == null || _scheduledInitial) return;
    _scheduledInitial = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadFirst();
    });
  }

  Future<void> _loadFirst() async {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref.read(inviteRepositoryProvider).fetchInvitesPage(
            idx.churchId,
            pageSize: 20,
          );
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _cursor = page.lastDoc;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await ref.read(inviteRepositoryProvider).fetchInvitesPage(
            idx.churchId,
            pageSize: 20,
            startAfter: _cursor,
          );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.lastDoc;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;

    ref.listen(userChurchIndexProvider, (prev, next) {
      final pc = prev?.valueOrNull?.churchId;
      final nc = next.valueOrNull?.churchId;
      if (pc != nc) {
        _items.clear();
        _cursor = null;
        _hasMore = true;
        _scheduledInitial = false;
        _ensureInitialLoad();
      }
    });

    if (idx != null) {
      _ensureInitialLoad();
    }

    final df = DateFormat.MMMd().add_jm();

    return RefreshIndicator(
      onRefresh: _loadFirst,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
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
                icon: LucideIcons.plus,
                onPressed: idx == null ? null : () => _openSendDialog(context, ref, idx.churchId),
                variant: PillrButtonVariant.primary,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (idx == null)
            const PillrLoadingShimmer(height: 200)
          else if (_loading)
            const PillrLoadingShimmer(height: 200)
          else if (_error != null)
            PillrErrorState(
              message: _error.toString(),
              onRetry: _loadFirst,
            )
          else if (_items.isEmpty)
            PillrEmptyState(
              title: 'No invitations yet',
              message: 'Send an invite to onboard pastors, staff, or admins.',
              actionLabel: 'Send invite',
              onAction: () => _openSendDialog(context, ref, idx.churchId),
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final useCards = PillrLayout.useCardListLayout(constraints.maxWidth);
                final table = PillrDataTable(
                  minWidth: 800,
                  sortColumnIndex: 3,
                  sortAscending: false,
                  columns: [
                    DataColumn2(
                      label: Text('EMAIL', style: AppTypography.tableHeader),
                      size: ColumnSize.L,
                    ),
                    DataColumn2(label: Text('ROLE', style: AppTypography.tableHeader)),
                    DataColumn2(label: Text('STATUS', style: AppTypography.tableHeader)),
                    DataColumn2(label: Text('EXPIRES', style: AppTypography.tableHeader)),
                    DataColumn2(
                      label: Text('ACTIONS', style: AppTypography.tableHeader),
                      fixedWidth: 120,
                    ),
                  ],
                  rows: [
                    for (final r in _items)
                      DataRow(
                        cells: [
                          DataCell(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  r.email,
                                  style: AppTypography.body.copyWith(
                                    color: AppColors.gray900,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text('Code ${r.code}', style: AppTypography.caption),
                              ],
                            ),
                          ),
                          DataCell(Text(r.role, style: AppTypography.body)),
                          DataCell(_statusBadge(r.status)),
                          DataCell(
                            Text(
                              df.format(r.expiresAt.toLocal()),
                              style: AppTypography.body,
                            ),
                          ),
                          DataCell(
                            r.status == 'pending'
                                ? TextButton(
                                    onPressed: () => _resend(context, ref, idx.churchId, r),
                                    child: const Text('Resend'),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                  ],
                );
                final cardList = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final r in _items)
                      PillrEntityCard(
                        title: r.email,
                        subtitle: 'Code ${r.code} · ${r.role} · Expires ${df.format(r.expiresAt.toLocal())}',
                        trailing: _statusBadge(r.status),
                        footer: r.status == 'pending'
                            ? Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => _resend(context, ref, idx.churchId, r),
                                  child: const Text('Resend'),
                                ),
                              )
                            : null,
                      ),
                  ],
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    useCards ? cardList : table,
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      '${_items.length} loaded${_hasMore ? ' · more available' : ''}',
                      style: AppTypography.caption,
                    ),
                    if (_hasMore) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Center(
                        child: PillrButton(
                          label: _loadingMore ? 'Loading…' : 'Load more',
                          onPressed: _loadingMore ? null : _loadMore,
                          variant: PillrButtonVariant.secondary,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ],
      ),
      ),
    );
  }

  static Widget _statusBadge(String status) {
    final s = status.toLowerCase();
    if (s == 'accepted') {
      return const PillrBadge(
        label: 'Accepted',
        kind: PillrBadgeKind.approved,
        compact: true,
      );
    }
    if (s == 'expired') {
      return const PillrBadge(
        label: 'Expired',
        kind: PillrBadgeKind.inactive,
        compact: true,
      );
    }
    return const PillrBadge(
      label: 'Pending',
      kind: PillrBadgeKind.pending,
      compact: true,
    );
  }

  Future<void> _openSendDialog(BuildContext context, WidgetRef ref, String churchId) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _SendInviteDialog(churchId: churchId),
    );
    await _loadFirst();
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
      await _loadFirst();
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
              child: PillrSegmentedControl<String>(
                segments: const [
                  PillrSegment(value: 'staff', label: 'Staff'),
                  PillrSegment(value: 'pastor', label: 'Pastor'),
                  PillrSegment(value: 'admin', label: 'Admin'),
                ],
                selected: _role,
                onChanged: (v) => setState(() => _role = v),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: AppTypography.caption.copyWith(color: AppColors.dangerColor),
              ),
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
