import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../design/seline.dart';
import '../features/leaderboard/fellowship_rhythm.dart';
import '../features/leaderboard/giving_view.dart';
import 'views/view_common.dart';

/// Fellowships · Giving rhythm, as on the canvas (board 5c): each square is
/// how many of that fellowship's partners gave in the month, written in, on
/// four wide colour bands so only real dips stand out.
class FellowshipRhythmView extends ConsumerWidget {
  const FellowshipRhythmView({super.key});

  /// Fill and text for each band. The top band is the filled-button blue,
  /// which holds white text at 4.9:1.
  static const bands = <(Color, Color)>[
    (Color(0xFFF1F6FB), Sel.ink),
    (Color(0xFFD3EAFC), Sel.ink),
    (Color(0xFF8CCAFB), Sel.ink),
    (Sel.cyan, Sel.card),
  ];

  static String _months(List<int> ms) {
    final names = [for (final m in ms) DateFormat('MMMM').format(GivingView.monthOf(m))];
    if (names.length <= 2) return names.join(' and ');
    return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(givingViewProvider);
    if (ref.watch(givingViewLoadingProvider)) return const ViewLoading();
    final now = GivingView.monthKey(DateTime.now());
    final all = [for (final m in view.months) if (m <= now) m];
    final months = all.length > 12 ? all.sublist(all.length - 12) : all;
    if (months.isEmpty || view.fellowships.isEmpty) {
      return const SelCard(
        child: SelEmpty(
          title: 'Nothing to show yet',
          message: 'Once giving is approved this year, each fellowship shows how many of its partners give each month.',
        ),
      );
    }
    final rows = fellowshipRhythm(view: view, months: months, openMonth: now);
    final church = rows.last;
    final dip = biggestDip(rows);

    String? dipLine() {
      if (dip == null) return null;
      final r = dip.row;
      final fewest = dip.months.map((m) => r.gave[m] ?? 0).reduce((a, b) => a < b ? a : b);
      final last = church.counted.last;
      final back = dip.months.contains(last)
          ? ''
          : ' It has come back to ${r.gave[last] ?? 0} in ${DateFormat('MMMM').format(GivingView.monthOf(last))}.';
      return '${r.name} dipped in ${_months(dip.months)}:|only $fewest of its ${r.partners} partners gave.$back';
    }

    String trend(RhythmTrend? t) => switch (t) {
      RhythmTrend.steady => 'Steady',
      RhythmTrend.pickingUp => 'Picking up',
      RhythmTrend.slipping => 'Slipping',
      null => '',
    };

    final line = dipLine();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (line != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(color: Sel.skyTint, borderRadius: BorderRadius.circular(18)),
            child: Text.rich(
              TextSpan(
                style: SelType.body.copyWith(color: Sel.ink),
                children: [
                  TextSpan(text: line.split('|').first, style: const TextStyle(fontWeight: FontWeight.w800)),
                  TextSpan(text: ' ${line.split('|').last}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: SelSpace.x4),
        ],
        SelCard(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          child: LayoutBuilder(
            builder: (context, c) {
              const nameW = 150.0, avgW = 150.0, gap = 4.0;
              final cellW = ((c.maxWidth - nameW - avgW - gap * (months.length + 1)) / months.length)
                  .clamp(56.0, 96.0);
              final width = nameW + avgW + (cellW + gap) * months.length + gap;

              Widget cell(FellowshipRhythmRow r, int m) {
                final open = m >= now;
                final none = !open && !church.isRecorded(m);
                final n = r.gave[m] ?? 0;
                final (bg, fg) = bands[rhythmBand(r.shareIn(m))];
                final month = DateFormat('MMMM').format(GivingView.monthOf(m));
                return Padding(
                  padding: const EdgeInsets.only(left: gap),
                  child: Tooltip(
                    message: open
                        ? '$month is still open: $n of ${r.partners} so far'
                        : none
                        ? 'No giving is recorded for $month yet, so it is not counted'
                        : '$month: $n of ${r.partners} partners gave',
                    child: Container(
                      width: cellW,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: open || none ? Sel.card : bg,
                        borderRadius: BorderRadius.circular(12),
                        border: open || none ? Border.all(color: Sel.border) : null,
                      ),
                      child: open || none
                          ? Text(open ? 'open' : 'none yet', style: SelType.small)
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$n',
                                  style: SelType.body.copyWith(
                                    color: fg,
                                    fontWeight: FontWeight.w800,
                                    height: 1.1,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                                Text(
                                  'of ${r.partners}',
                                  style: SelType.small.copyWith(color: fg, fontSize: 11, height: 1.1),
                                ),
                              ],
                            ),
                    ),
                  ),
                );
              }

              Widget row(FellowshipRhythmRow r) {
                final isAll = r.key.isEmpty;
                final name = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      r.name,
                      overflow: TextOverflow.ellipsis,
                      style: SelType.bodyMedium.copyWith(
                        color: isAll ? Sel.ink : Sel.cyanEdge,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text('${r.partners} partners', style: SelType.small),
                  ],
                );
                return Container(
                  padding: EdgeInsets.only(top: isAll ? 8 : 0, bottom: gap),
                  decoration: isAll
                      ? const BoxDecoration(border: Border(top: BorderSide(color: Sel.rowLine, width: 1.5)))
                      : null,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: isAll
                        ? null
                        : () => context.go('/fellowships/${Uri.encodeComponent(r.key)}?tab=months'),
                    child: Row(
                      children: [
                        SizedBox(
                          width: nameW,
                          child: Padding(padding: const EdgeInsets.only(left: 8), child: name),
                        ),
                        for (final m in months) cell(r, m),
                        SizedBox(
                          width: avgW,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  r.average == null ? '–' : '${(r.average! * 100).round()}% a month',
                                  style: SelType.bodyMedium.copyWith(color: Sel.ink, fontWeight: FontWeight.w700),
                                ),
                                if (r.trend != null) Text(trend(r.trend), style: SelType.small),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final head = Row(
                children: [
                  SizedBox(
                    width: nameW,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text('Fellowship', style: SelType.small),
                    ),
                  ),
                  for (final m in months)
                    Padding(
                      padding: const EdgeInsets.only(left: gap),
                      child: SizedBox(
                        width: cellW,
                        child: Text(
                          DateFormat('MMM').format(GivingView.monthOf(m)),
                          textAlign: TextAlign.center,
                          style: SelType.small,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: avgW,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text('On average', textAlign: TextAlign.right, style: SelType.small),
                    ),
                  ),
                ],
              );

              Widget swatch(int band, String label) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28,
                    height: 16,
                    decoration: BoxDecoration(color: bands[band].$1, borderRadius: BorderRadius.circular(5)),
                  ),
                  const SizedBox(width: 6),
                  Text(label, style: SelType.small),
                ],
              );

              final grid = SizedBox(
                width: width < c.maxWidth ? c.maxWidth : width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [head, const SizedBox(height: 8), for (final r in rows) row(r)],
                ),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SingleChildScrollView(scrollDirection: Axis.horizontal, child: grid),
                  const SizedBox(height: SelSpace.x3),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Wrap(
                      spacing: 14,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text("How many of the fellowship's partners gave that month:", style: SelType.small),
                        swatch(0, 'fewer than 1 in 4'),
                        swatch(1, '1 in 4 to half'),
                        swatch(2, 'half to 3 in 4'),
                        swatch(3, '3 in 4 or more'),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
