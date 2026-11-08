import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/extensions/async_value_ext.dart';
import '../../design/seline.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/church/providers/church_settings_providers.dart';
import '../../features/leaderboard/giving_view.dart';
import '../../features/partners/domain/partner.dart';
import '../../features/partners/providers/partners_providers.dart';
import '../../features/periods/providers/periods_providers.dart';
import '../../core/navigation/panel_flows.dart';
import '../../core/notifications/sel_notice.dart';
import '../../features/users/providers/users_providers.dart';
import 'view_common.dart';

/// The last four digits of a partner's first phone, so a list can show which
/// number it is without printing it in full.
String _phoneEnd(Partner p) {
  final phones = p.allPhones;
  final digits = phones.isEmpty
      ? ''
      : phones.first.replaceAll(RegExp(r'\D'), '');
  return digits.length < 4
      ? 'None'
      : '··· ${digits.substring(digits.length - 4)}';
}

String _initials(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .take(2)
    .map((w) => w[0].toUpperCase())
    .join();

/// The partner's initials on light sky, the way every list shows a person.
class _Face extends StatelessWidget {
  const _Face(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => Container(
    width: 32,
    height: 32,
    alignment: Alignment.center,
    decoration: const BoxDecoration(color: Sel.skyWash, shape: BoxShape.circle),
    child: Text(
      _initials(name),
      style: SelType.small.copyWith(color: Sel.ink, fontWeight: FontWeight.w800),
    ),
  );
}

/// Name with initials, and an optional second line.
class _Who extends StatelessWidget {
  const _Who(this.name, [this.sub]);

  final String name;
  final String? sub;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _Face(name),
      const SizedBox(width: SelSpace.x3),
      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: SelType.body.copyWith(color: Sel.text, fontWeight: FontWeight.w600),
            ),
            if (sub != null && sub!.isNotEmpty)
              Text(sub!, overflow: TextOverflow.ellipsis, style: SelType.small),
          ],
        ),
      ),
    ],
  );
}

/// Title, subtitle and Add partner, the header every Partners view shares.
Widget _partnersTitle(BuildContext context, WidgetRef ref, String subtitle) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  final canAdd = idx != null && (idx.isPastor || idx.isStaff);
  return SelPageTitle(
    title: 'Partners',
    subtitle: subtitle,
    actions: [
      if (canAdd)
        SelButton.cyan(
          label: 'Add partner',
          onPressed: () => showPartnerFormPanel(
            context,
            churchId: idx.churchId,
            uid: idx.uid,
          ),
        ),
    ],
  );
}

/// A pill tag in the canvas style: navy, light sky or grey.
Widget _tag(String text, {Color fill = Sel.track, Color ink = Sel.text}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(SelRadius.pill),
      ),
      child: Text(text, style: SelType.small.copyWith(color: ink)),
    );

/// Partners · By fellowship, as on the canvas: one table with a heading per
/// fellowship. Each heading folds, and an open group shows its five biggest
/// givers first so fifty fellowships stay a short page.
class PartnersByFellowshipScreen extends ConsumerStatefulWidget {
  const PartnersByFellowshipScreen({super.key});

  @override
  ConsumerState<PartnersByFellowshipScreen> createState() =>
      _PartnersByFellowshipState();
}

