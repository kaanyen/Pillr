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
        ref.watch(pendingEntriesProvider).valueOrNull ?? const <PartnershipEntry>[];
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
        if (inMonth(arm, m) > 0 && (best == null || inMonth(arm, m) > inMonth(arm, best))) {
          best = m;
        }
      }
      return best;
    }

    double usual(String arm) {
      final given = [for (final m in view.months) if (inMonth(arm, m) > 0) inMonth(arm, m)];
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
      final peak = [for (final m in view.months) inMonth(a.id, m), 1.0].reduce((x, y) => x > y ? x : y);
      final gave = view.partners.where((p) => (p.byArm[a.id] ?? 0) > 0).length;
      Widget fig(String k, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: SelType.small),
          Text(v, style: SelType.bodyMedium.copyWith(fontWeight: FontWeight.w800)),
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Sel.track,
                    borderRadius: BorderRadius.circular(SelRadius.pill),
                  ),
                  child: Text(pct(view.armTotal(a.id)), style: SelType.small.copyWith(color: Sel.text)),
                ),
              ],
            ),
            const SizedBox(height: SelSpace.x3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(money(view.armTotal(a.id)), style: SelType.hero.copyWith(fontSize: 28)),
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
                          height: inMonth(a.id, m) == 0 ? 2 : (44 * inMonth(a.id, m) / peak).clamp(4, 44).toDouble(),
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
    final sa = standout == null ? null : arms.firstWhere((a) => a.id == standout);
    final sm = sa == null ? null : bestMonth(sa.id);
    final monthName = sm == null ? '' : DateFormat.MMMM().format(GivingView.monthOf(sm));

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
                children: [for (final a in top) SizedBox(width: w, child: armCard(a))],
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
                      Text('${sa.name} had its biggest month in $monthName', style: SelType.subtitle),
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
                          value: view.total == 0 ? 0 : view.armTotal(a.id) / view.total,
                          minHeight: 8,
                          color: Sel.sky,
                          backgroundColor: Sel.track,
                        ),
                      ),
                    ),
                    SelCell.numeric(money(view.armTotal(a.id))),
                    SelCell.numeric(
                      money((view.armEntries[a.id] ?? 0) == 0 ? 0 : view.armTotal(a.id) / view.armEntries[a.id]!),
                      strong: false,
                    ),
                    SelCell.numeric(
                      bestMonth(a.id) == null ? '—' : DateFormat.MMMM().format(GivingView.monthOf(bestMonth(a.id)!)),
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
                    money(view.entryCount == 0 ? 0 : view.total / view.entryCount),
                    strong: false,
                  ),
                  SelCell.numeric(
                    view.months.isEmpty
                        ? '—'
                        : DateFormat.MMMM().format(GivingView.monthOf(
                            view.months.reduce((x, y) => view.monthTotal(x) >= view.monthTotal(y) ? x : y),
                          )),
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
    final month =
        _month ??
        (view.months.contains(now)
            ? now
            : (view.months.isEmpty ? now : view.months.last));

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
              '${view.fellowships.length} fellowships · approved giving in this period',
        ),
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
                value: view.months.contains(month) ? month : view.months.last,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(SelRadius.card),
                items: [
                  for (final m in view.months.reversed)
                    DropdownMenuItem(value: m, child: Text(monthLong(m))),
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
        const SizedBox(height: SelSpace.x4),
        if (loading)
          const ViewLoading()
        else
          SelLedger.builder(
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
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final f = rows[i];
              return SelRow(
                onTap: () =>
                    context.go('/fellowships/${Uri.encodeComponent(f.key)}'),
                cells: [
                  SelCell.primary(f.name),
                  SelCell.numeric('${f.partners}', strong: false),
                  SelCell.numeric(
                    '${f.gave.length} of ${f.partners}',
                    strong: false,
                  ),
                  SelCell.numeric(money(f.byMonth[month] ?? 0), strong: false),
                  SelCell.numeric(money(f.total)),
                ],
              );
            },
          ),
      ],
    );
  }
}

/// Records · By partner: each partner's year, split by main arm.
class RecordsByPartnerScreen extends ConsumerStatefulWidget {
  const RecordsByPartnerScreen({super.key});

  @override
  ConsumerState<RecordsByPartnerScreen> createState() =>
      _RecordsByPartnerState();
}

class _RecordsByPartnerState extends ConsumerState<RecordsByPartnerScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(churchMoneyFormatProvider);
    final view = ref.watch(givingViewProvider);
    final loading = ref.watch(givingViewLoadingProvider);
    final rows = view.partners
        .where(
          (p) =>
              _query.isEmpty ||
              p.name.toLowerCase().contains(_query) ||
              p.fellowshipKey.contains(_query),
        )
        .toList();

    return SelPageBody(
      children: [
        SelPageTitle(
          title: 'By partner',
          subtitle:
              '${view.partners.length} partners gave in this period · biggest first',
        ),
        ViewSearch(
          hint: 'Find a partner or fellowship',
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: SelSpace.x4),
        if (loading)
          const ViewLoading()
        else
          SelLedger.builder(
            minWidth: 360.0 + view.arms.length * 130 + 150,
            maxVirtualHeight: 720,
            columns: [
              const SelColumn('Partner', flex: 3),
              const SelColumn('Fellowship', flex: 2),
              for (final a in view.arms) SelColumn.numeric(a.name, width: 130),
              const SelColumn.numeric('Total', width: 150),
            ],
            emptyState: SelEmpty(
              title: _query.isEmpty ? 'No giving yet' : 'No matches',
              message: _query.isEmpty
                  ? 'Partners appear here once their giving is approved.'
                  : 'Nothing matches “$_query”.',
            ),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final p = rows[i];
              return SelRow(
                onTap: () => context.go('/partners/${p.partnerId}'),
                cells: [
                  SelCell.primary(p.name),
                  SelCell.secondary(p.fellowship),
                  for (final a in view.arms)
                    SelCell.numeric(
                      (p.byArm[a.id] ?? 0) == 0 ? '–' : money(p.byArm[a.id]!),
                      strong: false,
                    ),
                  SelCell.numeric(money(p.total)),
                ],
              );
            },
          ),
      ],
    );
  }
}
