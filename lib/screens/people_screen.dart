import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/utils/date_utils.dart';
import '../core/notifications/sel_notice.dart';
import '../design/seline.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/dashboard/providers/admin_dashboard_providers.dart';
import '../features/users/providers/users_providers.dart';
import '../core/errors/plain_error.dart';

/// People — Users and Invitations, merged.
///
/// These were two screens describing the same thing at two moments: someone
/// who is in the church, and someone on their way in. Splitting them meant
/// "did I already invite this person?" required checking a different page.
/// Now both lists live here, members first, invitations beneath.
class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key, this.initialSection});

  /// Lets `/invitations` land here on the invitations tab.
  final String? initialSection;

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen> {
  late bool _invites = widget.initialSection == 'invites';

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final users = ref.watch(churchUsersProvider);
    final invites = ref.watch(invitesListForAdminProvider);
    final canManage = (idx?.isAdmin ?? false) || (idx?.isPastor ?? false);
    final church = ref.watch(churchNameProvider) ?? 'your church';
    final memberCount = (users.valueOrNull ?? const []).length;
    final inviteList = invites.valueOrNull ?? const [];

    final members = users.when(
      loading: () => const SelSkeletonRows(count: 3),
      error: (e, _) => SelError(message: plainError(e)),
      data: (list) => SelLedger(
        bare: true,
        minWidth: 640,
        rowExtent: kSelLedgerStackedRowExtent,
        columns: const [
          SelColumn('Person', flex: 3),
          SelColumn('Role', fit: SelColFit.fixed, width: 160),
          SelColumn('Last active', fit: SelColFit.fixed, width: 140),
          SelColumn.numeric('', width: 120),
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
                Row(
                  children: [
                    SelFace(u.fullName, size: 38),
                    const SizedBox(width: SelSpace.x3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text.rich(
                            TextSpan(
                              text: u.fullName,
                              style: SelType.body.copyWith(
                                color: Sel.text,
                                fontWeight: FontWeight.w600,
                              ),
                              children: [
                                if (u.uid == idx?.uid)
                                  TextSpan(text: ' (you)', style: SelType.bodySm),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(u.email, style: SelType.small, maxLines: 1),
                        ],
                      ),
                    ),
                  ],
                ),
                if (canManage && u.uid != idx?.uid && u.isActive)
                  _RoleSelect(user: u, churchId: idx!.churchId)
                else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _RoleTag(
                      role: _role(u.role),
                      inactive: !u.isActive,
                    ),
                  ),
                SelCell.secondary(lastActiveLabel(u.lastLoginAt)),
                const SizedBox.shrink(),
              ],
            ),
        ],
      ),
    );

    final inviteRows = invites.when(
      loading: () => const SelSkeletonRows(count: 2),
      error: (e, _) => SelError(message: plainError(e)),
      data: (list) => list.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: SelSpace.x8),
              child: SelEmpty(
                title: 'No invitations',
                message: 'Invite a teammate and their code will appear here.',
                icon: LucideIcons.mail,
              ),
            )
          : Column(
              children: [
                for (var k = 0; k < list.length; k++) ...[
                  if (k > 0) const Divider(height: 1, color: Sel.rowLine),
                  _InviteRow(
                    invite: list[k],
                    role: _role(list[k].role),
                    onResend: canManage && list[k].status != 'accepted'
                        ? () => _resend(context, ref, idx!.churchId, list[k])
                        : null,
                  ),
                ],
              ],
            ),
    );

    final main = SelCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
            child: Row(
              children: [
                _Tab(
                  label: 'Members',
                  count: memberCount,
                  on: !_invites,
                  onTap: () => setState(() => _invites = false),
                ),
                _Tab(
                  label: 'Invitations',
                  count: inviteList.length,
                  on: _invites,
                  onTap: () => setState(() => _invites = true),
                ),
              ],
            ),
          ),
          if (_invites)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Codes expire four hours after sending',
                      style: SelType.small,
                    ),
                  ),
                  inviteRows,
                ],
              ),
            )
          else
            members,
        ],
      ),
    );

    const roles = [
      ('Pastor', 'Approves giving, edits and closes partners, sets goals, merges records.'),
      ('Staff', "Enters giving and imports sheets. Edits partners' names, IDs and contacts, and moves people between fellowships. Can't approve or close a partner."),
      ('Admin', 'Sets up arms, periods, people and branding.'),
    ];
    final side = SelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Who can do what', style: SelType.subtitle),
          const SizedBox(height: SelSpace.x1),
          Text(
            "Change someone's role from the list. It applies the next time they open Pillr.",
            style: SelType.small,
          ),
          for (final (r, what) in roles) ...[
            const Divider(height: SelSpace.x6, color: Sel.border),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 90, child: Text(r, style: SelType.bodyMedium)),
                Expanded(child: Text(what, style: SelType.bodySm.copyWith(color: Sel.text))),
              ],
            ),
          ],
        ],
      ),
    );

    return SelPageBody(
      onRefresh: () async {
        ref.invalidate(churchUsersProvider);
        ref.invalidate(invitesListForAdminProvider);
      },
      children: [
        SelPageTitle(
          title: 'People',
          subtitle: 'Everyone who can sign in to $church, and everyone on the way in',
          actions: [
            if (canManage)
              SelButton.cyan(
                label: 'Invite someone',
                icon: LucideIcons.plus,
                onPressed: () => _inviteDialog(context, ref, idx!.churchId),
              ),
          ],
        ),
        LayoutBuilder(
          builder: (context, c) => c.maxWidth < 980
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [main, const SizedBox(height: SelSpace.x4), side],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: main),
                    const SizedBox(width: SelSpace.x4),
                    SizedBox(width: 320, child: side),
                  ],
                ),
        ),
      ],
    );
  }

  String _role(String r) => r.isEmpty ? '—' : r[0].toUpperCase() + r.substring(1);
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.count, required this.on, required this.onTap});

  final String label;
  final int count;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = on ? Sel.card : Sel.text;
    return Padding(
      padding: const EdgeInsets.only(right: SelSpace.x1),
      child: Material(
        color: on ? Sel.ink : Colors.transparent,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text.rich(
              TextSpan(
                text: '$label  ',
                style: SelType.body.copyWith(color: fg),
                children: [
                  TextSpan(
                    text: '$count',
                    style: TextStyle(color: fg, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleTag extends StatelessWidget {
  const _RoleTag({required this.role, this.inactive = false});

  final String role;
  final bool inactive;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: inactive ? Sel.track : Sel.skyWash,
      borderRadius: BorderRadius.circular(SelRadius.pill),
    ),
    child: Text(inactive ? '$role · inactive' : role, style: SelType.tag),
  );
}

/// Sends a fresh code to the same address and role, then removes the old
/// invite, so the list shows one invite per person.
Future<void> _resend(
  BuildContext context,
  WidgetRef ref,
  String churchId,
  dynamic invite,
) async {
  final repo = ref.read(inviteRepositoryProvider);
  try {
    await repo.sendInvite(
      churchId: churchId,
      email: invite.email as String,
      role: invite.role as String,
    );
    await repo.deleteInvite(churchId: churchId, inviteId: invite.id as String);
    if (context.mounted) {
      selNotice(context, 'A new code is on its way to ${invite.email}.');
    }
  } catch (e) {
    if (context.mounted) {
      selNotice(context, plainError(e), kind: SelNoticeKind.error);
    }
  }
}

class _InviteRow extends StatelessWidget {
  const _InviteRow({required this.invite, required this.role, this.onResend});

  final dynamic invite;
  final String role;
  final VoidCallback? onResend;

  @override
  Widget build(BuildContext context) {
    final expires = invite.expiresAt as DateTime;
    final left = expires.difference(DateTime.now());
    final live = invite.status == 'pending' && !left.isNegative;
    final who = invite.createdByName as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          SelFace((invite.email as String).split('@').first.replaceAll('.', ' '), size: 38),
          const SizedBox(width: SelSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(invite.email as String, style: SelType.body.copyWith(color: Sel.text, fontWeight: FontWeight.w600)),
                Text(
                  '$role · sent${who == null ? '' : ' by $who'} ${formatFirestoreDate(invite.createdAt as DateTime, pattern: 'd MMM, HH:mm')}',
                  style: SelType.small,
                ),
              ],
            ),
          ),
          if (live) ...[
            Text(
              invite.code as String,
              style: SelType.bodyMedium.copyWith(fontFamily: 'monospace', letterSpacing: 2),
            ),
            const SizedBox(width: SelSpace.x3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Sel.skyWash,
                borderRadius: BorderRadius.circular(SelRadius.pill),
              ),
              child: Text(
                'Expires in ${left.inHours}h ${left.inMinutes % 60}m',
                style: SelType.tag,
              ),
            ),
          ] else
            SelStatusMark.fromString(
              status: invite.status == 'accepted' ? 'accepted' : 'expired',
              label: invite.status == 'accepted' ? 'Accepted' : 'Expired',
            ),
          if (onResend != null) ...[
            const SizedBox(width: SelSpace.x3),
            SelLink(label: 'Resend', onTap: onResend),
          ],
        ],
      ),
    );
  }
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