class _PartnersByFellowshipState
    extends ConsumerState<PartnersByFellowshipScreen> {
  static const _firstFew = 5;
  String _query = '';
  final Set<String> _open = {};
  final Set<String> _all = {};
  bool _openedFirst = false;

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(churchMoneyFormatProvider);
    final view = ref.watch(givingViewProvider);
    final roster = ref.watch(partnersStreamProvider(false));
    final givingOf = {for (final p in view.partners) p.partnerId: p.total};
    final active = (roster.valueOrNull ?? const <Partner>[]).where((p) => p.isActive).length;

    Widget rowFor(Partner p) => InkWell(
      onTap: () => context.go('/partners/${p.id}'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Sel.rowLine)),
        ),
        child: Row(
          children: [
            Expanded(child: _Who(p.fullName)),
            SizedBox(
              width: 170,
              child: Text(
                money(givingOf[p.id] ?? 0),
                textAlign: TextAlign.right,
                style: SelType.body.copyWith(
                  color: Sel.ink,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            SizedBox(
              width: 130,
              child: Text(
                _phoneEnd(p),
                textAlign: TextAlign.right,
                style: SelType.bodySm.copyWith(fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
      ),
    );

    return SelPageBody(
      children: [
        _partnersTitle(context, ref, '$active active · grouped by fellowship'),
        roster.when(
          loading: () => const ViewLoading(),
          error: (e, _) => SelError(message: '$e'),
          data: (partners) {
            final groups = <String, List<Partner>>{};
            for (final p in partners) {
              final hit =
                  _query.isEmpty ||
                  p.fullName.toLowerCase().contains(_query) ||
                  p.allPhones.any((x) => x.contains(_query));
              if (hit) {
                groups
                    .putIfAbsent(p.fellowship.trim().toLowerCase(), () => [])
                    .add(p);
              }
            }
            if (!_openedFirst && view.fellowships.isNotEmpty) {
              _openedFirst = true;
              _open.addAll(view.fellowships.take(2).map((f) => f.key));
            }
            final order = view.fellowships
                .where((f) => groups.containsKey(f.key))
                .toList();
            return SelCard(
              padding: EdgeInsets.zero,
              clip: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      runSpacing: SelSpace.x2,
                      children: [
                        SizedBox(
                          width: 340,
                          child: ViewSearch(
                            hint: 'Name or phone',
                            onChanged: (v) => setState(() => _query = v),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SelLink(
                              label: 'Open all',
                              onTap: () => setState(
                                () => _open.addAll(order.map((f) => f.key)),
                              ),
                            ),
                            const SizedBox(width: SelSpace.x6),
                            SelLink(
                              label: 'Close all',
                              onTap: () => setState(_open.clear),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
                    child: Row(
                      children: [
                        Expanded(child: Text('Partner', style: SelType.small)),
                        SizedBox(
                          width: 170,
                          child: Text('Giving this year', textAlign: TextAlign.right, style: SelType.small),
                        ),
                        SizedBox(
                          width: 130,
                          child: Text('Phone', textAlign: TextAlign.right, style: SelType.small),
                        ),
                      ],
                    ),
                  ),
                  if (order.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(SelSpace.x6),
                      child: SelEmpty(
                        title: _query.isEmpty ? 'No partners yet' : 'No matches',
                        message: _query.isEmpty
                            ? 'Add partners to see them by fellowship.'
                            : 'Nothing matches “$_query”.',
                      ),
                    ),
                  for (final f in order) ...[
                    Builder(
                      builder: (context) {
                        final open = _open.contains(f.key) || _query.isNotEmpty;
                        final list = groups[f.key]!
                          ..sort(
                            (a, b) => (givingOf[b.id] ?? 0).compareTo(givingOf[a.id] ?? 0),
                          );
                        final shown = _all.contains(f.key) || _query.isNotEmpty
                            ? list
                            : list.take(_firstFew).toList();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Semantics(
                              button: true,
                              expanded: open,
                              child: InkWell(
                                onTap: () => setState(
                                  () => _open.contains(f.key)
                                      ? _open.remove(f.key)
                                      : _open.add(f.key),
                                ),
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(14, 16, 18, 12),
                                  decoration: const BoxDecoration(
                                    border: Border(top: BorderSide(color: Sel.border)),
                                  ),
                                  child: Row(
                                    children: [
                                      AnimatedRotation(
                                        turns: open ? 0.25 : 0,
                                        duration: const Duration(milliseconds: 160),
                                        curve: Curves.easeOutCubic,
                                        child: const Icon(LucideIcons.chevronRight, size: 16, color: Sel.ink),
                                      ),
                                      const SizedBox(width: SelSpace.x2),
                                      Text(f.name, style: SelType.subtitle),
                                      const SizedBox(width: SelSpace.x2),
                                      Text('${list.length} partners', style: SelType.small),
                                      const Spacer(),
                                      Text(
                                        money(f.total),
                                        style: SelType.bodyMedium.copyWith(fontWeight: FontWeight.w800),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (open) ...[
                              for (final p in shown) rowFor(p),
                              if (shown.length < list.length)
                                Container(
                                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
                                  decoration: const BoxDecoration(
                                    border: Border(top: BorderSide(color: Sel.rowLine)),
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: SelLink(
                                      label: 'Show all ${list.length} in ${f.name}',
                                      onTap: () => setState(() => _all.add(f.key)),
                                    ),
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
            );
          },
        ),
      ],
    );
  }
}

/// Partners · New this year, as on the canvas: how many joined and when, who
/// added each one, whether they have given yet, and a nudge for those who
/// have not.
class NewPartnersScreen extends ConsumerWidget {
  const NewPartnersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(churchMoneyFormatProvider);
    final view = ref.watch(givingViewProvider);
    final period = ref.watch(activePeriodProvider);
    final roster = ref.watch(partnersStreamProvider(false));
    final users = ref.watch(churchUsersProvider).valueOrNull ?? const [];
    final nameOf = {for (final u in users) u.uid: u.fullName};
    final byId = {for (final p in view.partners) p.partnerId: p};
    final since = period?.startDate ?? DateTime(DateTime.now().year);
    final active = (roster.valueOrNull ?? const <Partner>[]).where((p) => p.isActive).length;

    return SelPageBody(
      children: [
        _partnersTitle(
          context,
          ref,
          '$active active · who joined the book since ${gaveOn(since)}',
        ),
        roster.when(
          loading: () => const ViewLoading(),
          error: (e, _) => SelError(message: '$e'),
          data: (partners) {
            final fresh =
                partners.where((p) => !p.createdAt.isBefore(since)).toList()
                  ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            final gave = fresh.where((p) => byId[p.id] != null).toList();
            final notYet = fresh.where((p) => byId[p.id] == null).toList();
            final total = gave.fold<double>(0, (s, p) => s + byId[p.id]!.total);

            // One bar per month of the period so far.
            final now = DateTime.now();
            final months = <DateTime>[
              for (var m = DateTime(since.year, since.month);
                  !m.isAfter(now) && m.year * 12 + m.month - since.year * 12 - since.month < 12;
                  m = DateTime(m.year, m.month + 1))
                m,
            ];
            int joinedIn(DateTime m) => fresh
                .where((p) => p.createdAt.year == m.year && p.createdAt.month == m.month)
                .length;
            final peak = [for (final m in months) joinedIn(m), 1].reduce((a, b) => a > b ? a : b);

            final summary = SelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('New partners this year', style: SelType.bodyMedium),
                  const SizedBox(height: SelSpace.x2),
                  Text('${fresh.length}', style: SelType.hero.copyWith(fontSize: 40)),
                  const SizedBox(height: SelSpace.x2),
                  Text(
                    gave.isEmpty
                        ? 'None has given yet'
                        : '${gave.length} ${gave.length == 1 ? 'has' : 'have'} given, ${money(total)} between them',
                    style: SelType.bodySm,
                  ),
                ],
              ),
            );
            final chart = SelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('When they joined', style: SelType.bodyMedium),
                  const SizedBox(height: SelSpace.x4),
                  SizedBox(
                    height: 96,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final m in months)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Container(
                                    height: joinedIn(m) == 0 ? 4 : 70 * joinedIn(m) / peak,
                                    decoration: BoxDecoration(
                                      color: joinedIn(m) == 0 ? Sel.track : Sel.sky,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  const SizedBox(height: SelSpace.x2),
                                  Text(monthShort(GivingView.monthKey(m)), style: SelType.small),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, c) => c.maxWidth < 760
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [summary, const SizedBox(height: SelSpace.x4), chart],
                        )
                      : IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(width: 300, child: summary),
                              const SizedBox(width: SelSpace.x4),
                              Expanded(child: chart),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: SelSpace.x4),
                SelLedger(
                  minWidth: 720,
                  rowExtent: kSelLedgerStackedRowExtent,
                  columns: const [
                    SelColumn('Partner', flex: 3),
                    SelColumn('Joined', fit: SelColFit.fixed, width: 100),
                    SelColumn('Added by', flex: 2),
                    SelColumn('First giving', fit: SelColFit.fixed, width: 120),
                    SelColumn.numeric('Given since', width: 140),
                  ],
                  emptyState: const SelEmpty(
                    title: 'No new partners yet',
                    message: 'Partners added in this period show up here.',
                    icon: LucideIcons.userPlus,
                  ),
                  rows: [
                    for (final p in fresh)
                      SelRow(
                        onTap: () => context.go('/partners/${p.id}'),
                        cells: [
                          _Who(p.fullName, p.fellowship),
                          SelCell.secondary(gaveOn(p.createdAt)),
                          SelCell.secondary(
                            nameOf[p.createdBy] == null ? '' : 'Typed by ${nameOf[p.createdBy]}',
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: byId[p.id] == null
                                ? _tag('Not yet', fill: Sel.skyWash, ink: Sel.ink)
                                : Text(gaveOn(byId[p.id]!.firstGave), style: SelType.bodySm.copyWith(color: Sel.text)),
                          ),
                          SelCell.numeric(byId[p.id] == null ? '–' : money(byId[p.id]!.total)),
                        ],
                      ),
                  ],
                ),
                if (notYet.isNotEmpty) ...[
                  const SizedBox(height: SelSpace.x4),
                  SelCard(
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      runSpacing: SelSpace.x3,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "${notYet.length} new ${notYet.length == 1 ? "partner hasn't" : "partners haven't"} given yet",
                              style: SelType.subtitle,
                            ),
                            const SizedBox(height: SelSpace.x1),
                            Text(
                              '${notYet.last.fullName} joined in ${gaveOn(notYet.last.createdAt)}. A welcome call might help.',
                              style: SelType.bodySm,
                            ),
                          ],
                        ),
                        SelButton(
                          label: 'See them in Follow up',
                          onPressed: () => context.go('/partners/follow-up'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

enum _Rhythm { everyone, everyMonth, mostMonths, nowAndThen, stopped, notYet }

const _rhythmLabel = {
  _Rhythm.everyone: 'Everyone',
  _Rhythm.everyMonth: 'Every month',
  _Rhythm.mostMonths: 'Most months',
  _Rhythm.nowAndThen: 'Now and then',
  _Rhythm.stopped: 'Stopped',
  _Rhythm.notYet: 'Not yet',
};

/// Partners · Giving rhythm, as on the canvas: one dot per month, each
/// partner sorted into how often they give, with their usual gift size and
/// when they last gave. The month still under way is drawn open.
class GivingRhythmScreen extends ConsumerStatefulWidget {
  const GivingRhythmScreen({super.key});

  @override
  ConsumerState<GivingRhythmScreen> createState() => _GivingRhythmState();
}

class _GivingRhythmState extends ConsumerState<GivingRhythmScreen> {
  static const _page = 25;
  _Rhythm _tab = _Rhythm.everyone;
  int _start = 0;

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(churchMoneyFormatProvider);
    final view = ref.watch(givingViewProvider);
    final loading = ref.watch(givingViewLoadingProvider);
    final roster = ref.watch(partnersStreamProvider(false)).valueOrNull ?? const <Partner>[];
    final now = GivingView.monthKey(DateTime.now());
    final months = [for (final m in view.months) if (m <= now) m];
    final shownMonths = months.length > 12 ? months.sublist(months.length - 12) : months;
    final closed = [for (final m in months) if (m < now) m];

    _Rhythm rhythmOf(PartnerGiving p) {
      final gaveIn = closed.where((m) => (p.byMonth[m] ?? 0) > 0).length;
      if (gaveIn == 0 && (p.byMonth[now] ?? 0) == 0) return _Rhythm.notYet;
      final lastTwo = closed.length < 2 ? closed : closed.sublist(closed.length - 2);
      if (lastTwo.length == 2 && lastTwo.every((m) => (p.byMonth[m] ?? 0) == 0)) {
        return _Rhythm.stopped;
      }
      if (closed.isNotEmpty && gaveIn == closed.length) return _Rhythm.everyMonth;
      if (closed.isNotEmpty && gaveIn * 3 >= closed.length * 2) return _Rhythm.mostMonths;
      return _Rhythm.nowAndThen;
    }

    // Everyone on the book: those who gave, then active partners who have not.
    final gave = {for (final p in view.partners) p.partnerId};
    final rows = <({String id, String name, String fellowship, PartnerGiving? g, _Rhythm r})>[
      for (final p in view.partners)
        (id: p.partnerId, name: p.name, fellowship: p.fellowship, g: p, r: rhythmOf(p)),
      for (final p in roster)
        if (p.isActive && !gave.contains(p.id))
          (id: p.id, name: p.fullName, fellowship: p.fellowship, g: null, r: _Rhythm.notYet),
    ];
    int count(_Rhythm t) =>
        t == _Rhythm.everyone ? rows.length : rows.where((x) => x.r == t).length;
    final list = [for (final x in rows) if (_tab == _Rhythm.everyone || x.r == _tab) x];
    final start = _start >= list.length ? 0 : _start;
    final page = list.skip(start).take(_page).toList();

    double usual(PartnerGiving g) {
      final v = [for (final m in closed) if ((g.byMonth[m] ?? 0) > 0) g.byMonth[m]!]..sort();
      return v.isEmpty ? 0 : v[v.length ~/ 2];
    }

    String lastGave(PartnerGiving? g) {
      final last = g?.lastGave;
      if (last == null) return '–';
      final ago = now - GivingView.monthKey(last);
      final name = gaveOnMonth(last);
      return ago >= 2 ? '$name · $ago months' : name;
    }

    Widget dot(int m, bool on) {
      final open = m == now && !on;
      return Container(
        width: 14,
        height: 14,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? Sel.sky : Sel.card,
          border: Border.all(
            color: on ? Sel.sky : (open ? Sel.border : Sel.borderMuted),
            width: open ? 1 : 1.5,
          ),
        ),
      );
    }

    Widget rhythmTag(_Rhythm r) => switch (r) {
      _Rhythm.everyMonth => _tag('Every month', fill: Sel.ink, ink: Sel.card),
      _Rhythm.mostMonths => _tag('Most months', fill: Sel.skyWash, ink: Sel.ink),
      _Rhythm.nowAndThen => _tag('Now and then', fill: Sel.skyTint, ink: Sel.ink),
      _Rhythm.stopped => _tag('Stopped'),
      _ => _tag('Not yet'),
    };

    return SelPageBody(
      children: [
        _partnersTitle(context, ref, '${roster.where((p) => p.isActive).length} active · how often each one gives'),
        if (loading)
          const ViewLoading()
        else
          SelCard(
            padding: EdgeInsets.zero,
            clip: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Sel.border)),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final t in _Rhythm.values)
                          InkWell(
                            onTap: () => setState(() {
                              _tab = t;
                              _start = 0;
                            }),
                            child: Container(
                              width: 170,
                              padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
                              decoration: BoxDecoration(
                                color: t == _tab ? Sel.skyTint : null,
                                border: Border(
                                  bottom: BorderSide(
                                    color: t == _tab ? Sel.ink : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_rhythmLabel[t]!, style: SelType.small),
                                  Text(
                                    '${count(t)}',
                                    style: SelType.subtitle.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SelLedger(
                  bare: true,
                  minWidth: 300.0 + shownMonths.length * 22 + 420,
                  rowExtent: kSelLedgerStackedRowExtent,
                  columns: [
                    const SelColumn('Partner', flex: 3),
                    SelColumn(
                      shownMonths.map((m) => monthShort(m)[0]).join('   '),
                      fit: SelColFit.fixed,
                      width: shownMonths.length * 22.0 + 8,
                    ),
                    const SelColumn('Rhythm', fit: SelColFit.fixed, width: 140),
                    const SelColumn.numeric('Usual giving', width: 130),
                    const SelColumn.numeric('Last gave', width: 170),
                  ],
                  emptyState: const SelEmpty(
                    title: 'Nobody here',
                    message: 'No partner gives in this rhythm yet.',
                  ),
                  rows: [
                    for (final x in page)
                      SelRow(
                        onTap: () => context.go('/partners/${x.id}'),
                        cells: [
                          _Who(x.name, x.fellowship),
                          Row(
                            children: [
                              for (final m in shownMonths)
                                dot(m, (x.g?.byMonth[m] ?? 0) > 0),
                            ],
                          ),
                          Align(alignment: Alignment.centerLeft, child: rhythmTag(x.r)),
                          SelCell.numeric(x.g == null ? '–' : money(usual(x.g!)), strong: false),
                          SelCell.numeric(lastGave(x.g), strong: false),
                        ],
                      ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Sel.rowLine)),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: SelSpace.x2,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          dot(-1, true),
                          Text('Gave', style: SelType.small),
                          const SizedBox(width: SelSpace.x3),
                          dot(-1, false),
                          Text("Didn't", style: SelType.small),
                          const SizedBox(width: SelSpace.x3),
                          dot(now, false),
                          Text('${monthLong(now).split(' ').first}, still open', style: SelType.small),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            list.isEmpty ? '' : '${start + 1}–${start + page.length} of ${list.length}',
                            style: SelType.small,
                          ),
                          if (start > 0) ...[
                            const SizedBox(width: SelSpace.x3),
                            SelButton(
                              label: 'Previous',
                              dense: true,
                              onPressed: () => setState(() => _start = start - _page),
                            ),
                          ],
                          if (start + _page < list.length) ...[
                            const SizedBox(width: SelSpace.x2),
                            SelButton(
                              label: 'Next',
                              dense: true,
                              onPressed: () => setState(() => _start = start + _page),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Partners · Follow up: active partners who have not given in a while, with
/// a reason the church can note against each one, and their numbers to copy
/// for a round of calls.
class FollowUpScreen extends ConsumerStatefulWidget {
  const FollowUpScreen({super.key});

  @override
  ConsumerState<FollowUpScreen> createState() => _FollowUpState();
}

class _FollowUpState extends ConsumerState<FollowUpScreen> {
  int _days = 60;

  Future<void> _editReason(Partner p) async {
    final ctrl = TextEditingController(text: p.followUpReason ?? '');
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reason for ${p.fullName}'),
        content: SizedBox(
          width: 420,
          child: SelField(
            controller: ctrl,
            hint: 'Called 12 Oct, travelling',
            autofocus: true,
            onSubmitted: (_) => Navigator.pop(context, true),
          ),
        ),
        actions: [
          SelButton(
            label: 'Cancel',
            kind: SelButtonKind.quiet,
            onPressed: () => Navigator.pop(context, false),
          ),
          SelButton.cyan(
            label: 'Save',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (save != true || idx == null) return;
    await ref
        .read(partnersRepositoryProvider)
        .setFollowUpReason(
          churchId: idx.churchId,
          partnerId: p.id,
          reason: ctrl.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(givingViewProvider);
    final roster = ref.watch(partnersStreamProvider(false));
    final lastOf = {for (final p in view.partners) p.partnerId: p.lastGave};
    final cutoff = DateTime.now().subtract(Duration(days: _days));
    final quiet =
        (roster.valueOrNull ?? const <Partner>[]).where((p) {
          if (!p.isActive) return false;
          final last = lastOf[p.id];
          return last == null || last.isBefore(cutoff);
        }).toList()..sort((a, b) {
          final la = lastOf[a.id], lb = lastOf[b.id];
          if (la == null) return lb == null ? 0 : 1;
          if (lb == null) return -1;
          return la.compareTo(lb);
        });
    final phones = [
      for (final p in quiet)
        if (p.allPhones.isNotEmpty) '${p.fullName}: ${p.allPhones.first}',
    ];

    return SelPageBody(
      children: [
        SelPageTitle(
          title: 'Follow up',
          subtitle: "Partners who haven't given in ${_days == 180 ? '6 months' : '$_days days'}",
          actions: [
            SelButton(
              label: 'Copy phone numbers',
              onPressed: phones.isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(ClipboardData(text: phones.join('\n')));
                      if (context.mounted) {
                        selNotice(
                          context,
                          'Copied ${phones.length} ${phones.length == 1 ? 'number' : 'numbers'}.',
                        );
                      }
                    },
            ),
          ],
        ),
        SelPillGroup<int>(
          selected: _days,
          onChanged: (v) => setState(() => _days = v),
          options: const [(60, '60 days'), (90, '90 days'), (180, '6 months')],
        ),
        const SizedBox(height: SelSpace.x4),
        roster.when(
          loading: () => const ViewLoading(),
          error: (e, _) => SelError(message: '$e'),
          data: (_) => SelLedger(
            minWidth: 760,
            columns: const [
              SelColumn('Partner', flex: 3),
              SelColumn('Fellowship', flex: 2),
              SelColumn('Last gave', fit: SelColFit.fixed, width: 140),
              SelColumn.numeric('Phone', width: 110),
              SelColumn('Reason', flex: 3),
            ],
            emptyState: const SelEmpty(
              title: 'Everyone has given recently',
              message: 'Nobody needs a call right now.',
              icon: LucideIcons.phoneCall,
            ),
            rows: [
              for (final p in quiet)
                SelRow(
                  onTap: () => context.go('/partners/${p.id}'),
                  cells: [
                    SelCell.primary(p.fullName),
                    SelCell.secondary(p.fellowship),
                    SelCell.secondary(
                      lastOf[p.id] == null ? 'Not yet' : gaveOnMonth(lastOf[p.id]!),
                    ),
                    SelCell.numeric(_phoneEnd(p), strong: false),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: p.followUpReason?.trim().isNotEmpty == true
                          ? InkWell(
                              borderRadius: BorderRadius.circular(SelRadius.pill),
                              onTap: () => _editReason(p),
                              child: _tag(p.followUpReason!.trim()),
                            )
                          : SelLink(
                              label: 'Add a reason',
                              onTap: () => _editReason(p),
                            ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
