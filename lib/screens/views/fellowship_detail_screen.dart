import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/extensions/async_value_ext.dart';
import '../../design/seline.dart';
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

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(churchMoneyFormatProvider);
    final view = ref.watch(givingViewProvider);
    final loading = ref.watch(givingViewLoadingProvider);
    final roster =
        ref.watch(partnersStreamProvider(false)).valueOrNull ?? const [];
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
        Align(
          alignment: Alignment.centerLeft,
          child: SelLink(
            label: '← Fellowships',
            onTap: () => context.go('/fellowships'),
          ),
        ),
        const SizedBox(height: SelSpace.x2),
        SelPageTitle(
          title: name,
          subtitle: '${members.length} partners · this period',
        ),
        SelPillGroup<FellowshipTab>(
          selected: _tab,
          onChanged: (t) => setState(() => _tab = t),
          options: const [
            (FellowshipTab.overview, 'Overview'),
            (FellowshipTab.people, 'People'),
            (FellowshipTab.arms, 'Arms'),
            (FellowshipTab.months, 'Month by month'),
          ],
        ),
        const SizedBox(height: SelSpace.x6),
        if (loading)
          const ViewLoading()
        else
          switch (_tab) {
            FellowshipTab.overview => _overview(view, f, members, money),
            FellowshipTab.people => _people(members, giving, money),
            FellowshipTab.arms => _arms(view, f, giving, members, money),
            FellowshipTab.months => _months(view, f, money),
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
            SelStat(
              label: 'Place among fellowships',
              value: f == null
                  ? '–'
                  : '${ordinal(view.placeOf(widget.fellowshipKey))} of $n',
            ),
          ],
        ),
        const SizedBox(height: SelSpace.x6),
        Wrap(
          spacing: SelSpace.x6,
          runSpacing: SelSpace.x6,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 320, maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SelSectionLabel(label: 'Arms'),
                  SelLedger(
                    minWidth: 320,
                    columns: const [
                      SelColumn('Arm', flex: 2),
                      SelColumn.numeric('Given', width: 140),
                      SelColumn.numeric('Place', width: 90),
                    ],
                    rows: [
                      for (final a in view.arms)
                        SelRow(
                          cells: [
                            SelCell.primary(a.name),
                            SelCell.numeric(money(f?.byArm[a.id] ?? 0)),
                            SelCell.numeric(
                              f == null
                                  ? '–'
                                  : ordinal(
                                      view.placeOf(
                                        widget.fellowshipKey,
                                        armId: a.id,
                                      ),
                                    ),
                              strong: false,
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 320, maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SelSectionLabel(
                    label: 'Gave the most',
                    trailing: SelLink(
                      label: 'All ${members.length} people',
                      onTap: () => setState(() => _tab = FellowshipTab.people),
                    ),
                  ),
                  SelLedger(
                    minWidth: 320,
                    columns: const [
                      SelColumn('Partner', flex: 3),
                      SelColumn.numeric('Given', width: 140),
                    ],
                    emptyState: const SelEmpty(
                      title: 'No giving yet',
                      message:
                          'Approved giving from this fellowship shows here.',
                    ),
                    rows: [
                      for (final p in top)
                        SelRow(
                          onTap: () => context.go('/partners/${p.partnerId}'),
                          cells: [
                            SelCell.primary(p.name),
                            SelCell.numeric(money(p.total)),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
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
                                  f == null
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
  ) {
    final members = view.partners
        .where((p) => p.fellowshipKey == widget.fellowshipKey)
        .toList();
    double cell(int m, String armId) =>
        members.fold(0, (s, p) => s + (p.byArmMonth[m]?[armId] ?? 0));
    return SelLedger(
      minWidth: 180.0 + view.arms.length * 140 + 150,
      columns: [
        const SelColumn('Month', flex: 2),
        for (final a in view.arms) SelColumn.numeric(a.name, width: 140),
        const SelColumn.numeric('Total', width: 150),
      ],
      rows: [
        for (final m in view.months)
          SelRow(
            cells: [
              SelCell.primary(monthLong(m)),
              for (final a in view.arms)
                SelCell.numeric(money(cell(m, a.id)), strong: false),
              SelCell.numeric(money(f?.byMonth[m] ?? 0)),
            ],
          ),
      ],
    );
  }
}
