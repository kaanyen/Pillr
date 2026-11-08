import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/extensions/async_value_ext.dart';
import '../../design/seline.dart';
import '../../features/activity/activity_action_label.dart';
import '../../features/arms/providers/arms_providers.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/church/providers/church_settings_providers.dart';
import '../../features/dashboard/providers/admin_dashboard_providers.dart';
import '../../features/entries/bulk_import/bulk_import_batches.dart';
import '../../features/entries/domain/partnership_entry.dart';
import '../../features/entries/providers/entries_providers.dart';
import '../../features/logs/providers/activity_logs_providers.dart';
import '../../features/maintenance/providers/duplicate_health_provider.dart';
import '../../features/partners/providers/partners_providers.dart';
import '../../features/periods/providers/periods_providers.dart';
import '../../features/users/providers/users_providers.dart';

/// Every entry this person recorded, newest first.
final myEntriesProvider = StreamProvider.autoDispose<List<PartnershipEntry>>((
  ref,
) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null) return Stream.value(const []);
  return ref
      .watch(entriesRepositoryProvider)
      .watchMyEntries(idx.churchId, idx.uid);
});

const _soft = Color(0xFFC9DEF3);

String _initials(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .take(2)
    .map((w) => w[0].toUpperCase())
    .join();

String _days(DateTime since) {
  final d = DateTime.now().difference(since).inDays;
  return d <= 0 ? 'Today' : '$d ${d == 1 ? 'day' : 'days'}';
}

String _when(DateTime d) {
  final today = DateTime.now();
  final days = DateTime(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (days == 0) return 'today';
  if (days == 1) return 'yesterday';
  return DateFormat(d.year == today.year ? 'd MMM' : 'd MMM y').format(d);
}

// ---------------------------------------------------------------- pieces

/// The card frame every list on the Overview uses: a title, a link to the
/// full page, an optional line under the title, then rows.
class _ListCard extends StatelessWidget {
  const _ListCard({
    required this.title,
    required this.rows,
    this.link,
    this.onLink,
    this.note,
    this.empty,
    this.after,
  });

  final String title;
  final String? link;
  final VoidCallback? onLink;
  final String? note;
  final List<Widget> rows;
  final String? empty;
  final Widget? after;

  @override
  Widget build(BuildContext context) {
    return SelCard(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: SelType.subtitle)),
              if (link != null) SelLink(label: link!, onTap: onLink),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: SelSpace.x1),
            Text(note!, style: SelType.small),
          ],
          const SizedBox(height: SelSpace.x1),
          if (rows.isEmpty && empty != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SelSpace.x4),
              child: Text(empty!, style: SelType.bodySm),
            ),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Sel.rowLine),
            rows[i],
          ],
          ?after,
        ],
      ),
    );
  }
}

/// One person or entry in a list: initials, two lines, and a value.
class _Line extends StatelessWidget {
  const _Line({
    required this.title,
    required this.sub,
    this.initials,
    this.trailing,
    this.trailingSub,
    this.onTap,
  });

