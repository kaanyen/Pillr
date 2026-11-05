import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/extensions/async_value_ext.dart';
import '../design/seline.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/entries/providers/entries_providers.dart';
import '../features/leaderboard/giving_view.dart';
import '../features/periods/providers/periods_providers.dart';
import 'views/view_common.dart';

/// Records · By month, as on the canvas: one row per month of the period
/// (entries, approved, still waiting) and the year so far. A month opens who
/// gave in it.
class MonthlyRecordsScreen extends ConsumerWidget {
  const MonthlyRecordsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(churchMoneyFormatProvider);
    final view = ref.watch(givingViewProvider);
    final loading = ref.watch(givingViewLoadingProvider);
    final period = ref.watch(activePeriodProvider);
    final pending =
        ref.watch(pendingEntriesProvider).valueOrNull ?? const [];
    final waiting = <int, double>{};
    for (final e in pending) {
      final m = GivingView.monthKey(e.dateGiven);
      waiting[m] = (waiting[m] ?? 0) + e.amountCedis;
    }
    final now = GivingView.monthKey(DateTime.now());
    final months = view.months.where((m) => m <= now).toList();
    final waitingTotal = waiting.values.fold<double>(0, (s, v) => s + v);

    Widget waitingCell(double v) => Align(
      alignment: Alignment.centerRight,
      child: v == 0
          ? Text('None', style: SelType.small)
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Sel.skyWash,
                borderRadius: BorderRadius.circular(SelRadius.pill),
              ),
              child: Text(money(v), style: SelType.tag),
            ),
    );

    return SelPageBody(
      children: [
        SelPageTitle(
          title: 'By month',
          subtitle:
              '${period?.name ?? 'This period'} · counted by the date giving was given',
          actions: [
            SelButton(
              label: 'All records',
              kind: SelButtonKind.quiet,
              onPressed: () => context.go('/records'),
            ),
          ],
        ),
        if (loading)
          const ViewLoading()
        else
          SelLedger(
            minWidth: 640,
            columns: const [
              SelColumn('Month', flex: 3),
              SelColumn('Entries', flex: 2),
              SelColumn.numeric('Approved', width: 180),
              SelColumn.numeric('Waiting', width: 160),
            ],
            emptyState: const SelEmpty(
              title: 'No months yet',
              message: 'Open a giving period to count giving by month.',
            ),
            rows: [
              for (final m in months)
                SelRow(
                  onTap: () => _showMonth(context, view, m, money),
                  cells: [
                    Row(
                      children: [
                        Text(
                          monthLong(m).split(' ').first,
                          style: SelType.body.copyWith(color: Sel.text),
                        ),
                        if (m == now)
                          Text(' · so far', style: SelType.small),
                      ],
                    ),
                    SelCell.secondary('${view.entriesByMonth[m] ?? 0}'),
                    SelCell.numeric(money(view.monthTotal(m))),
                    waitingCell(waiting[m] ?? 0),
                  ],
                ),
              if (months.isNotEmpty)
                SelRow(
                  cells: [
                    Text(
                      'Year so far',
                      style: SelType.body.copyWith(
                        color: Sel.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text('${view.entryCount}', style: SelType.bodyMedium.copyWith(color: Sel.text)),
                    Text(
                      money(view.total),
                      textAlign: TextAlign.right,
                      style: SelType.subtitleSm.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(money(waitingTotal), style: SelType.bodyMedium.copyWith(color: Sel.text)),
                    ),
                  ],
                ),
            ],
          ),
      ],
    );
  }

  /// Who gave in [month], biggest first.
  void _showMonth(
    BuildContext context,
    GivingView view,
    int month,
    String Function(num) money,
  ) {
    final gave = view.partners.where((p) => (p.byMonth[month] ?? 0) > 0).toList()
      ..sort((a, b) => (b.byMonth[month] ?? 0).compareTo(a.byMonth[month] ?? 0));
    showSelSideSheet<void>(
      context,
      title: monthLong(month),
      subtitle:
          '${gave.length} partners · ${money(view.monthTotal(month))} approved',
      child: SelLedger(
        minWidth: 360,
        columns: const [
          SelColumn('Partner', flex: 3),
          SelColumn.numeric('Gave', width: 140),
        ],
        emptyState: const SelEmpty(
          title: 'Nobody yet',
          message: 'No approved giving in this month.',
        ),
        rows: [
          for (final p in gave)
            SelRow(
              onTap: () {
                Navigator.of(context).pop();
                context.go('/partners/${p.partnerId}');
              },
              cells: [
                SelCell.stacked(p.name, p.fellowship),
                SelCell.numeric(money(p.byMonth[month] ?? 0)),
              ],
            ),
        ],
      ),
    );
  }
}
