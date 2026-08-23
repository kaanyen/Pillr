import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/utils/date_utils.dart';
import '../design/seline.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/dashboard/providers/admin_dashboard_providers.dart';
import '../features/users/providers/users_providers.dart';

/// People — Users and Invitations, merged.
///
/// These were two screens describing the same thing at two moments: someone
/// who is in the church, and someone on their way in. Splitting them meant
/// "did I already invite this person?" required checking a different page.
/// Now both lists live here, members first, invitations beneath.
class PeopleScreen extends ConsumerWidget {
  const PeopleScreen({super.key, this.initialSection});

  /// Lets `/invitations` land here and scroll to the right block.
  final String? initialSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final users = ref.watch(churchUsersProvider);
    final invites = ref.watch(invitesListForAdminProvider);
    final canManage = (idx?.isAdmin ?? false) || (idx?.isPastor ?? false);

    return SelPageBody(
      onRefresh: () async {
        ref.invalidate(churchUsersProvider);
        ref.invalidate(invitesListForAdminProvider);
      },
      children: [
        SelPageTitle(
          title: 'People',
          subtitle: 'Everyone in your workspace, and everyone on the way in.',
          actions: [
            if (canManage)
              SelButton.cyan(
                label: 'Invite someone',
                icon: LucideIcons.plus,
                onPressed: () => _inviteDialog(context, ref, idx!.churchId),
              ),
          ],
        ),

        SelSectionLabel(
          label: 'Members',
          trailing: Text(
            '${(users.valueOrNull ?? []).length}',
            style: SelType.bodyMuted,
          ),
        ),
        users.when(
          loading: () => const SelCard(child: SelSkeletonRows(count: 3)),
          error: (e, _) => SelError(message: '$e'),
          data: (list) => SelLedger(
            minWidth: 700,
            columns: const [
              SelColumn('Name', flex: 2),
              SelColumn('Email', flex: 2),
              SelColumn('Role', fit: SelColFit.fixed, width: 110),
              SelColumn('Last active', fit: SelColFit.fixed, width: 130),
              SelColumn('Status', fit: SelColFit.fixed, width: 110),
            ],
            emptyState: const SelEmpty(
              title: 'No members yet',
              message: 'Invite your team to get started.',
              icon: LucideIcons.users,
            ),
            rows: [
              for (final u in list)
                SelRow(
                  cells: [
                    SelCell.primary(u.fullName),
                    SelCell.secondary(u.email),
                    if (canManage && u.uid != idx?.uid)
                      _RoleSelect(user: u, churchId: idx!.churchId)
                    else
                      SelCell.secondary(_role(u.role)),
                    SelCell.secondary(
                      u.lastLoginAt == null
                          ? '—'
                          : formatFirestoreDate(u.lastLoginAt!, pattern: 'd MMM'),
                    ),
                    SelStatusMark(
                      status: u.isActive ? SelStatus.active : SelStatus.inactive,
                      label: u.isActive ? 'Active' : 'Inactive',
                    ),
                  ],
                ),
            ],
          ),
        ),

        const SelSectionGap(factor: 0.5),

        SelSectionLabel(
          label: 'Invitations',
          trailing: Text(
            '${ref.watch(pendingInvitesCountProvider)} pending',
            style: SelType.bodyMuted,
          ),
        ),
        invites.when(
          loading: () => const SelCard(child: SelSkeletonRows(count: 2)),
          error: (e, _) => SelError(message: '$e'),
          data: (list) => SelLedger(
            minWidth: 640,
            columns: const [
              SelColumn('Email', flex: 3),
              SelColumn('Role', fit: SelColFit.fixed, width: 110),
              SelColumn('Expires', fit: SelColFit.fixed, width: 130),
              SelColumn('Status', fit: SelColFit.fixed, width: 130),
            ],
            emptyState: const SelEmpty(
              title: 'No invitations',
              message: 'Invite a teammate and their code will appear here.',
              icon: LucideIcons.mail,
            ),
            rows: [
              for (final i in list)
                SelRow(
                  cells: [
                    SelCell.primary(i.email),
                    SelCell.secondary(_role(i.role)),
                    SelCell.secondary(
                      formatFirestoreDate(i.expiresAt, pattern: 'd MMM, HH:mm'),
                    ),
                    SelStatusMark.fromString(
                      status: i.status,
                      label: _inviteStatus(i.status),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _role(String r) => r.isEmpty ? '—' : r[0].toUpperCase() + r.substring(1);

  String _inviteStatus(String s) => switch (s) {
        'accepted' => 'Accepted',
        'expired' => 'Expired',
        _ => 'Pending',
      };
}

/// Inline role change. A select rather than a dialog — changing someone's role
/// is a two-second decision and should not cost a modal.
class _RoleSelect extends ConsumerWidget {
  const _RoleSelect({required this.user, required this.churchId});

  final dynamic user;
  final String churchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SelSelect<String>(
      value: user.role as String,
      expanded: false,
      onChanged: (v) async {
        if (v == null || v == user.role) return;
        final ok = await selConfirm(
          context,
          title: 'Change role to $v?',
          message:
              '${user.fullName} will immediately gain the permissions of the '
              '$v role and lose any the current one had.',
          confirmLabel: 'Change role',
        );
        if (!ok) return;
        await ref.read(usersRepositoryProvider).updateMember(
              churchId: churchId,
              targetUid: user.uid as String,
              role: v,
            );
      },
      items: const [
        DropdownMenuItem(value: 'admin', child: Text('Admin')),
        DropdownMenuItem(value: 'pastor', child: Text('Pastor')),
        DropdownMenuItem(value: 'staff', child: Text('Staff')),
      ],
    );
  }
}

Future<void> _inviteDialog(
  BuildContext context,
  WidgetRef ref,
  String churchId,
) async {
  final email = TextEditingController();
  var role = 'staff';

  final send = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => SelDialog(
        title: 'Invite someone',
        subtitle: 'They get a code by email that expires in four hours.',
        width: 460,
        scrollable: false,
        actions: [
          SelButton(
            label: 'Cancel',
            kind: SelButtonKind.quiet,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          SelButton.cyan(
            label: 'Send invite',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SelField(
              controller: email,
              label: 'Email address',
              hint: 'name@church.org',
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
            ),
            const SizedBox(height: SelSpace.x4),
            SelSelect<String>(
              value: role,
              label: 'Role',
              onChanged: (v) => setState(() => role = v ?? 'staff'),
              items: const [
                DropdownMenuItem(value: 'pastor', child: Text('Pastor')),
                DropdownMenuItem(value: 'staff', child: Text('Staff')),
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  if (send != true || email.text.trim().isEmpty) return;
  await ref.read(inviteRepositoryProvider).sendInvite(
        churchId: churchId,
        email: email.text,
        role: role,
      );
}