  final String title;
  final String sub;
  final String? initials;
  final Widget? trailing;
  final String? trailingSub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            if (initials != null) ...[
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Sel.skyTint,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initials!,
                  style: SelType.small.copyWith(
                    color: Sel.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: SelSpace.x3),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: SelType.body.copyWith(
                      color: Sel.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    sub,
                    overflow: TextOverflow.ellipsis,
                    style: SelType.small,
                  ),
                ],
              ),
            ),
            if (trailing != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  trailing!,
                  if (trailingSub != null)
                    Text(trailingSub!, style: SelType.small),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

Widget _money(String text) => Text(
  text,
  style: SelType.body.copyWith(
    color: Sel.ink,
    fontWeight: FontWeight.w700,
    fontFeatures: const [FontFeature.tabularFigures()],
  ),
);

Widget _tag(String text, {bool waiting = false}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  decoration: BoxDecoration(
    color: waiting ? Sel.skyWash : Sel.track,
    borderRadius: BorderRadius.circular(SelRadius.pill),
  ),
  child: Text(
    text,
    style: SelType.small.copyWith(color: waiting ? Sel.ink : Sel.text),
  ),
);

/// The navy card on the right of the first row: what needs this person.
class _NavyCard extends StatelessWidget {
  const _NavyCard({
    required this.label,
    required this.headline,
    required this.sub,
    required this.body,
    this.action,
    this.onAction,
    this.footLink,
    this.onFootLink,
  });

  final String label;
  final String headline;
  final String sub;
  final List<Widget> body;
  final String? action;
  final VoidCallback? onAction;
  final String? footLink;
  final VoidCallback? onFootLink;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(26, 26, 26, 22),
      decoration: BoxDecoration(
        color: Sel.ink,
        borderRadius: BorderRadius.circular(SelRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: SelType.body.copyWith(color: _soft)),
          const SizedBox(height: SelSpace.x1),
          Text(
            headline,
            style: SelType.hero.copyWith(
              fontSize: 32,
              color: Sel.card,
              height: 1.15,
            ),
          ),
          Text(sub, style: SelType.body.copyWith(color: _soft)),
          const SizedBox(height: SelSpace.x3),
          ...body,
          const SizedBox(height: SelSpace.x4),
          if (action != null)
            Material(
              color: Sel.card,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: onAction,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  child: Text(
                    action!,
                    textAlign: TextAlign.center,
                    style: SelType.button.copyWith(color: Sel.ink),
                  ),
                ),
              ),
            ),
          if (footLink != null) ...[
            const SizedBox(height: SelSpace.x3),
            Center(
              child: InkWell(
                onTap: onFootLink,
                child: Text(
                  footLink!,
                  style: SelType.bodySm.copyWith(
                    color: Sel.card,
                    decoration: TextDecoration.underline,
                    decorationColor: Sel.card,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A wide card beside the navy card, and three cards under them; on a narrow
/// screen everything stacks.
Widget _layout({
  required Widget wide,
  required Widget navy,
  required List<Widget> lower,
}) {
  return LayoutBuilder(
    builder: (context, c) {
      if (c.maxWidth < 900) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            wide,
            const SizedBox(height: SelSpace.x4),
            navy,
            for (final w in lower) ...[const SizedBox(height: SelSpace.x4), w],
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: wide),
                const SizedBox(width: SelSpace.x4),
                SizedBox(width: 330, child: navy),
              ],
            ),
          ),
          const SizedBox(height: SelSpace.x4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < lower.length; i++) ...[
                if (i > 0) const SizedBox(width: SelSpace.x4),
                Expanded(child: lower[i]),
              ],
            ],
          ),
        ],
      );
    },
  );
}

Widget _figure(String label, String value, String? sub, {bool big = false}) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: SelType.small.copyWith(fontWeight: FontWeight.w600)),
        Text(
          value,
          style: big
              ? SelType.hero.copyWith(fontSize: 32, height: 1.2)
              : SelType.subtitle.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.5,
                ),
        ),
        if (sub != null) Text(sub, style: SelType.small),
      ],
    );

// ----------------------------------------------------------------- staff

/// The staff Overview, as on the canvas: what they recorded this month and
/// where it stands, what a pastor sent back, what is still with a pastor, what
/// was approved lately and the sheets brought in.
///
/// Staff see their own work here; the church's totals are the pastor's.
class StaffOverview extends ConsumerWidget {
  const StaffOverview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(churchMoneyFormatProvider);
    final tree = ref.watch(armTreeProvider);
    final mine =
        ref.watch(myEntriesProvider).valueOrNull ?? const <PartnershipEntry>[];
    final now = DateTime.now();
    final month = [
      for (final e in mine)
        if (e.createdAt.year == now.year && e.createdAt.month == now.month) e,
    ];
    List<PartnershipEntry> of(Iterable<PartnershipEntry> es, String s) => [
      for (final e in es)
        if (e.status == s) e,
    ];
    double sum(List<PartnershipEntry> es) =>
        es.fold(0, (s, e) => s + e.amountCedis);
    final approved = of(month, 'approved');
    final waiting = of(month, 'pending');
    final back = of(month, 'declined');
    final sentBack = of(mine, 'declined');
    final pendingAll = of(mine, 'pending')
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final recentApproved = of(mine, 'approved')
      ..sort(
        (a, b) => (b.reviewedAt ?? b.updatedAt).compareTo(
          a.reviewedAt ?? a.updatedAt,
        ),
      );
    final turnaround = [
      for (final e in of(mine, 'approved'))
        if (e.reviewedAt != null) e.reviewedAt!.difference(e.createdAt).inHours,
    ]..sort();
    final usualDays = turnaround.isEmpty
        ? null
        : (turnaround[turnaround.length ~/ 2] / 24).ceil();
    final monthName = DateFormat('MMMM').format(now);
    String arm(PartnershipEntry e) =>
        tree.shownNameOf(e.partnershipArmId) ??
        e.armSnapshot['name']?.toString() ??
        '';
    String who(PartnershipEntry e) =>
        e.partnerSnapshot['fullName']?.toString() ?? 'A partner';

