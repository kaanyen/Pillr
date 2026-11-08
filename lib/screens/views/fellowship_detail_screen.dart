import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/extensions/async_value_ext.dart';
import '../../design/seline.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/periods/providers/periods_providers.dart';
import '../../features/church/providers/church_settings_providers.dart';
import '../../features/leaderboard/giving_view.dart';
import '../../features/partners/domain/partner.dart';
import '../../features/partners/providers/partners_providers.dart';
import 'view_common.dart';

enum FellowshipTab { overview, people, arms, months }

/// One fellowship: Overview, People, Arms and Month by month, as tabs on the
/// same page. Reached from Fellowships, By fellowship and Search.
class FellowshipDetailScreen extends ConsumerStatefulWidget {
  const FellowshipDetailScreen({
    super.key,
    required this.fellowshipKey,
    this.initialTab,
  });

  /// Lower-cased fellowship name, the key every giving view groups by.
  final String fellowshipKey;
  final String? initialTab;

  @override
  ConsumerState<FellowshipDetailScreen> createState() =>
      _FellowshipDetailState();
}

class _FellowshipDetailState extends ConsumerState<FellowshipDetailScreen> {
  late FellowshipTab _tab = FellowshipTab.values.firstWhere(
    (t) => t.name == widget.initialTab,
    orElse: () => FellowshipTab.overview,
  );
  String _query = '';
  final Set<String> _openArms = {};

