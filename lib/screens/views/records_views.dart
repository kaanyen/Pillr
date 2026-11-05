import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../design/seline.dart';
import '../../features/church/providers/church_settings_providers.dart';
import '../../features/leaderboard/giving_view.dart';
import 'view_common.dart';

/// Records · By arm: each main arm's year, then the year month by month.
class RecordsByArmScreen extends ConsumerWidget {
  const RecordsByArmScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(churchMoneyFormatProvider);
    final view = ref.watch(givingViewProvider);
    final loading = ref.watch(givingViewLoadingProvider);

    return SelPageBody(
      children: [
        const SelPageTitle(
          title: 'By arm',
          subtitle: 'Approved giving in this period, by main arm.',
        ),
        if (loading)
          const ViewLoading()
        else ...[
          SelLedger(
            minWidth: 480,
            columns: const [
              SelColumn('Arm', flex: 3),
              SelColumn.numeric('Entries', width: 100),
              SelColumn.numeric('Approved', width: 160),
            ],
            emptyState: const SelEmpty(
              title: 'No arms yet',
              message: 'Add arms in Configuration to see giving split here.',
            ),
            rows: [
              for (final a in view.arms)
                SelRow(
                  cells: [
                    SelCell.primary(a.name),
                    SelCell.numeric(
                      '${view.armEntries[a.id] ?? 0}',
                      strong: false,
                    ),
                    SelCell.numeric(money(view.armTotal(a.id))),
                  ],
                ),
              if (view.arms.isNotEmpty)
                SelRow(
                  cells: [
                    SelCell.primary('All arms'),
                    SelCell.numeric('${view.entryCount}'),
                    SelCell.numeric(money(view.total)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: SelSpace.x6),
          const SelSectionLabel(label: 'Month by month'),
          SelLedger(
            minWidth: 160.0 + view.arms.length * 140 + 150,
            columns: [
              const SelColumn('Month', flex: 2),
              for (final a in view.arms) SelColumn.numeric(a.name, width: 140),
              const SelColumn.numeric('All arms', width: 150),
            ],
            rows: [
              for (final m in view.months)
                SelRow(
                  cells: [
                    SelCell.primary(monthLong(m)),
                    for (final a in view.arms)
                      SelCell.numeric(
                        money(view.armByMonth[m]?[a.id] ?? 0),
                        strong: false,
                      ),
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