    final total = sum(month);
    final full = money(total);
    final dot = full.lastIndexOf('.');
    final wide = SelCard(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'What you recorded in $monthName',
                  style: SelType.subtitle,
                ),
              ),
              SelLink(
                label: 'See them in Records',
                onTap: () => context.go('/records'),
              ),
            ],
          ),
          const SizedBox(height: SelSpace.x4),
          Wrap(
            spacing: SelSpace.x10,
            runSpacing: SelSpace.x4,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recorded',
                    style: SelType.small.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text.rich(
                    TextSpan(
                      text: dot < 0 ? full : full.substring(0, dot),
                      style: SelType.hero.copyWith(fontSize: 32, height: 1.2),
                      children: [
                        if (dot >= 0)
                          TextSpan(
                            text: full.substring(dot),
                            style: SelType.subtitle.copyWith(color: Sel.warm),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '${month.length} ${month.length == 1 ? 'entry' : 'entries'}',
                    style: SelType.small,
                  ),
                ],
              ),
              _figure('Approved', '${approved.length}', money(sum(approved))),
              _figure(
                'With a pastor',
                '${waiting.length}',
                money(sum(waiting)),
              ),
              _figure('Sent back to you', '${back.length}', money(sum(back))),
            ],
          ),
          const SizedBox(height: SelSpace.x4),
          if (month.isNotEmpty)
            Semantics(
              label:
                  'Of ${month.length} entries, ${approved.length} approved, ${waiting.length} with a pastor, ${back.length} sent back',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(SelRadius.pill),
                child: SizedBox(
                  height: 12,
                  child: Row(
                    children: [
                      for (final (n, c) in [
                        (approved.length, Sel.ink),
                        (waiting.length, Sel.sky),
                        (back.length, const Color(0xFF9AA6B8)),
                      ])
                        if (n > 0)
                          Expanded(
                            flex: n,
                            child: Container(
                              margin: const EdgeInsets.only(right: 2),
                              color: c,
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            )
          else
            Text('Nothing recorded yet this month.', style: SelType.bodySm),
          if (month.isNotEmpty) const SizedBox(height: SelSpace.x3),
          if (month.isNotEmpty)
            Wrap(
              spacing: SelSpace.x4,
              children: [
                for (final (l, c) in [
                  ('Approved', Sel.ink),
                  ('With a pastor', Sel.sky),
                  ('Sent back', const Color(0xFF9AA6B8)),
                ])
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: c,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(l, style: SelType.small),
                    ],
                  ),
              ],
            ),
          const SizedBox(height: SelSpace.x4),
          Text(
            usualDays == null
                ? 'Everything you record counts once a pastor approves it.'
                : usualDays <= 0
                ? 'Everything you record counts once a pastor approves it. Most are approved the same day.'
                : 'Everything you record counts once a pastor approves it. Most are approved within $usualDays ${usualDays == 1 ? 'day' : 'days'}.',
            style: SelType.bodySm.copyWith(color: Sel.text),
          ),
        ],
      ),
    );

    final first = sentBack.isEmpty ? null : sentBack.first;
    final navy = _NavyCard(
      label: 'Sent back to you',
      headline: sentBack.isEmpty
          ? 'Nothing'
          : '${sentBack.length} ${sentBack.length == 1 ? 'entry' : 'entries'}',
      sub: sentBack.isEmpty
          ? 'No pastor has asked for a change.'
          : 'A pastor asked for a change',
      body: [
        if (first != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        who(first),
                        style: SelType.body.copyWith(
                          color: Sel.card,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      money(first.amountCedis),
                      style: SelType.body.copyWith(
                        color: Sel.card,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${arm(first)} · ${DateFormat('d MMM').format(first.dateGiven)}',
                  style: SelType.small.copyWith(color: _soft),
                ),
                if ((first.declineReason ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: SelSpace.x2),
                  Text(
                    '“${first.declineReason!.trim()}”',
                    style: SelType.bodySm.copyWith(color: Sel.card),
                  ),
                ],
                if (first.reviewedAt != null)
                  Text(
                    '${first.reviewedBySnapshot?['fullName'] ?? 'A pastor'} · ${_when(first.reviewedAt!)}',
                    style: SelType.small.copyWith(color: _soft),
                  ),
              ],
            ),
          ),
      ],
      action: first == null ? 'Record giving' : 'Fix and send again',
      onAction: first == null
          ? () => context.go('/entries/new')
          : () => context.go('/entries/${first.id}'),
      footLink: sentBack.length > 1
          ? 'See all ${sentBack.length} sent back'
          : null,
      onFootLink: () => context.go('/records?filter=declined'),
    );

    final withPastor = _ListCard(
      title: 'With a pastor',
      link: pendingAll.isEmpty ? null : 'All ${pendingAll.length}',
      onLink: () => context.go('/queue'),
      note: 'Yours, waiting to be approved. Oldest first.',
      empty: 'Nothing of yours is waiting.',
      rows: [
        for (final e in pendingAll.take(4))
          _Line(
            initials: _initials(who(e)),
            title: who(e),
            sub: '${arm(e)} · ${DateFormat('d MMM').format(e.dateGiven)}',
            trailing: _money(money(e.amountCedis)),
            trailingSub: _days(e.createdAt),
            onTap: () => context.go('/entries/${e.id}'),
          ),
      ],
    );

    final lately = _ListCard(
      title: 'Recently approved',
      link: 'Records',
      onLink: () => context.go('/records'),
      note: 'Yours, newest first.',
      empty: 'Approved entries will show here.',
      rows: [
        for (final e in recentApproved.take(4))
          _Line(
            initials: _initials(who(e)),
            title: who(e),
            sub: '${arm(e)} · approved ${_when(e.reviewedAt ?? e.updatedAt)}',
            trailing: _money(money(e.amountCedis)),
            onTap: () => context.go('/entries/${e.id}'),
          ),
      ],
    );

    final batches =
        ref.watch(recentImportBatchesProvider).valueOrNull ?? const [];
    final sheets = _ListCard(
      title: 'Sheets',
      link: 'Imports',
      onLink: () => context.go('/records/imports'),
      empty: 'No sheets brought in yet.',
      rows: [
        for (final b in batches.take(3))
          _Line(
            title: b.displayName,
            sub:
                '${b.entryCount} entries · ${DateFormat('d MMM').format(b.createdAt)} · ${b.createdByName}',
            trailing: b.isIncomplete
                ? _tag('Not finished', waiting: true)
                : b.isVoided
                ? _tag('Cleared')
                : null,
            onTap: () => context.go('/records/imports'),
          ),
      ],
      after: Padding(
        padding: const EdgeInsets.only(top: SelSpace.x2),
        child: SelLink(
          label: 'Bring in a sheet',
          onTap: () => context.go('/entries/bulk-import'),
        ),
      ),
    );

    return _layout(wide: wide, navy: navy, lower: [withPastor, lately, sheets]);
  }
}

