import 'giving_view.dart';

/// How a fellowship's giving has been lately, from its closed months.
enum RhythmTrend { steady, pickingUp, slipping }

/// One fellowship's row in the giving rhythm: of its partners, how many gave
/// in each month.
class FellowshipRhythmRow {
  FellowshipRhythmRow({
    required this.key,
    required this.name,
    required this.partners,
    required this.gave,
    required this.average,
    required this.trend,
    required this.counted,
  });

  final String key;
  final String name;

  /// Partners on the book, or more if more than that gave in some month.
  final int partners;

  /// Month key → partners who gave that month.
  final Map<int, int> gave;

  /// Share of partners who gave, averaged over the closed months; null with
  /// no closed month yet.
  final double? average;

  /// Null until there are enough closed months to tell.
  final RhythmTrend? trend;

  /// The closed months the average and trend use: ones where the church has
  /// any giving recorded. A month with nothing at all is almost always one
  /// not entered yet, not one where everybody stopped.
  final List<int> counted;

  bool isRecorded(int month) => counted.contains(month);

  double shareIn(int month) => partners == 0 ? 0 : (gave[month] ?? 0) / partners;
}

/// Four wide bands, not a smooth scale, so a one-person change does not
/// flip a steady fellowship's colour: 0 under a quarter, 1 to half, 2 to
/// three quarters, 3 at three quarters or more.
int rhythmBand(double share) {
  if (share >= .75) return 3;
  if (share >= .5) return 2;
  if (share >= .25) return 1;
  return 0;
}

/// Fellowships (in [view]'s order) with how many of their partners gave in
/// each of [months]. Months on or after [openMonth] are still open: they show
/// but do not count toward the average or trend. A last "All" row adds up
/// the church.
List<FellowshipRhythmRow> fellowshipRhythm({
  required GivingView view,
  required List<int> months,
  required int openMonth,
}) {
  final gaveBy = <String, Map<int, int>>{};
  final all = <int, int>{};
  for (final p in view.partners) {
    final row = gaveBy.putIfAbsent(p.fellowshipKey, () => {});
    for (final m in months) {
      if ((p.byMonth[m] ?? 0) > 0) {
        row[m] = (row[m] ?? 0) + 1;
        all[m] = (all[m] ?? 0) + 1;
      }
    }
  }
  final closed = [for (final m in months) if (m < openMonth && (all[m] ?? 0) > 0) m];

  FellowshipRhythmRow make(String key, String name, int onBook, Map<int, int> gave) {
    final most = gave.values.fold<int>(0, (a, b) => a > b ? a : b);
    final n = onBook > most ? onBook : most;
    double share(Iterable<int> ms) =>
        ms.isEmpty || n == 0 ? 0 : ms.fold<int>(0, (s, m) => s + (gave[m] ?? 0)) / (ms.length * n);
    RhythmTrend? trend;
    if (closed.length >= 4 && n > 0) {
      final recent = closed.sublist(closed.length - 3);
      final before = closed.sublist(0, closed.length - 3);
      final d = share(recent) - share(before);
      trend = d.abs() < .06
          ? RhythmTrend.steady
          : d > 0
          ? RhythmTrend.pickingUp
          : RhythmTrend.slipping;
    }
    return FellowshipRhythmRow(
      key: key,
      name: name,
      partners: n,
      gave: gave,
      average: closed.isEmpty || n == 0 ? null : share(closed),
      trend: trend,
      counted: closed,
    );
  }

  final rows = [
    for (final f in view.fellowships) make(f.key, f.name, f.partners, gaveBy[f.key] ?? const {}),
  ];
  final onBook = view.fellowships.fold<int>(0, (s, f) => s + f.partners);
  return [...rows, make('', 'All', onBook, all)];
}

/// The fellowship that fell furthest below its own average (under 70% of
/// it) in months when the rest of the church held up: the one thing worth
/// saying in words above the grid.
({FellowshipRhythmRow row, List<int> months})? biggestDip(List<FellowshipRhythmRow> rows) {
  final church = rows.where((r) => r.key.isEmpty).firstOrNull;
  if (church == null) return null;
  ({FellowshipRhythmRow row, List<int> months})? best;
  var bestDrop = 0.0;
  for (final r in rows) {
    if (r.key.isEmpty || r.average == null || r.partners < 3) continue;
    // Everyone else in the church, month by month. A dip they share says
    // nothing about this fellowship.
    final others = church.partners - r.partners;
    double rest(int m) => others <= 0 ? 0 : ((church.gave[m] ?? 0) - (r.gave[m] ?? 0)) / others;
    final ms = church.counted;
    if (ms.isEmpty) continue;
    final restAvg = ms.fold<double>(0, (s, m) => s + rest(m)) / ms.length;
    final low = [
      for (final m in ms)
        if (r.shareIn(m) < r.average! * .7 && (others <= 0 || rest(m) >= restAvg * .85)) m,
    ];
    if (low.isEmpty) continue;
    final drop = low.fold<double>(0, (s, m) => s + (r.average! - r.shareIn(m)));
    if (drop > bestDrop) {
      bestDrop = drop;
      best = (row: r, months: low);
    }
  }
  return best;
}
