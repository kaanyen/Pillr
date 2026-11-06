import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/extensions/async_value_ext.dart';
import '../../design/seline.dart';
import '../../features/periods/providers/periods_providers.dart';
import '../../features/entries/providers/entries_providers.dart';
import '../../features/entries/domain/partnership_entry.dart';
import '../../features/arms/providers/arms_providers.dart';
import '../../features/arms/domain/partnership_arm.dart';
import '../../features/church/providers/church_settings_providers.dart';
import '../../features/leaderboard/giving_view.dart';
import 'view_common.dart';

/// Records · By arm, as on the canvas: a card for each of the biggest arms
/// with its year in month bars (the best month in navy), the arm's best month
/// against its usual, and a table of every arm with its share of the year.
/// The month-by-month figures stay below for anyone who needs them.
class RecordsByArmScreen extends ConsumerWidget {
  const RecordsByArmScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(churchMoneyFormatProvider);
    final view = ref.watch(givingViewProvider);
    final loading = ref.watch(givingViewLoadingProvider);
    final period = ref.watch(activePeriodProvider);
    final tree = ref.watch(armTreeProvider);
    final pending =
        ref.watch(pendingEntriesProvider).valueOrNull ??
        const <PartnershipEntry>[];
    final waiting = <String, double>{};
    for (final e in pending) {
      final id = tree.shownArmIdOf(e.partnershipArmId);
      waiting[id] = (waiting[id] ?? 0) + e.amountCedis;
    }
    final arms = [...view.arms]
      ..sort((a, b) => view.armTotal(b.id).compareTo(view.armTotal(a.id)));
    double inMonth(String arm, int m) => view.armByMonth[m]?[arm] ?? 0;
    int? bestMonth(String arm) {
      int? best;
      for (final m in view.months) {
        if (inMonth(arm, m) > 0 &&
            (best == null || inMonth(arm, m) > inMonth(arm, best))) {
          best = m;
        }
      }
      return best;
    }

    double usual(String arm) {
      final given = [
        for (final m in view.months)
          if (inMonth(arm, m) > 0) inMonth(arm, m),
      ];
      return given.isEmpty ? 0 : given.reduce((x, y) => x + y) / given.length;
    }

    String pct(double v) => view.total == 0
        ? '0%'
        : '${(100 * v / view.total).toStringAsFixed(1)}% of the year';

    // The arm whose best month stood out most from its usual month.
    String? standout;
    var lift = 1.2;
    for (final a in arms) {
      final m = bestMonth(a.id);
      final u = usual(a.id);
      if (m == null || u == 0) continue;
      final r = inMonth(a.id, m) / u;
      if (r > lift) {
        lift = r;
        standout = a.id;
      }
    }
    final allPartners = view.partners.length;
    final totalWaiting = waiting.values.fold<double>(0, (s, v) => s + v);