// ----------------------------------------------------------------- admin

/// The admin Overview, as on the canvas: how the church is set up, step by
/// step, invites that have not been accepted, the people, the fellowships and
/// recent changes. No giving figures: the admin runs the setup.
class AdminOverview extends ConsumerWidget {
  const AdminOverview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(churchSettingsProvider).valueOrNull;
    final period = ref.watch(activePeriodProvider);
    final tree = ref.watch(armTreeProvider);
    final users = ref.watch(churchUsersProvider).valueOrNull ?? const [];
    final invites = [
      for (final i
          in ref.watch(invitesListForAdminProvider).valueOrNull ?? const [])
        if (i.status == 'pending') i,
    ];
    final partners =
        ref.watch(partnersStreamProvider(false)).valueOrNull ?? const [];
    final dupes = ref.watch(duplicateBadgeCountProvider);
    final pastors = users.where((u) => u.role == 'pastor').length;
    final staff = users.where((u) => u.role == 'staff').length;
    final mains = tree.mains;
    final subs = tree.flattened.length - mains.length;
    final daysLeft = period?.endDate.difference(DateTime.now()).inDays;

    final steps = <(bool, String, String, String, String)>[
      (
        (settings?.name ?? '').trim().isNotEmpty,
        'Church name and logo',
        [
          settings?.name ?? 'No name yet',
          settings?.logoUrl == null ? 'initials as the mark' : 'logo added',
        ].join(' · '),
        'Change',
        '/settings',
      ),
      (
        period != null,
        period == null ? 'Open a giving period' : 'A giving period is open',
        period == null
            ? 'Giving is counted against a period, usually a year.'
            : '${period.name} · ${DateFormat('d MMM').format(period.startDate)} to ${DateFormat('d MMM').format(period.endDate)}${daysLeft == null || daysLeft < 0 ? '' : ' · $daysLeft days left'}',
        period == null ? 'Open one' : 'Open',
        '/configuration',
      ),
      (
        mains.isNotEmpty,
        'Arms to give to',
        mains.isEmpty
            ? 'Tithe, Building, Missions: whatever your church gives towards.'
            : '${mains.take(3).map((a) => a.name).join(', ')}${mains.length > 3 ? ' and ${mains.length - 3} more' : ''}${subs > 0 ? ' · $subs sub-arms' : ''}',
        mains.isEmpty ? 'Add arms' : 'Edit',
        '/configuration',
      ),
      (
        pastors > 0 && staff > 0,
        'People who record and approve',
        '$pastors ${pastors == 1 ? 'pastor' : 'pastors'} · $staff staff',
        'People',
        '/people',
      ),
      (
        settings?.sendMonthlyPartnerEmails ?? false,
        'Monthly thank-you letters',
        (settings?.sendMonthlyPartnerEmails ?? false)
            ? 'On. Partners with an email get a summary of their giving each month.'
            : 'Off. Partners with an email get a summary of their giving each month.',
        (settings?.sendMonthlyPartnerEmails ?? false) ? 'Settings' : 'Turn on',
        '/settings',
      ),
    ];
    final done = steps.where((s) => s.$1).length;

