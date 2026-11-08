import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons/lucide_icons.dart';

import '../core/constants/firebase_constants.dart';
import '../core/extensions/async_value_ext.dart';
import '../core/notifications/sel_notice.dart';
import '../design/seline.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/dashboard/providers/admin_dashboard_providers.dart';
import '../features/users/providers/users_providers.dart';

/// What the server says about how Pillr is running: counts and ages only.
class ChurchHealth {
  ChurchHealth(Map<String, dynamic> m)
    : waiting = Map<String, dynamic>.from(m['waiting'] as Map? ?? {}),
      duplicatesOpen = ((m['duplicates'] as Map?)?['open'] as num?)?.toInt() ?? 0,
      duplicatesCheckedAt = _date((m['duplicates'] as Map?)?['checkedAt']),
      letters = m['letters'] == null ? null : Map<String, dynamic>.from(m['letters'] as Map),
      sheets = [
        for (final s in (m['sheets'] as List? ?? const [])) Map<String, dynamic>.from(s as Map),
      ],
      partnersOff = ((m['totals'] as Map?)?['partnersOff'] as num?)?.toInt() ?? 0,
      periodsOff = ((m['totals'] as Map?)?['periodsOff'] as num?)?.toInt() ?? 0,
      lastRemindedAt = _date(m['lastRemindedAt']),
      lastBackupAt = _date((m['lastBackup'] as Map?)?['at']);

  final Map<String, dynamic> waiting;
  final int duplicatesOpen;
  final DateTime? duplicatesCheckedAt;
  final Map<String, dynamic>? letters;
  final List<Map<String, dynamic>> sheets;
  final int partnersOff;
  final int periodsOff;
  final DateTime? lastRemindedAt;
  final DateTime? lastBackupAt;

  int n(String k) => (waiting[k] as num?)?.toInt() ?? 0;

  static DateTime? _date(Object? ms) =>
      ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()) : null;
}

final churchHealthProvider = FutureProvider.autoDispose<ChurchHealth>((ref) async {
  final r = await ref
      .watch(firebaseFunctionsProvider)
      .httpsCallable(FirebaseConstants.churchHealth)
      .call(<String, dynamic>{});
  return ChurchHealth(Map<String, dynamic>.from(r.data as Map));
});

/// Health, as on the canvas (board 53): how Pillr is running for the church,
/// for the admin who runs it. Counts only — nothing here shows who gave or
/// how much.
class HealthScreen extends ConsumerStatefulWidget {
  const HealthScreen({super.key});

