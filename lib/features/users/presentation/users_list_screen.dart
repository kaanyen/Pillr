import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../common/widgets/pillr_badge.dart';
import '../../../common/widgets/pillr_data_table.dart';
import '../../../common/widgets/pillr_dropdown_field.dart';
import '../../../common/widgets/pillr_entity_card.dart';
import '../../../common/widgets/pillr_empty_state.dart';
import '../../../common/widgets/pillr_error_state.dart';
import '../../../common/widgets/pillr_loading_shimmer.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../../core/theme/pillr_layout.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/domain/church_user.dart';
import '../../auth/domain/user_church_index.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/users_providers.dart';

class UsersListScreen extends ConsumerWidget {
  const UsersListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final users = ref.watch(churchUsersProvider);

    if (idx == null || (!idx.isPastor && !idx.isAdmin)) {
      return const Center(child: Text('You do not have access to the user directory.'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Users', style: AppTypography.heading2),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Church members and roles. Role changes sync via Cloud Functions.',
            style: AppTypography.body,
          ),
          const SizedBox(height: AppSpacing.lg),
          users.when(
            loading: () => const PillrLoadingShimmer(height: 200),
            error: (e, _) => PillrErrorState(message: e.toString(), onRetry: () => ref.invalidate(churchUsersProvider)),
            data: (rows) {
              if (rows.isEmpty) {
                return const PillrEmptyState(
                  title: 'No users',
                  message: 'Invite people from Invitations.',
                );
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  final useCards = PillrLayout.useCardListLayout(constraints.maxWidth);
                  final table = PillrDataTable(
                    minWidth: 960,
                    columns: [
                      DataColumn2(label: Text('NAME', style: AppTypography.tableHeader), size: ColumnSize.L),
                      DataColumn2(label: Text('EMAIL', style: AppTypography.tableHeader)),
                      DataColumn2(label: Text('ROLE', style: AppTypography.tableHeader)),
                      DataColumn2(label: Text('LAST ACTIVE', style: AppTypography.tableHeader)),
                      DataColumn2(label: Text('STATUS', style: AppTypography.tableHeader)),
                      DataColumn2(label: Text('ACTIONS', style: AppTypography.tableHeader), fixedWidth: 200),
                    ],
                    rows: [
                      for (final u in rows)
                        DataRow(
                          cells: [
                            DataCell(Text(u.fullName, style: AppTypography.body.copyWith(fontWeight: FontWeight.w600))),
                            DataCell(Text(u.email, style: AppTypography.caption)),
                            DataCell(_RoleCell(idx: idx, user: u)),
                            DataCell(Text(
                              u.lastLoginAt != null
                                  ? DateFormat.yMMMd().add_jm().format(u.lastLoginAt!)
                                  : '—',
                              style: AppTypography.caption,
                            )),
                            DataCell(
                              u.isActive
                                  ? const PillrBadge(label: 'Active', kind: PillrBadgeKind.approved, compact: true)
                                  : const PillrBadge(label: 'Inactive', kind: PillrBadgeKind.inactive, compact: true),
                            ),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    onPressed: () => context.go('/entries'),
                                    child: const Text('Entries'),
                                  ),
                                  TextButton(
                                    onPressed: () => _toggleActive(context, ref, idx, u),
                                    child: Text(u.isActive ? 'Deactivate' : 'Activate'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  );
                  final cardList = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final u in rows)
                        PillrEntityCard(
                          title: u.fullName,
                          subtitle:
                              '${u.email} · ${u.lastLoginAt != null ? DateFormat.yMMMd().add_jm().format(u.lastLoginAt!) : '—'}',
                          trailing: u.isActive
                              ? const PillrBadge(label: 'Active', kind: PillrBadgeKind.approved, compact: true)
                              : const PillrBadge(label: 'Inactive', kind: PillrBadgeKind.inactive, compact: true),
                          footer: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: _RoleCell(idx: idx, user: u),
                                ),
                              ),
                              Wrap(
                                alignment: WrapAlignment.end,
                                spacing: AppSpacing.sm,
                                children: [
                                  TextButton(
                                    onPressed: () => context.go('/entries'),
                                    child: const Text('Entries'),
                                  ),
                                  TextButton(
                                    onPressed: () => _toggleActive(context, ref, idx, u),
                                    child: Text(u.isActive ? 'Deactivate' : 'Activate'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                  return useCards ? cardList : table;
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

Future<void> _toggleActive(
  BuildContext context,
  WidgetRef ref,
  UserChurchIndex idx,
  ChurchUser u,
) async {
  final repo = ref.read(usersRepositoryProvider);
  try {
    await repo.updateMember(
      churchId: idx.churchId,
      targetUid: u.uid,
      isActive: !u.isActive,
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

class _RoleCell extends ConsumerStatefulWidget {
  const _RoleCell({required this.idx, required this.user});

  final UserChurchIndex idx;
  final ChurchUser user;

  @override
  ConsumerState<_RoleCell> createState() => _RoleCellState();
}

class _RoleCellState extends ConsumerState<_RoleCell> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final idx = widget.idx;
    final u = widget.user;
    final selfUid = ref.watch(authStateProvider).valueOrNull?.uid;
    if (u.uid == selfUid) {
      return Text(u.role, style: AppTypography.body);
    }
    if (!idx.isPastor && !idx.isAdmin) {
      return Text(u.role, style: AppTypography.body);
    }

    final roles = <String>['staff', 'pastor'];
    if (idx.isAdmin) roles.add('admin');

    final role = u.role.trim().toLowerCase();
    // DropdownButton requires [value] to match exactly one item. Pastors cannot edit
    // admins — those rows must not use a value missing from [items].
    if (!roles.contains(role)) {
      return Text(u.role, style: AppTypography.body);
    }

    return SizedBox(
      width: 128,
      child: PillrDropdownButton<String>(
        value: role,
        isDense: true,
        isExpanded: true,
        onChanged: _busy
            ? null
            : (v) async {
                if (v == null) return;
                setState(() => _busy = true);
                try {
                  await ref.read(usersRepositoryProvider).updateMember(
                        churchId: idx.churchId,
                        targetUid: u.uid,
                        role: v,
                      );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                  }
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
        items: [for (final r in roles) DropdownMenuItem(value: r, child: Text(r))],
      ),
    );
  }
}