    final wide = SelCard(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'How the church is set up',
                  style: SelType.subtitle,
                ),
              ),
              Text('$done of ${steps.length} done', style: SelType.small),
            ],
          ),
          const SizedBox(height: SelSpace.x3),
          ClipRRect(
            borderRadius: BorderRadius.circular(SelRadius.pill),
            child: LinearProgressIndicator(
              value: done / steps.length,
              minHeight: 8,
              color: Sel.sky,
              backgroundColor: Sel.track,
              semanticsLabel: '$done of ${steps.length} done',
            ),
          ),
          const SizedBox(height: SelSpace.x2),
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Sel.rowLine),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: steps[i].$1 ? Sel.skyWash : Sel.card,
                      border: steps[i].$1
                          ? null
                          : Border.all(
                              color: const Color(0xFF9AA6B8),
                              width: 1.5,
                            ),
                    ),
                    child: steps[i].$1
                        ? const Icon(
                            LucideIcons.check,
                            size: 14,
                            color: Sel.ink,
                          )
                        : null,
                  ),
                  const SizedBox(width: SelSpace.x4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          steps[i].$2,
                          style: SelType.body.copyWith(
                            color: Sel.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(steps[i].$3, style: SelType.bodySm),
                      ],
                    ),
                  ),
                  const SizedBox(width: SelSpace.x3),
                  if (steps[i].$1)
                    SelLink(
                      label: steps[i].$4,
                      onTap: () => context.go(steps[i].$5),
                    )
                  else
                    SelButton(
                      label: steps[i].$4,
                      onPressed: () => context.go(steps[i].$5),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    final navy = _NavyCard(
      label: 'Needs you',
      headline: invites.isEmpty
          ? 'Nothing'
          : '${invites.length} ${invites.length == 1 ? 'invite' : 'invites'}',
      sub: invites.isEmpty
          ? 'Every invite has been accepted.'
          : 'Not accepted yet',
      body: [
        for (var i = 0; i < invites.length && i < 3; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              border: i == 0
                  ? null
                  : Border(
                      top: BorderSide(
                        color: Sel.skyWash.withValues(alpha: 0.2),
                      ),
                    ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invites[i].email,
                  overflow: TextOverflow.ellipsis,
                  style: SelType.body.copyWith(
                    color: Sel.card,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${invites[i].role[0].toUpperCase()}${invites[i].role.substring(1)} · sent ${_when(invites[i].createdAt)} · ${invites[i].expiresAt.isBefore(DateTime.now()) ? 'ended' : 'ends ${_when(invites[i].expiresAt)}'}',
                  style: SelType.small.copyWith(color: _soft),
                ),
              ],
            ),
          ),
      ],
      action: invites.isEmpty ? 'Invite someone' : 'Open People',
      onAction: () => context.go('/people'),
      footLink: dupes > 0
          ? '$dupes possible ${dupes == 1 ? 'duplicate' : 'duplicates'} to check'
          : null,
      onFootLink: () => context.go('/tools'),
    );

    final people = _ListCard(
      title: 'People',
      link: 'All ${users.length}',
      onLink: () => context.go('/people'),
      empty: 'Nobody yet. Invite a pastor and staff.',
      rows: [
        for (final u in users.take(4))
          _Line(
            initials: _initials(u.fullName),
            title: u.fullName,
            sub: '${u.role[0].toUpperCase()}${u.role.substring(1)}',
            trailing: Text(u.email, style: SelType.small),
          ),
      ],
    );

    final counts = <String, int>{};
    var noFellowship = 0;
    for (final p in partners) {
      final f = p.fellowship.trim();
      if (f.isEmpty) {
        noFellowship++;
      } else {
        counts[f] = (counts[f] ?? 0) + 1;
      }
    }
    final order = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final fellowships = _ListCard(
      title: 'Fellowships',
      link: 'All ${order.length}',
      onLink: () => context.go('/fellowships'),
      empty: 'No fellowships yet.',
      rows: [
        for (final f in order.take(4))
          _Line(
            title: f.key,
            sub: '${f.value} ${f.value == 1 ? 'partner' : 'partners'}',
            onTap: () => context.go(
              '/fellowships/${Uri.encodeComponent(f.key.toLowerCase())}',
            ),
          ),
      ],
      after: noFellowship == 0
          ? null
          : Container(
              margin: const EdgeInsets.only(
                top: SelSpace.x2,
                bottom: SelSpace.x2,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Sel.skyTint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '$noFellowship ${noFellowship == 1 ? 'partner has' : 'partners have'} no fellowship. ',
                    style: SelType.bodySm.copyWith(color: Sel.ink),
                  ),
                  SelLink(
                    label: 'Give them one',
                    onTap: () => context.go('/partners'),
                  ),
                ],
              ),
            ),
    );

    final logs = ref.watch(activityLogsPreviewProvider).valueOrNull ?? const [];
    final changes = _ListCard(
      title: 'Recent changes',
      link: 'Activity',
      onLink: () => context.go('/activity'),
      empty: 'Nothing changed yet.',
      rows: [
        for (final l in logs.take(3))
          _Line(
            title: activityActionLabel(l.action),
            sub: '${l.actorName} · ${_when(l.createdAt)}',
          ),
      ],
    );

    return _layout(
      wide: wide,
      navy: navy,
      lower: [people, fellowships, changes],
    );
  }
}