  @override
  ConsumerState<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends ConsumerState<HealthScreen> {
  bool _reminding = false;

  Future<void> _remind(int waiting, int oldest) async {
    final ok = await selConfirm(
      context,
      title: 'Remind the pastors?',
      message:
          'Each pastor gets one short note: $waiting ${waiting == 1 ? 'entry is' : 'entries are'} '
          'waiting, the oldest $oldest ${oldest == 1 ? 'day' : 'days'}. No names or amounts. '
          'You can do this once a day.',
      confirmLabel: 'Remind them',
    );
    if (!ok) return;
    setState(() => _reminding = true);
    try {
      final r = await ref
          .read(firebaseFunctionsProvider)
          .httpsCallable(FirebaseConstants.remindPastors)
          .call(<String, dynamic>{});
      final d = Map<String, dynamic>.from(r.data as Map);
      final delivered = (d['delivered'] as num?)?.toInt() ?? 0;
      if (mounted) {
        selNotice(
          context,
          delivered > 0
              ? 'Sent to $delivered ${delivered == 1 ? 'device' : 'devices'}.'
              : 'Noted, but no pastor has notifications turned on, so nothing reached a phone. Tell them in person.',
        );
        ref.invalidate(churchHealthProvider);
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) selNotice(context, e.message ?? 'Could not send the reminder.', kind: SelNoticeKind.error);
    } finally {
      if (mounted) setState(() => _reminding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final health = ref.watch(churchHealthProvider);
    final users = ref.watch(churchUsersProvider).valueOrNull ?? const [];
    final invites = ref.watch(pendingInvitesCountProvider);
    final quiet = [
      for (final u in users)
        if (u.isActive &&
            u.lastLoginAt != null &&
            DateTime.now().difference(u.lastLoginAt!).inDays >= 21)
          u,
    ];
    final now = DateTime.now();

    Widget tile(String k, String v, String sub, String? link, VoidCallback? onLink, {bool navy = false}) =>
        Container(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          decoration: BoxDecoration(
            color: navy ? Sel.ink : Sel.card,
            borderRadius: BorderRadius.circular(SelRadius.card),
            border: Border.all(color: navy ? Sel.ink : Sel.border),
            boxShadow: navy ? null : SelShadow.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(k, style: SelType.small.copyWith(color: navy ? SelNavyCard.soft : Sel.warm)),
              const SizedBox(height: 4),
              Text(v, style: SelType.hero.copyWith(fontSize: 30, height: 1.15, color: navy ? Sel.card : Sel.ink)),
              const SizedBox(height: 4),
              Text(sub, style: SelType.small.copyWith(color: navy ? SelNavyCard.soft : Sel.warm)),
              if (link != null) ...[
                const SizedBox(height: SelSpace.x3),
                InkWell(
                  onTap: onLink,
                  child: Text(
                    link,
                    style: SelType.bodySm.copyWith(
                      color: navy ? Sel.card : Sel.cyanEdge,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                      decorationColor: navy ? Sel.card : Sel.cyanEdge,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );

    Widget check(bool ok, String title, String sub, {String? link, VoidCallback? onLink}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: ok ? Sel.skyWash : Sel.ink, shape: BoxShape.circle),
            child: Text(ok ? '✓' : '!', style: SelType.small.copyWith(color: ok ? Sel.ink : Sel.card, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: SelSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: SelType.body.copyWith(color: Sel.text, fontWeight: FontWeight.w600)),
                Text(sub, style: SelType.small),
              ],
            ),
          ),
          if (link != null) SelLink(label: link, onTap: onLink),
        ],
      ),
    );

    return SelPageBody(
      onRefresh: () async => ref.invalidate(churchHealthProvider),
      children: [
        SelPageTitle(
          title: 'Health',
          subtitle: 'How Pillr is running. Counts only: nothing here shows who gave or how much.',
          actions: [SelButton(label: 'Activity', onPressed: () => context.go('/activity'))],
        ),
        health.when(
          loading: () => const SelCard(child: SelSkeletonRows(count: 6)),
          error: (e, _) => SelError(message: '$e'),
          data: (h) {
            final waiting = h.n('count');
            final oldest = h.n('oldestDays');
            final letters = h.letters;
            final remindedToday = h.lastRemindedAt != null && now.difference(h.lastRemindedAt!).inHours < 20;
            final totalsOk = h.partnersOff == 0 && h.periodsOff == 0;

            final tiles = [
              tile(
                'Waiting for a pastor',
                '$waiting ${waiting == 1 ? 'entry' : 'entries'}',
                waiting == 0 ? 'Nothing is waiting' : 'The oldest has waited $oldest ${oldest == 1 ? 'day' : 'days'}',
                waiting == 0 || remindedToday ? null : 'Remind the pastors',
                () => _remind(waiting, oldest),
                navy: waiting > 0,
              ),
              tile(
                'On the book twice?',
                '${h.duplicatesOpen} ${h.duplicatesOpen == 1 ? 'pair' : 'pairs'}',
                h.duplicatesCheckedAt == null ? 'Not checked yet' : "Found by last night's check",
                'Review in Tools',
                () => context.go('/tools'),
              ),
              tile(
                letters == null ? 'Monthly letters' : 'Monthly letters · ${(letters['monthLabel'] as String? ?? '').split(' ').first}',
                letters == null ? 'Not sent yet' : '${letters['sent']} sent',
                letters == null
                    ? 'They go out on the 15th once switched on'
                    : '${letters['failed']} could not be sent · ${letters['noEmail']} have no email',
                'Letters',
                () => context.go('/settings/letters'),
              ),
              tile(
                'Totals',
                totalsOk ? 'All match' : '${h.partnersOff + h.periodsOff} out',
                totalsOk ? 'Every total matches its entries' : 'A pastor can repair them in Tools',
                null,
                null,
              ),
            ];

            Widget bar(String label, int v, {bool dark = false}) => Padding(
              padding: const EdgeInsets.only(bottom: SelSpace.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(label, style: SelType.bodySm.copyWith(color: Sel.text, fontWeight: FontWeight.w600))),
                      Text('$v', style: SelType.bodySm),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(SelRadius.pill),
                    child: LinearProgressIndicator(
                      value: waiting == 0 ? 0 : v / waiting,
                      minHeight: 12,
                      backgroundColor: Sel.track,
                      valueColor: AlwaysStoppedAnimation(dark ? Sel.ink : Sel.sky),
                    ),
                  ),
                ],
              ),
            );

            final waitCard = SelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('How long entries have waited', style: SelType.subtitle)),
                      Text('$waiting in all', style: SelType.small),
                    ],
                  ),
                  const SizedBox(height: SelSpace.x4),
                  bar('Under a week', h.n('underWeek')),
                  bar('One to four weeks', h.n('underMonth')),
                  bar('Over a month', h.n('overMonth'), dark: true),
                  const SizedBox(height: SelSpace.x2),
                  Container(
                    padding: const EdgeInsets.all(SelSpace.x3),
                    decoration: BoxDecoration(color: Sel.skyTint, borderRadius: BorderRadius.circular(16)),
                    child: Text(
                      'Remind the pastors sends each pastor one short note with the count and the oldest age. '
                      'No names or amounts. Once a day at most.',
                      style: SelType.small,
                    ),
                  ),
                  const SizedBox(height: SelSpace.x4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelButton.cyan(
                      label: remindedToday ? 'Reminded today' : 'Remind the pastors',
                      loading: _reminding,
                      onPressed: waiting == 0 || remindedToday || _reminding ? null : () => _remind(waiting, oldest),
                    ),
                  ),
                ],
              ),
            );

            final checks = SelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Checks', style: SelType.subtitle),
                  const SizedBox(height: SelSpace.x2),
                  check(
                    totalsOk,
                    'Partner and period totals',
                    totalsOk
                        ? 'Match the entries'
                        : '${h.partnersOff} partners and ${h.periodsOff} periods are out. A pastor repairs them in Tools.',
                    link: 'Check again',
                    onLink: () => ref.invalidate(churchHealthProvider),
                  ),
                  const Divider(height: 1, color: Sel.rowLine),
                  check(
                    h.duplicatesOpen == 0,
                    'Possible duplicates',
                    h.duplicatesOpen == 0 ? 'None found' : '${h.duplicatesOpen} to look at',
                    link: h.duplicatesOpen == 0 ? null : 'Review',
                    onLink: () => context.go('/tools'),
                  ),
                  const Divider(height: 1, color: Sel.rowLine),
                  check(
                    h.lastBackupAt != null && now.difference(h.lastBackupAt!).inDays <= 8,
                    'Backup',
                    h.lastBackupAt == null
                        ? 'None finished yet'
                        : 'Last one ${DateFormat('EEE d MMM, HH:mm').format(h.lastBackupAt!)}',
                    link: 'Backups',
                    onLink: () => context.go('/backups'),
                  ),
                  const Divider(height: 1, color: Sel.rowLine),
                  check(
                    letters == null || (letters['failed'] as num? ?? 0) == 0,
                    'Monthly letters',
                    letters == null
                        ? 'No run yet'
                        : (letters['failed'] as num? ?? 0) == 0
                        ? 'Last run sent every letter it could'
                        : '${letters['failed']} could not be sent. A pastor can see who and send again.',
                    link: 'Open',
                    onLink: () => context.go('/settings/letters'),
                  ),
                ],
              ),
            );

            final sheets = SelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('Sheets brought in', style: SelType.subtitle)),
                      Text('Last 30 days', style: SelType.small),
                    ],
                  ),
                  const SizedBox(height: SelSpace.x2),
                  if (h.sheets.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: SelSpace.x3),
                      child: Text('No sheets brought in.', style: SelType.bodySm),
                    ),
                  for (final (i, s) in h.sheets.indexed) ...[
                    if (i > 0) const Divider(height: 1, color: Sel.rowLine),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${s['fileName']}',
                                  overflow: TextOverflow.ellipsis,
                                  style: SelType.body.copyWith(color: Sel.text, fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  [
                                    '${s['rows']} rows',
                                    if ((s['by'] as String? ?? '').isNotEmpty) s['by'],
                                    if (s['at'] is num)
                                      DateFormat('d MMM').format(DateTime.fromMillisecondsSinceEpoch((s['at'] as num).toInt())),
                                  ].join(' · '),
                                  style: SelType.small,
                                ),
                              ],
                            ),
                          ),
                          s['undone'] == true
                              ? const SelTag('Undone')
                              : (s['waiting'] as num? ?? 0) > 0
                              ? SelTag('${s['waiting']} waiting', tone: SelTagTone.waiting)
                              : const SelTag('All approved'),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );

            final people = SelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('People', style: SelType.subtitle)),
                      SelLink(label: 'People', onTap: () => context.go('/people')),
                    ],
                  ),
                  const SizedBox(height: SelSpace.x2),
                  check(
                    invites == 0,
                    invites == 0 ? 'No invites waiting' : '$invites ${invites == 1 ? 'invite' : 'invites'} not accepted',
                    invites == 0 ? 'Everyone invited has joined' : 'Resend from People',
                    link: invites == 0 ? null : 'Resend',
                    onLink: () => context.go('/people'),
                  ),
                  const Divider(height: 1, color: Sel.rowLine),
                  check(
                    quiet.isEmpty,
                    quiet.isEmpty ? 'Everyone has been in lately' : 'Not seen in 3 weeks',
                    quiet.isEmpty ? 'Signed in within the last three weeks' : quiet.map((u) => u.fullName).join(', '),
                    link: quiet.isEmpty ? null : 'Open',
                    onLink: () => context.go('/people'),
                  ),
                ],
              ),
            );

            return LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth >= 900;
                final gap = const SizedBox(width: SelSpace.x4, height: SelSpace.x4);
                Widget pair(Widget a, Widget b) => wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [Expanded(flex: 13, child: a), gap, Expanded(flex: 10, child: b)],
                      )
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, gap, b]);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (wide)
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final (i, t) in tiles.indexed) ...[if (i > 0) gap, Expanded(child: t)],
                          ],
                        ),
                      )
                    else
                      Wrap(
                        spacing: SelSpace.x4,
                        runSpacing: SelSpace.x4,
                        children: [for (final t in tiles) SizedBox(width: (c.maxWidth - SelSpace.x4) / 2, child: t)],
                      ),
                    const SizedBox(height: SelSpace.x4),
                    pair(waitCard, checks),
                    const SizedBox(height: SelSpace.x4),
                    pair(sheets, people),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}

/// For the nav and tests: the health page is the admin's.
const healthIcon = LucideIcons.activity;