    Widget armCard(PartnershipArm a) {
      final best = bestMonth(a.id);
      final peak = [
        for (final m in view.months) inMonth(a.id, m),
        1.0,
      ].reduce((x, y) => x > y ? x : y);
      final gave = view.partners.where((p) => (p.byArm[a.id] ?? 0) > 0).length;
      Widget fig(String k, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: SelType.small),
          Text(
            v,
            style: SelType.bodyMedium.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      );
      return SelCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(a.name, style: SelType.subtitle)),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Sel.track,
                    borderRadius: BorderRadius.circular(SelRadius.pill),
                  ),
                  child: Text(
                    pct(view.armTotal(a.id)),
                    style: SelType.small.copyWith(color: Sel.text),
                  ),
                ),
              ],
            ),
            const SizedBox(height: SelSpace.x3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                money(view.armTotal(a.id)),
                style: SelType.hero.copyWith(fontSize: 28),
              ),
            ),
            const SizedBox(height: SelSpace.x3),
            SizedBox(
              height: 46,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final m in view.months)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: Container(
                          height: inMonth(a.id, m) == 0
                              ? 2
                              : (44 * inMonth(a.id, m) / peak)
                                    .clamp(4, 44)
                                    .toDouble(),
                          color: m == best ? Sel.ink : Sel.skyWash,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (view.months.isNotEmpty) ...[
              const SizedBox(height: SelSpace.x2),
              Row(
                children: [
                  Text(monthShort(view.months.first), style: SelType.small),
                  const Spacer(),
                  Text(monthShort(view.months.last), style: SelType.small),
                ],
              ),
            ],
            const Divider(height: SelSpace.x6, color: Sel.border),
            Wrap(
              spacing: SelSpace.x6,
              runSpacing: SelSpace.x2,
              children: [
                fig('Entries', '${view.armEntries[a.id] ?? 0}'),
                fig('Partners', '$gave of $allPartners'),
                fig('Waiting', money(waiting[a.id] ?? 0)),
              ],
            ),
          ],
        ),
      );
    }

    final top = arms.take(3).toList();
    final sa = standout == null
        ? null
        : arms.firstWhere((a) => a.id == standout);
    final sm = sa == null ? null : bestMonth(sa.id);
    final monthName = sm == null
        ? ''
        : DateFormat.MMMM().format(GivingView.monthOf(sm));

    return SelPageBody(
      children: [
        SelPageTitle(
          title: 'By arm',
          subtitle:
              '${period?.name ?? 'This period'} · approved giving, counted by the date it was given',
        ),
        if (loading)
          const ViewLoading()
        else if (arms.isEmpty)
          const SelCard(
            child: SelEmpty(
              title: 'No arms yet',
              message: 'Add arms in Configuration to see giving split here.',
            ),
          )
        else ...[
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth < 700 ? 1 : top.length;
              final w = (c.maxWidth - SelSpace.x4 * (cols - 1)) / cols;
              return Wrap(
                spacing: SelSpace.x4,
                runSpacing: SelSpace.x4,
                children: [
                  for (final a in top) SizedBox(width: w, child: armCard(a)),
                ],
              );
            },
          ),
          if (sa != null && sm != null) ...[
            const SizedBox(height: SelSpace.x4),
            SelCard(
              child: Wrap(
                spacing: SelSpace.x4,
                runSpacing: SelSpace.x3,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${sa.name} had its biggest month in $monthName',
                        style: SelType.subtitle,
                      ),
                      const SizedBox(height: SelSpace.x1),
                      Text(
                        '${money(inMonth(sa.id, sm))} against a usual ${money(usual(sa.id))}.',
                        style: SelType.bodySm,
                      ),
                    ],
                  ),
                  SelButton(
                    label: 'See it month by month',
                    onPressed: () => context.go('/records/monthly'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: SelSpace.x4),
          SelLedger(
            minWidth: 820,
            columns: const [
              SelColumn('Arm', flex: 2),
              SelColumn('Share of the year', flex: 3),
              SelColumn.numeric('Approved', width: 150),
              SelColumn.numeric('Average entry', width: 130),
              SelColumn.numeric('Best month', width: 120),
              SelColumn.numeric('Waiting', width: 130),
            ],
            rows: [
              for (final a in arms)
                SelRow(
                  cells: [
                    SelCell.primary(a.name),
                    Padding(
                      padding: const EdgeInsets.only(right: SelSpace.x6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: view.total == 0
                              ? 0
                              : view.armTotal(a.id) / view.total,
                          minHeight: 8,
                          color: Sel.sky,
                          backgroundColor: Sel.track,
                        ),
                      ),
                    ),
                    SelCell.numeric(money(view.armTotal(a.id))),
                    SelCell.numeric(
                      money(
                        (view.armEntries[a.id] ?? 0) == 0
                            ? 0
                            : view.armTotal(a.id) / view.armEntries[a.id]!,
                      ),
                      strong: false,
                    ),
                    SelCell.numeric(
                      bestMonth(a.id) == null
                          ? '—'
                          : DateFormat.MMMM().format(
                              GivingView.monthOf(bestMonth(a.id)!),
                            ),
                      strong: false,
                    ),
                    SelCell.numeric(money(waiting[a.id] ?? 0), strong: false),
                  ],
                ),
              SelRow(
                cells: [
                  SelCell.primary('All arms'),
                  const SizedBox.shrink(),
                  SelCell.numeric(money(view.total)),
                  SelCell.numeric(
                    money(
                      view.entryCount == 0 ? 0 : view.total / view.entryCount,
                    ),
                    strong: false,
                  ),
                  SelCell.numeric(
                    view.months.isEmpty
                        ? '—'
                        : DateFormat.MMMM().format(
                            GivingView.monthOf(
                              view.months.reduce(
                                (x, y) =>
                                    view.monthTotal(x) >= view.monthTotal(y)
                                    ? x
                                    : y,
                              ),
                            ),
                          ),
                    strong: false,
                  ),
                  SelCell.numeric(money(totalWaiting), strong: false),
                ],
              ),
            ],
          ),
          const SizedBox(height: SelSpace.x6),
          const SelSectionLabel(label: 'Month by month'),
          SelLedger(
            minWidth: 160.0 + arms.length * 140 + 150,
            columns: [
              const SelColumn('Month', flex: 2),
              for (final a in arms) SelColumn.numeric(a.name, width: 140),
              const SelColumn.numeric('All arms', width: 150),
            ],
            rows: [
              for (final m in view.months)
                SelRow(
                  cells: [
                    SelCell.primary(monthLong(m)),
                    for (final a in arms)
                      SelCell.numeric(money(inMonth(a.id, m)), strong: false),
                    SelCell.numeric(money(view.monthTotal(m))),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}

enum _FellowshipSort { biggest, name }

/// Records · By fellowship: one row per fellowship, so it reads the same with
/// four fellowships or fifty. Find, sort and pick the month to compare.
class RecordsByFellowshipScreen extends ConsumerStatefulWidget {
  const RecordsByFellowshipScreen({super.key});

  @override
  ConsumerState<RecordsByFellowshipScreen> createState() =>
      _RecordsByFellowshipState();
}

class _RecordsByFellowshipState
    extends ConsumerState<RecordsByFellowshipScreen> {
  String _query = '';
  int? _month;
  _FellowshipSort _sort = _FellowshipSort.biggest;

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(churchMoneyFormatProvider);
    final view = ref.watch(givingViewProvider);
    final loading = ref.watch(givingViewLoadingProvider);
    final now = GivingView.monthKey(DateTime.now());
    // The latest month that has giving in it, not an empty month just begun.
    final given = [
      for (final m in view.months)
        if (m <= now && view.monthTotal(m) > 0) m,
    ];
    final month =
        _month ??
        (given.isNotEmpty
            ? given.last
            : (view.months.isEmpty ? now : view.months.last));
    final period = ref.watch(activePeriodProvider);

    final rows = view.fellowships
        .where((f) => _query.isEmpty || f.name.toLowerCase().contains(_query))
        .toList();
    if (_sort == _FellowshipSort.name) {
      rows.sort((a, b) => a.name.compareTo(b.name));
    }

    return SelPageBody(
      children: [
        SelPageTitle(
          title: 'By fellowship',
          subtitle:
              '${view.fellowships.length} fellowships · ${period?.name ?? 'this period'} · approved giving',
        ),
        SelCard(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: SelSpace.x3,
                runSpacing: SelSpace.x3,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ViewSearch(
                    hint: 'Find a fellowship',
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  if (view.months.isNotEmpty)
                    DropdownButton<int>(
                      value: view.months.contains(month)
                          ? month
                          : view.months.last,
                      underline: const SizedBox.shrink(),
                      borderRadius: BorderRadius.circular(SelRadius.card),
                      items: [
                        for (final m in view.months.reversed)
                          DropdownMenuItem(
                            value: m,
                            child: Text(
                              'Month: ${monthLong(m)}',
                              style: SelType.bodySm.copyWith(color: Sel.text),
                            ),
                          ),
                      ],
                      onChanged: (m) => setState(() => _month = m),
                    ),
                  SelPillGroup<_FellowshipSort>(
                    selected: _sort,
                    onChanged: (v) => setState(() => _sort = v),
                    options: const [
                      (_FellowshipSort.biggest, 'Biggest first'),
                      (_FellowshipSort.name, 'A to Z'),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: SelSpace.x3),
              if (loading)
                const ViewLoading()
              else
                SelLedger.builder(
                  bare: true,
                  minWidth: 680,
                  maxVirtualHeight: 720,
                  columns: [
                    const SelColumn('Fellowship', flex: 3),
                    const SelColumn.numeric('Partners', width: 100),
                    const SelColumn.numeric('Gave this period', width: 150),
                    SelColumn.numeric(monthShort(month), width: 140),
                    const SelColumn.numeric('Year so far', width: 160),
                  ],
                  emptyState: SelEmpty(
                    title: _query.isEmpty ? 'No fellowships yet' : 'No matches',
                    message: _query.isEmpty
                        ? 'Fellowships appear once partners belong to one.'
                        : 'No fellowship matches “$_query”.',
                    icon: LucideIcons.users2,
                  ),
                  itemCount: rows.isEmpty ? 0 : rows.length + 1,
                  itemBuilder: (context, i) {
                    if (i == rows.length) {
                      final partners = rows.fold<int>(
                        0,
                        (s, f) => s + f.partners,
                      );
                      final gave = rows.fold<int>(
                        0,
                        (s, f) => s + f.gave.length,
                      );
                      return SelRow(
                        cells: [
                          SelCell.primary('All ${rows.length}'),
                          SelCell.numeric('$partners'),
                          SelCell.numeric('$gave of $partners'),
                          SelCell.numeric(
                            money(
                              rows.fold<double>(
                                0,
                                (s, f) => s + (f.byMonth[month] ?? 0),
                              ),
                            ),
                          ),
                          SelCell.numeric(
                            money(rows.fold<double>(0, (s, f) => s + f.total)),
                          ),
                        ],
                      );
                    }
                    final f = rows[i];
                    return SelRow(
                      onTap: () => context.go(
                        '/fellowships/${Uri.encodeComponent(f.key)}',
                      ),
                      cells: [
                        SelCell.primary(f.name),
                        SelCell.numeric('${f.partners}', strong: false),
                        SelCell.numeric(
                          '${f.gave.length} of ${f.partners}',
                          strong: false,
                        ),
                        SelCell.numeric(
                          money(f.byMonth[month] ?? 0),
                          strong: false,
                        ),
                        SelCell.numeric(money(f.total)),
                      ],
                    );
                  },
                ),
              const SizedBox(height: SelSpace.x3),
              Text(
                'Showing ${rows.length} of ${view.fellowships.length}',
                style: SelType.small,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Records · By partner, as on the canvas: each partner's approved giving
/// month by month, shaded by size so the steady givers and the gaps show at a
/// glance. Sorted by most given, name or months given; 25 a page.
class RecordsByPartnerScreen extends ConsumerStatefulWidget {
  const RecordsByPartnerScreen({super.key});

  @override
  ConsumerState<RecordsByPartnerScreen> createState() =>
      _RecordsByPartnerState();
}

enum _PartnerSort { most, name, months }

class _RecordsByPartnerState extends ConsumerState<RecordsByPartnerScreen> {
  static const _page = 25;
  String _query = '';
  _PartnerSort _sort = _PartnerSort.most;
  int _start = 0;

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(churchMoneyFormatProvider);
    final symbol = money(0).replaceAll(RegExp(r'[0-9.,\s]'), '');
    // Short enough for a month cell: ₵840, ₵1.3k, ₵15k, ₵2.9M.
    String compact(double v) {
      String trim(double x) {
        final t = x >= 10 ? x.round().toString() : x.toStringAsFixed(1);
        return t.endsWith('.0') ? t.substring(0, t.length - 2) : t;
      }

      if (v >= 1e6) return '$symbol${trim(v / 1e6)}M';
      if (v >= 1e3) return '$symbol${trim(v / 1e3)}k';
      return '$symbol${v.round()}';
    }
    final view = ref.watch(givingViewProvider);
    final loading = ref.watch(givingViewLoadingProvider);
    final period = ref.watch(activePeriodProvider);
    int monthsGiven(PartnerGiving p) =>
        p.byMonth.values.where((v) => v > 0).length;
    final rows = view.partners
        .where(
          (p) =>
              _query.isEmpty ||
              p.name.toLowerCase().contains(_query) ||
              p.fellowshipKey.contains(_query),
        )
        .toList();
    switch (_sort) {
      case _PartnerSort.most:
        break; // already biggest first
      case _PartnerSort.name:
        rows.sort((a, b) => a.name.compareTo(b.name));
      case _PartnerSort.months:
        rows.sort((a, b) => monthsGiven(b).compareTo(monthsGiven(a)));
    }
    final start = _start >= rows.length ? 0 : _start;
    final shown = rows.skip(start).take(_page).toList();
    final peak = [
      for (final p in view.partners) ...p.byMonth.values,
      1.0,
    ].reduce((x, y) => x > y ? x : y);
    final now = GivingView.monthKey(DateTime.now());

    Color shade(double v) {
      if (v <= 0) return Colors.transparent;
      final t = (v / peak).clamp(0.0, 1.0);
      // From a faint sky tint to the light sky of the bars, by square root so
      // smaller givers still read.
      return Color.lerp(
        const Color(0xFFE6F2FD),
        const Color(0xFF7FC0F6),
        math.sqrt(t),
      )!;
    }

    Widget pill(_PartnerSort k, String label) => Padding(
      padding: const EdgeInsets.only(left: SelSpace.x2),
      child: Material(
        color: _sort == k ? Sel.ink : Sel.card,
        shape: StadiumBorder(
          side: BorderSide(color: _sort == k ? Sel.ink : Sel.border),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => setState(() {
            _sort = k;
            _start = 0;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              label,
              style: SelType.bodySm.copyWith(
                color: _sort == k ? Sel.card : Sel.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );

    const nameW = 160.0, yearW = 150.0;
    Widget head(String t, double w, {TextAlign align = TextAlign.right}) =>
        SizedBox(
          width: w,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Text(t, textAlign: align, style: SelType.small),
          ),
        );

    Widget tableFor(double cellW) => SizedBox(
      width: nameW + yearW + view.months.length * cellW,
      child: Column(
        children: [
          Row(
            children: [
              head('Partner', nameW, align: TextAlign.left),
              for (final m in view.months) head(monthShort(m), cellW),
              head('Year', yearW),
            ],
          ),
          const Divider(height: 1, color: Sel.rowLine),
          for (final p in shown) ...[
            InkWell(
              onTap: () => context.go('/partners/${p.partnerId}'),
              child: SizedBox(
                height: 56,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: nameW,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              overflow: TextOverflow.ellipsis,
                              style: SelType.bodySm.copyWith(color: Sel.text),
                            ),
                            Text(p.fellowship, style: SelType.small),
                          ],
                        ),
                      ),
                    ),
                    for (final m in view.months)
                      Container(
                        width: cellW,
                        margin: const EdgeInsets.only(right: 1),
                        color: shade(p.byMonth[m] ?? 0),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          (p.byMonth[m] ?? 0) > 0
                              ? compact(p.byMonth[m]!)
                              : m > now
                              ? '·'
                              : '–',
                          style: SelType.small.copyWith(
                            color: (p.byMonth[m] ?? 0) > 0 ? Sel.ink : Sel.warm,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    SizedBox(
                      width: yearW - view.months.length.toDouble(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            money(p.total),
                            style: SelType.bodySm.copyWith(
                              color: Sel.ink,
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: Sel.rowLine),
          ],
        ],
      ),
    );

    return SelPageBody(
      children: [
        SelPageTitle(
          title: 'By partner',
          subtitle:
              "${period?.name ?? 'This period'} · each partner's approved giving, month by month",
        ),
        if (loading)
          const ViewLoading()
        else
          SelCard(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  runSpacing: SelSpace.x2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    SizedBox(
                      width: 320,
                      child: ViewSearch(
                        hint: 'Find a partner or fellowship',
                        onChanged: (v) => setState(() {
                          _query = v;
                          _start = 0;
                        }),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Sort', style: SelType.small),
                        pill(_PartnerSort.most, 'Most given'),
                        pill(_PartnerSort.name, 'Name'),
                        pill(_PartnerSort.months, 'Months given'),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: SelSpace.x3),
                if (rows.isEmpty)
                  SelEmpty(
                    title: _query.isEmpty ? 'Nobody has given yet' : 'No matches',
                    message: _query.isEmpty
                        ? 'Partners appear here once their giving is approved.'
                        : 'No partner or fellowship matches “$_query”.',
                  )
                else
                  LayoutBuilder(
                    builder: (context, c) {
                      final fit = view.months.isEmpty
                          ? 70.0
                          : (c.maxWidth - nameW - yearW) / view.months.length;
                      // Months share the width; below 58 a cell cannot hold
                      // ₵12.3k, so the table scrolls sideways instead.
                      return fit >= 58
                          ? tableFor(fit.clamp(58.0, 96.0))
                          : SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: tableFor(58),
                            );
                    },
                  ),
                const SizedBox(height: SelSpace.x3),
                Wrap(
                  runSpacing: SelSpace.x2,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Less ', style: SelType.small),
                        for (final t in const [0.02, 0.1, 0.3, 0.6, 1.0])
                          Container(
                            width: 18,
                            height: 10,
                            margin: const EdgeInsets.only(right: 2),
                            color: shade(t * peak),
                          ),
                        Text(' More · – nothing given', style: SelType.small),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          rows.isEmpty
                              ? ''
                              : '${start + 1}–${start + shown.length} of ${rows.length} who gave',
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
                        if (start + _page < rows.length) ...[
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
              ],
            ),
          ),
      ],
    );
  }
}