  // A link to another tab of the page already open (from Search, say) comes
  // in as a new widget on the same state; follow it.
  @override
  void didUpdateWidget(FellowshipDetailScreen old) {
    super.didUpdateWidget(old);
    if (widget.initialTab != old.initialTab) {
      _tab = FellowshipTab.values.firstWhere(
        (t) => t.name == widget.initialTab,
        orElse: () => FellowshipTab.overview,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(churchMoneyFormatProvider);
    final view = ref.watch(givingViewProvider);
    final loading = ref.watch(givingViewLoadingProvider);
    final roster =
        ref.watch(visiblePartnersProvider(false)).valueOrNull ?? const [];
    final key = widget.fellowshipKey;
    final f = view.fellowship(key);
    final members = roster
        .where((p) => p.fellowship.trim().toLowerCase() == key)
        .toList();
    final giving = {
      for (final p in view.partners)
        if (p.fellowshipKey == key) p.partnerId: p,
    };
    final name = f?.name ?? (members.isEmpty ? key : members.first.fellowship);

    return SelPageBody(
      children: [
        SelBreadcrumb([
          ('Fellowships', () => context.go('/fellowships')),
          (name, null),
        ]),
        const SizedBox(height: SelSpace.x3),
        SelPageTitle(
          title: name,
          subtitle:
              '${members.length} partners · ${ref.watch(activePeriodProvider)?.name ?? 'this period'}',
        ),
        SelTrackTabs<FellowshipTab>(
          selected: _tab,
          onSelect: (t) => setState(() => _tab = t),
          tabs: const [
            (FellowshipTab.overview, 'Overview'),
            (FellowshipTab.people, 'People'),
            (FellowshipTab.arms, 'Arms'),
            (FellowshipTab.months, 'Month by month'),
          ],
        ),
        const SizedBox(height: SelSpace.x4),
        if (loading)
          const ViewLoading()
        else
          switch (_tab) {
            FellowshipTab.overview => _overview(view, f, members, money),
            FellowshipTab.people => _people(members, giving, money),
            FellowshipTab.arms => _arms(view, f, giving, members, money),
            FellowshipTab.months => _months(view, f, money, name),
          },
      ],
    );
  }

  Widget _overview(
    GivingView view,
    FellowshipGiving? f,
    List<Partner> members,
    String Function(num) money,
  ) {
    final top = view.partners
        .where((p) => p.fellowshipKey == widget.fellowshipKey)
        .take(5)
        .toList();
    final n = view.fellowships.length;
    final ranks = ref.watch(canSeeRanksProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelStatRow(
          stats: [
            SelStat(label: 'Given this period', value: money(f?.total ?? 0)),
            SelStat(
              label: 'Partners who gave',
              value: '${f?.gave.length ?? 0} of ${members.length}',
            ),
            if (ranks)
              SelStat(
                label: 'Place among fellowships',
                value: f == null
                    ? '–'
                    : '${ordinal(view.placeOf(widget.fellowshipKey))} of $n',
              ),
          ],
        ),
        const SizedBox(height: SelSpace.x4),
        LayoutBuilder(
          builder: (context, c) {
            Widget line(
              String label,
              String value, {
              String? place,
              VoidCallback? onTap,
            }) => InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: SelType.body.copyWith(color: Sel.text),
                      ),
                    ),
                    Text(
                      value,
                      style: SelType.bodyMedium.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (place != null) ...[
                      const SizedBox(width: SelSpace.x2),
                      Text(place, style: SelType.small),
                    ],
                  ],
                ),
              ),
            );
            Widget card(
              String title,
              Widget link,
              List<Widget> lines,
              Widget empty,
            ) => SelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(title, style: SelType.subtitle)),
                      link,
                    ],
                  ),
                  const SizedBox(height: SelSpace.x1),
                  if (lines.isEmpty) empty,
                  for (var i = 0; i < lines.length; i++) ...[
                    if (i > 0) const Divider(height: 1, color: Sel.rowLine),
                    lines[i],
                  ],
                ],
              ),
            );
            final arms =
                [
                  for (final a in view.arms)
                    if ((f?.byArm[a.id] ?? 0) > 0) a,
                ]..sort(
                  (x, y) => (f!.byArm[y.id] ?? 0).compareTo(f.byArm[x.id] ?? 0),
                );
            final armCard = card(
              'Arms',
              SelLink(
                label: 'See by person',
                onTap: () => setState(() => _tab = FellowshipTab.arms),
              ),
              [
                for (final a in arms)
                  line(
                    a.name,
                    money(f?.byArm[a.id] ?? 0),
                    place: ranks
                        ? '${ordinal(view.placeOf(widget.fellowshipKey, armId: a.id))} of $n'
                        : null,
                  ),
              ],
              Text('No approved giving yet.', style: SelType.bodySm),
            );
            final topCard = card(
              'Gave the most',
              SelLink(
                label: 'All ${members.length} people',
                onTap: () => setState(() => _tab = FellowshipTab.people),
              ),
              [
                for (final p in top)
                  line(
                    p.name,
                    money(p.total),
                    onTap: () => context.go('/partners/${p.partnerId}'),
                  ),
              ],
              Text(
                'Approved giving from this fellowship shows here.',
                style: SelType.bodySm,
              ),
            );
            // Staff see what they recorded, not who gave the most.
            if (!ranks) return armCard;
            if (c.maxWidth < 760) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  armCard,
                  const SizedBox(height: SelSpace.x4),
                  topCard,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: armCard),
                const SizedBox(width: SelSpace.x4),
                Expanded(child: topCard),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _people(
    List<Partner> members,
    Map<String, PartnerGiving> giving,
    String Function(num) money,
  ) {
    final rows =
        members
            .where(
              (p) =>
                  _query.isEmpty ||
                  p.fullName.toLowerCase().contains(_query) ||
                  (p.phone ?? '').contains(_query),
            )
            .toList()
          ..sort(
            (a, b) =>
                (giving[b.id]?.total ?? 0).compareTo(giving[a.id]?.total ?? 0),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ViewSearch(
          hint: 'Search by name or phone',
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: SelSpace.x4),
        SelLedger.builder(
          minWidth: 560,
          maxVirtualHeight: 720,
          columns: const [
            SelColumn('Name', flex: 3),
            SelColumn.numeric('Gave this period', width: 160),
            SelColumn('Last gave', fit: SelColFit.fixed, width: 120),
          ],
          emptyState: SelEmpty(
            title: _query.isEmpty ? 'No partners here yet' : 'No matches',
            message: _query.isEmpty
                ? 'Partners in this fellowship show up here.'
                : 'Nothing matches “$_query”.',
          ),
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final p = rows[i];
            final g = giving[p.id];
            return SelRow(
              onTap: () => context.go('/partners/${p.id}'),
              cells: [
                SelCell.primary(p.fullName),
                SelCell.numeric(money(g?.total ?? 0), strong: g != null),
                SelCell.secondary(gaveOn(g?.lastGave)),
              ],
            );
          },
        ),
      ],
    );
  }

  /// One fold per arm, so a church with many arms still reads as a short
  /// list. The first arm starts open.
  Widget _arms(
    GivingView view,
    FellowshipGiving? f,
    Map<String, PartnerGiving> giving,
    List<Partner> members,
    String Function(num) money,
  ) {
    if (_openArms.isEmpty && view.arms.isNotEmpty) {
      _openArms.add(view.arms.first.id);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in view.arms) ...[
          Builder(
            builder: (context) {
              final gave =
                  giving.values.where((p) => (p.byArm[a.id] ?? 0) > 0).toList()
                    ..sort(
                      (x, y) =>
                          (y.byArm[a.id] ?? 0).compareTo(x.byArm[a.id] ?? 0),
                    );
              final open = _openArms.contains(a.id);
              return SelCard(
                padding: EdgeInsets.zero,
                clip: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      button: true,
                      expanded: open,
                      child: InkWell(
                        onTap: () => setState(
                          () => open
                              ? _openArms.remove(a.id)
                              : _openArms.add(a.id),
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 64),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: SelSpace.x4,
                            ),
                            child: Row(
                              children: [
                                AnimatedRotation(
                                  turns: open ? 0.25 : 0,
                                  duration: const Duration(milliseconds: 160),
                                  curve: Curves.easeOutCubic,
                                  child: const Icon(
                                    LucideIcons.chevronRight,
                                    size: 18,
                                    color: Sel.ink,
                                  ),
                                ),
                                const SizedBox(width: SelSpace.x3),
                                Text(a.name, style: SelType.bodyMedium),
                                const SizedBox(width: SelSpace.x2),
                                Text(
                                  '${gave.length} of ${members.length} gave',
                                  style: SelType.small,
                                ),
                                const Spacer(),
                                Text(
                                  money(f?.byArm[a.id] ?? 0),
                                  style: SelType.bodyMedium,
                                ),
                                const SizedBox(width: SelSpace.x3),
                                Text(
                                  f == null || !ref.watch(canSeeRanksProvider)
                                      ? ''
                                      : '${ordinal(view.placeOf(widget.fellowshipKey, armId: a.id))} of ${view.fellowships.length}',
                                  style: SelType.small,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (open)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          SelSpace.x8,
                          0,
                          SelSpace.x4,
                          SelSpace.x3,
                        ),
                        child: SelLedger(
                          bare: true,
                          minWidth: 420,
                          columns: [
                            const SelColumn('Partner', flex: 3),
                            SelColumn.numeric('Gave to ${a.name}', width: 160),
                            const SelColumn(
                              'Last gave',
                              fit: SelColFit.fixed,
                              width: 110,
                            ),
                          ],
                          emptyState: const SelEmpty(
                            title: 'Nobody yet',
                            message: 'No approved giving to this arm yet.',
                          ),
                          rows: [
                            for (final p in gave)
                              SelRow(
                                onTap: () =>
                                    context.go('/partners/${p.partnerId}'),
                                cells: [
                                  SelCell.primary(p.name),
                                  SelCell.numeric(money(p.byArm[a.id] ?? 0)),
                                  SelCell.secondary(gaveOn(p.lastGave)),
                                ],
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: SelSpace.x3),
        ],
      ],
    );
  }

  Widget _months(
    GivingView view,
    FellowshipGiving? f,
    String Function(num) money,
    String name,
  ) {
    final members = view.partners
        .where((p) => p.fellowshipKey == widget.fellowshipKey)
        .toList();
    final roster = f?.partners ?? members.length;
    double cell(int m, String armId) =>
        members.fold(0, (s, p) => s + (p.byArmMonth[m]?[armId] ?? 0));
    final now = GivingView.monthKey(DateTime.now());
    final months = [
      for (final m in view.months)
        if (m <= now) m,
    ];
    // Arms this fellowship gave to, biggest first; the chart stacks them
    // navy, sky, light sky from the bottom, and anything past three is "Other".
    final arms = [
      for (final a in view.arms)
        if ((f?.byArm[a.id] ?? 0) > 0) a,
    ]..sort((x, y) => (f!.byArm[y.id] ?? 0).compareTo(f.byArm[x.id] ?? 0));
    const tones = [Sel.ink, Sel.sky, Sel.skyWash];
    final shown = arms.take(3).toList();
    double other(int m) =>
        (f?.byMonth[m] ?? 0) -
        shown.fold<double>(0, (s, a) => s + cell(m, a.id));
    final peakMonth = months.isEmpty
        ? null
        : months.reduce(
            (x, y) => (f?.byMonth[x] ?? 0) >= (f?.byMonth[y] ?? 0) ? x : y,
          );
    final peak = peakMonth == null
        ? 1.0
        : math.max(1.0, f?.byMonth[peakMonth] ?? 0);
    final cellPeak = [
      for (final m in months)
        for (final a in arms) cell(m, a.id),
      1.0,
    ].reduce(math.max);
    int gaveIn(int m) => members.where((p) => (p.byMonth[m] ?? 0) > 0).length;
    String share(double part, double whole) =>
        whole == 0 ? '–' : '${(100 * part / whole).toStringAsFixed(1)}%';
    Color shade(double v) => v <= 0
        ? Colors.transparent
        : Color.lerp(
            const Color(0xFFE6F2FD),
            const Color(0xFF7FC0F6),
            math.sqrt((v / cellPeak).clamp(0.0, 1.0)),
          )!;

    if (months.isEmpty || f == null) {
      return const SelCard(
        child: SelEmpty(
          title: 'No giving yet',
          message:
              'Approved giving from this fellowship shows here month by month.',
        ),
      );
    }

    final chart = SelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: SelSpace.x2,
            children: [
              Text(
                "${DateFormat.MMMM().format(GivingView.monthOf(peakMonth!))} was $name's biggest month",
                style: SelType.subtitle,
              ),
              Wrap(
                spacing: SelSpace.x3,
                children: [
                  for (var i = 0; i < shown.length; i++)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 10, height: 10, color: tones[i]),
                        const SizedBox(width: 6),
                        Text(shown[i].name, style: SelType.small),
                      ],
                    ),
                  if (arms.length > 3)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 10, height: 10, color: Sel.border),
                        const SizedBox(width: 6),
                        Text('Other arms', style: SelType.small),
                      ],
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: SelSpace.x4),
          SizedBox(
            height: 230,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final m in months)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (arms.length > 3 && other(m) > 0)
                            Container(
                              height: 180 * other(m) / peak,
                              color: Sel.border,
                            ),
                          for (var i = shown.length - 1; i >= 0; i--)
                            if (cell(m, shown[i].id) > 0)
                              Container(
                                height: 180 * cell(m, shown[i].id) / peak,
                                margin: const EdgeInsets.only(top: 2),
                                color: tones[i],
                              ),
                          const SizedBox(height: SelSpace.x2),
                          Text(monthShort(m), style: SelType.small),
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

    TextStyle num0 = SelType.bodySm.copyWith(
      color: Sel.text,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    TextStyle strong = num0.copyWith(
      color: Sel.ink,
      fontWeight: FontWeight.w800,
    );
    Widget c(
      String t, {
      TextStyle? style,
      Color? fill,
      TextAlign align = TextAlign.right,
    }) => Container(
      color: fill,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
      child: Text(t, textAlign: align, style: style ?? num0),
    );
    final yearTotal = months.fold<double>(0, (s, m) => s + view.monthTotal(m));
    final table = SelCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: box.maxWidth),
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              // The month column takes whatever width is left over.
              columnWidths: const {0: IntrinsicColumnWidth(flex: 1)},
              border: const TableBorder(
                horizontalInside: BorderSide(color: Sel.rowLine),
              ),
              children: [
                TableRow(
                  children: [
                    c('Month', style: SelType.small, align: TextAlign.left),
                    for (final a in arms) c(a.name, style: SelType.small),
                    c(name, style: SelType.small),
                    c('Members who gave', style: SelType.small),
                    c('Share of the church', style: SelType.small),
                  ],
                ),
                for (final m in months)
                  TableRow(
                    children: [
                      c(
                        m == now
                            ? '${DateFormat.MMMM().format(GivingView.monthOf(m))} · so far'
                            : DateFormat.MMMM().format(GivingView.monthOf(m)),
                        align: TextAlign.left,
                      ),
                      for (final a in arms)
                        c(
                          cell(m, a.id) == 0 ? '–' : money(cell(m, a.id)),
                          fill: shade(cell(m, a.id)),
                        ),
                      c(money(f.byMonth[m] ?? 0), style: strong),
                      c('${gaveIn(m)} of $roster'),
                      c(share(f.byMonth[m] ?? 0, view.monthTotal(m))),
                    ],
                  ),
                TableRow(
                  children: [
                    c('Year', style: strong, align: TextAlign.left),
                    for (final a in arms)
                      c(money(f.byArm[a.id] ?? 0), style: strong),
                    c(money(f.total), style: strong),
                    c('${f.gave.length} of $roster', style: strong),
                    c(share(f.total, yearTotal), style: strong),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        chart,
        const SizedBox(height: SelSpace.x4),
        table,
        const SizedBox(height: SelSpace.x4),
        SelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recent months may look low while giving is still coming in',
                style: SelType.subtitle,
              ),
              const SizedBox(height: SelSpace.x1),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Entries waiting in the Queue count here once they are approved. ',
                    style: SelType.bodySm,
                  ),
                  SelLink(
                    label: 'Open the Queue',
                    onTap: () => context.go('/queue'),
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
