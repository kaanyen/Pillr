import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../design/seline.dart';
import '../features/leaderboard/fellowship_rhythm.dart';
import '../features/leaderboard/giving_view.dart';
import '../core/errors/plain_error.dart';
import '../features/leaderboard/rhythm_counts_provider.dart';
import 'views/view_common.dart';

/// Fellowships · Giving rhythm, as on the canvas (board 5c): a quiet table of
/// how many of each fellowship's partners gave each month. Only the months
/// below the fellowship's usual level are marked, so a dip is what you see.
///
/// Pastors' rows come from the giving they can read; staff's ([countsOnly])
/// from counts the server sends, with no names or amounts, and the rows do
/// not open a fellowship's members.
class FellowshipRhythmView extends ConsumerWidget {
  const FellowshipRhythmView({super.key, this.countsOnly = false});

  final bool countsOnly;

  static String _months(List<int> ms) {
    final names = [for (final m in ms) DateFormat('MMMM').format(GivingView.monthOf(m))];
    if (names.length <= 2) return names.join(' and ');
    return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = GivingView.monthKey(DateTime.now());
    List<int> recent(List<int> ms) {
      final all = [for (final m in ms) if (m <= now) m];
      return all.length > 12 ? all.sublist(all.length - 12) : all;
    }

    final List<int> months;
    final List<FellowshipRhythmRow> rows;
    if (countsOnly) {
      final async = ref.watch(rhythmCountsProvider);
      if (async.isLoading && !async.hasValue) return const ViewLoading();
      if (async.hasError && !async.hasValue) return SelError(message: plainError(async.error));
      final d = async.value!;
      months = recent(d.months);
      rows = d.fellowships.isEmpty
          ? const []
          : fellowshipRhythmFromCounts(fellowships: d.fellowships, months: months, openMonth: now);
    } else {
      final view = ref.watch(givingViewProvider);
      if (ref.watch(givingViewLoadingProvider)) return const ViewLoading();
      months = recent(view.months);
      rows = view.fellowships.isEmpty ? const [] : fellowshipRhythm(view: view, months: months, openMonth: now);
    }
    if (months.isEmpty || rows.isEmpty) {
      return const SelCard(
        child: SelEmpty(
          title: 'Nothing to show yet',
          message: 'Once giving is approved this year, each fellowship shows how many of its partners give each month.',
        ),
      );
    }
    final church = rows.last;
    final dip = biggestDip(rows);

    // One plain sentence about the biggest dip, as on the canvas (5c).
    TextSpan? lead() {
      if (dip == null) return null;
      final r = dip.row;
      final fewest = dip.months.map((m) => r.gave[m] ?? 0).reduce((a, b) => a < b ? a : b);
      final last = church.counted.last;
      final back = dip.months.contains(last)
          ? ''
          : ' It is back to ${r.gave[last] ?? 0} in ${DateFormat('MMMM').format(GivingView.monthOf(last))}.';
      return TextSpan(
        style: SelType.lead.copyWith(color: Sel.text),
        children: [
          TextSpan(
            text: '${r.name} dipped in ${_months(dip.months)},',
            style: const TextStyle(color: Sel.ink, fontWeight: FontWeight.w700),
          ),
          TextSpan(text: ' when only $fewest of its ${r.partners} partners gave.$back'),
        ],
      );
    }

    // Slipping fellowships first; the church's own row stays last.
    int order(RhythmTrend? t) => switch (t) {
      RhythmTrend.slipping => 0,
      RhythmTrend.pickingUp => 1,
      RhythmTrend.steady => 2,
      null => 3,
    };
    final shown = [
      ...([for (final r in rows) if (r.key.isNotEmpty) r]..sort((a, b) => order(a.trend).compareTo(order(b.trend)))),
      church,
    ];

    final line = lead();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (line != null) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Text.rich(line),
          ),
          const SizedBox(height: SelSpace.x4),
        ],
        SelCard(
          padding: EdgeInsets.zero,
          clip: true,
          child: LayoutBuilder(
            builder: (context, c) {
              const nameW = 200.0, trendW = 140.0, pad = 24.0;
              final cellW = ((c.maxWidth - nameW - trendW - pad * 2) / months.length).clamp(48.0, 96.0);
              final width = nameW + trendW + pad * 2 + cellW * months.length;

              Widget cell(FellowshipRhythmRow r, int m) {
                final open = m >= now;
                final n = r.gave[m] ?? 0;
                final month = DateFormat('MMMM').format(GivingView.monthOf(m));
                final isAll = r.key.isEmpty;
                final style = SelType.body.copyWith(
                  color: isAll ? Sel.text : Sel.warm,
                  fontFeatures: const [FontFeature.tabularFigures()],
                );
                final Widget child;
                if (open) {
                  child = Text('so far', style: SelType.small.copyWith(color: Sel.warm));
                } else if (!church.isRecorded(m)) {
                  child = Text('–', style: style);
                } else if (!isAll && r.isDip(m)) {
                  child = Container(
                    constraints: const BoxConstraints(minWidth: 34),
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(color: const Color(0xFFE7F1FB), borderRadius: BorderRadius.circular(40)),
                    child: Center(
                      widthFactor: 1,
                      child: Text('$n', style: style.copyWith(color: Sel.ink, fontWeight: FontWeight.w800)),
                    ),
                  );
                } else {
                  child = Text('$n', style: style);
                }
                return Tooltip(
                  message: open
                      ? '$month is still open: $n of ${r.partners} so far'
                      : !church.isRecorded(m)
                      ? 'No giving is recorded for $month yet'
                      : '$month: $n of ${r.partners} partners gave${!isAll && r.isDip(m) ? ', fewer than usual' : ''}',
                  child: SizedBox(width: cellW, child: Center(child: child)),
                );
              }

              Widget trendText(RhythmTrend? t) => switch (t) {
                RhythmTrend.slipping => Text(
                  '↓ Slipping',
                  style: SelType.body.copyWith(color: Sel.ink, fontWeight: FontWeight.w700),
                ),
                RhythmTrend.pickingUp => Text('↑ Picking up', style: SelType.body.copyWith(color: Sel.text)),
                RhythmTrend.steady => Text('Steady', style: SelType.body.copyWith(color: Sel.text)),
                null => Text('–', style: SelType.body.copyWith(color: Sel.warm)),
              };

              Widget row(FellowshipRhythmRow r) {
                final isAll = r.key.isEmpty;
                final canOpen = !isAll && !countsOnly;
                final title = Text(
                  isAll ? 'Whole church' : r.name,
                  overflow: TextOverflow.ellipsis,
                  style: SelType.bodyMedium.copyWith(color: Sel.ink, fontWeight: FontWeight.w700),
                );
                return Container(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: isAll ? Sel.border : Sel.rowLine, width: isAll ? 1.5 : 1)),
                  ),
                  child: InkWell(
                    onTap: canOpen ? () => context.go('/fellowships/${Uri.encodeComponent(r.key)}?tab=months') : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: pad, vertical: 14),
                      child: Row(
                        children: [
                          SizedBox(
                            width: nameW,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [title, Text('${r.partners} partners', style: SelType.small)],
                            ),
                          ),
                          for (final m in months) cell(r, m),
                          SizedBox(width: trendW, child: Padding(padding: const EdgeInsets.only(left: 12), child: trendText(r.trend))),
                        ],
                      ),
                    ),
                  ),
                );
              }

              final head = Padding(
                padding: const EdgeInsets.fromLTRB(pad, 16, pad, 12),
                child: Row(
                  children: [
                    SizedBox(width: nameW, child: Text('Fellowship', style: SelType.small.copyWith(color: Sel.warm, fontWeight: FontWeight.w600))),
                    for (final m in months)
                      SizedBox(
                        width: cellW,
                        child: Text(
                          DateFormat('MMM').format(GivingView.monthOf(m)),
                          textAlign: TextAlign.center,
                          style: SelType.small.copyWith(color: Sel.warm, fontWeight: FontWeight.w600),
                        ),
                      ),
                    SizedBox(
                      width: trendW,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text('Lately', style: SelType.small.copyWith(color: Sel.warm, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              );

              final table = SizedBox(
                width: width < c.maxWidth ? c.maxWidth : width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [head, for (final r in shown) row(r)],
                ),
              );
              return SingleChildScrollView(scrollDirection: Axis.horizontal, child: table);
            },
          ),
        ),
        const SizedBox(height: SelSpace.x3),
        Text(
          'Highlighted months are when fewer partners gave than the fellowship usually has. '
          'Slipping fellowships are listed first.',
          style: SelType.small.copyWith(color: Sel.warm),
        ),
      ],
    );
  }
}
