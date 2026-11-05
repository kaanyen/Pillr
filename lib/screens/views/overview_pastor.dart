import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/extensions/async_value_ext.dart';
import '../../design/seline.dart';
import '../../features/arms/providers/arms_providers.dart';
import '../../features/church/providers/church_settings_providers.dart';
import '../../features/entries/domain/partnership_entry.dart';
import '../../features/entries/providers/entries_providers.dart';
import '../../features/goals/providers/goals_providers.dart';
import '../../features/leaderboard/giving_view.dart';
import '../../features/maintenance/providers/duplicate_health_provider.dart';
import '../../features/periods/providers/periods_providers.dart';

/// The pastor's Overview body, from the canvas board "1 · Overview":
/// Giving this year beside Waiting for you, then By arm, Who gives most and
/// the goals. Every figure comes from the same approved, in-period entries.
class PastorOverview extends ConsumerWidget {
  const PastorOverview({super.key, this.extra});

  /// The third card on the bottom row (Recent activity).
  final Widget? extra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(churchMoneyFormatProvider);
    final compact = ref.watch(churchCompactMoneyProvider);
    final view = ref.watch(givingViewProvider);
    final pending = ref.watch(pendingEntriesProvider).valueOrNull ?? const [];
    final goals = ref.watch(countedActivePeriodGoalsProvider);
    final goal = goals.fold<double>(0, (s, g) => s + g.targetAmountCedis);
    final period = ref.watch(activePeriodProvider);

    final top = LayoutBuilder(
      builder: (context, c) {
        final giving = _GivingCard(
          view: view,
          goal: goal,
          start: period?.startDate,
          end: period?.endDate,
          money: money,
          compact: compact,
        );
        final waiting = _WaitingCard(entries: pending, money: money);
        if (c.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              giving,
              const SizedBox(height: SelSpace.x4),
              waiting,
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: giving),
              const SizedBox(width: SelSpace.x4),
              SizedBox(width: 340, child: waiting),
            ],
          ),
        );
      },
    );

    final bottom = LayoutBuilder(
      builder: (context, c) {
        final cards = <Widget>[
          _ByArmCard(view: view, money: money),
          _TopGiversCard(view: view, money: money),
          ?extra,
        ];
        if (c.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: SelSpace.x4),
                cards[i],
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: SelSpace.x4),
                Expanded(child: cards[i]),
              ],
            ],
          ),
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        top,
        const SizedBox(height: SelSpace.x4),
        bottom,
      ],
    );
  }
}

class _GivingCard extends StatelessWidget {
  const _GivingCard({
    required this.view,
    required this.goal,
    required this.start,
    required this.end,
    required this.money,
    required this.compact,
  });

  final GivingView view;
  final double goal;
  final DateTime? start;
  final DateTime? end;
  final String Function(num) money;
  final String Function(num) compact;

  @override
  Widget build(BuildContext context) {
    final total = view.total;
    final left = end?.difference(DateTime.now()).inDays.clamp(0, 9999);
    final whole = money(total.truncate());
    final cents = ((total - total.truncate()) * 100).round().toString().padLeft(
      2,
      '0',
    );
    final wholeText = whole.contains('.')
        ? whole.substring(0, whole.lastIndexOf('.'))
        : whole;

    Widget kpi(String label, Widget value, [String? note]) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: SelType.small),
        const SizedBox(height: 2),
        value,
        if (note != null) Text(note, style: SelType.small),
      ],
    );

    return SelCard(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: SelSpace.x1,
            children: [
              Text('Giving this year', style: SelType.subtitle),
              Text(
                start == null
                    ? 'Approved giving only'
                    : 'Approved giving only · ${DateFormat('d MMM').format(start!)} to today',
                style: SelType.small,
              ),
            ],
          ),
          const SizedBox(height: SelSpace.x4),
          Wrap(
            spacing: SelSpace.x10,
            runSpacing: SelSpace.x4,
            children: [
              kpi(
                'Approved',
                Text.rich(
                  TextSpan(
                    text: wholeText,
                    style: SelType.hero.copyWith(fontSize: 34, height: 1.2),
                    children: [
                      TextSpan(
                        text: '.$cents',
                        style: SelType.subtitle.copyWith(color: Sel.warm),
                      ),
                    ],
                  ),
                ),
                '${view.entryCount} entries',
              ),
              if (goal > 0) ...[
                kpi(
                  'Goal',
                  Text(
                    money(goal),
                    style: SelType.subtitle.copyWith(fontSize: 22),
                  ),
                ),
                kpi(
                  'Still to go',
                  Text(
                    money(math.max(0, goal - total)),
                    style: SelType.subtitle.copyWith(fontSize: 22),
                  ),
                  left == null ? null : '$left days left',
                ),
              ] else if (left != null)
                kpi(
                  'Days left',
                  Text('$left', style: SelType.subtitle.copyWith(fontSize: 22)),
                ),
            ],
          ),
          const SizedBox(height: SelSpace.x6),
          SizedBox(
            height: 220,
            child: CustomPaint(
              painter: _PaceChart(
                months: view.months,
                byMonth: {for (final m in view.months) m: view.monthTotal(m)},
                goal: goal,
                compact: compact,
              ),
            ),
          ),
          const SizedBox(height: SelSpace.x3),
          Wrap(
            spacing: SelSpace.x6,
            runSpacing: SelSpace.x2,
            children: [
              const _Legend(kind: 0, label: 'Approved so far'),
              if (goal > 0) const _Legend(kind: 1, label: 'Pace for the goal'),
              const _Legend(kind: 2, label: "At this year's pace"),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.kind, required this.label});

  /// 0 solid sky, 1 dashed grey, 2 dotted sky.
  final int kind;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      CustomPaint(size: const Size(20, 8), painter: _LegendLine(kind)),
      const SizedBox(width: SelSpace.x2),
      Text(label, style: SelType.small),
    ],
  );
}

class _LegendLine extends CustomPainter {
  _LegendLine(this.kind);

  final int kind;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..strokeWidth = kind == 0 ? 3 : 2
      ..strokeCap = StrokeCap.round
      ..color = kind == 1 ? Sel.ash : Sel.sky;
    final y = size.height / 2;
    if (kind == 0) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
      return;
    }
    final step = kind == 1 ? 6.0 : 3.0;
    for (var x = 0.0; x < size.width; x += step * 1.8) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + step, size.width), y),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_LegendLine old) => old.kind != kind;
}

/// Cumulative approved giving through the period against the straight-line
/// pace that reaches the goal, and where this year's own pace is heading.
class _PaceChart extends CustomPainter {
  _PaceChart({
    required this.months,
    required this.byMonth,
    required this.goal,
    required this.compact,
  });

  final List<int> months;
  final Map<int, double> byMonth;
  final double goal;
  final String Function(num) compact;

  @override
  void paint(Canvas canvas, Size size) {
    if (months.isEmpty) return;
    const left = 52.0, bottom = 26.0, top = 8.0;
    final w = size.width - left - 8;
    final h = size.height - bottom - top;
    final now = GivingView.monthKey(DateTime.now());
    final current = months.indexWhere((m) => m == now);
    final upto = current < 0
        ? (now > months.last ? months.length - 1 : -1)
        : current;

    final cum = <double>[];
    var run = 0.0;
    for (final m in months) {
      run += byMonth[m] ?? 0;
      cum.add(run);
    }
    final reached = upto >= 0 ? cum[upto] : 0.0;
    final projected = upto >= 0 ? reached / (upto + 1) * months.length : 0.0;
    final maxV = [goal, reached, projected, 1.0].reduce(math.max) * 1.05;

    double x(num i) => left + w * (i / math.max(1, months.length - 1));
    double y(double v) => top + h * (1 - v / maxV);

    final grid = Paint()
      ..color = Sel.border
      ..strokeWidth = 1;
    final label = SelType.small;
    for (final f in [0.0, 0.5, 1.0]) {
      final v = maxV / 1.05 * f;
      final yy = y(v);
      canvas.drawLine(Offset(left, yy), Offset(left + w, yy), grid);
      _text(canvas, f == 0 ? '0' : compact(v), Offset(0, yy - 8), label, 46);
    }
    for (var i = 0; i < months.length; i++) {
      final m = DateFormat('MMM').format(GivingView.monthOf(months[i]));
      _text(
        canvas,
        m,
        Offset(x(i) - 14, size.height - 18),
        label,
        28,
        center: true,
      );
    }

    if (goal > 0) {
      final pace = Paint()
        ..color = Sel.ash
        ..strokeWidth = 2;
      _dashed(
        canvas,
        Offset(x(-0.0), y(0)),
        Offset(x(months.length - 1), y(goal)),
        pace,
        7,
        6,
      );
    }
    if (upto < 0) return;

    final line = Path()..moveTo(x(0), y(cum[0]));
    for (var i = 1; i <= upto; i++) {
      line.lineTo(x(i), y(cum[i]));
    }
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = Sel.cyan,
    );
    if (upto < months.length - 1) {
      _dashed(
        canvas,
        Offset(x(upto), y(reached)),
        Offset(x(months.length - 1), y(projected)),
        Paint()
          ..color = Sel.sky
          ..strokeWidth = 2,
        2,
        5,
      );
    }
    canvas.drawCircle(
      Offset(x(upto), y(reached)),
      5,
      Paint()..color = Sel.card,
    );
    canvas.drawCircle(
      Offset(x(upto), y(reached)),
      5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Sel.cyan,
    );

    if (goal > 0) {
      final paceNow = goal * (upto + 1) / months.length;
      final gap = reached - paceNow;
      final chip =
          'Today · ${compact(gap.abs())} ${gap >= 0 ? 'ahead of' : 'behind'} pace';
      final tp = TextPainter(
        text: TextSpan(
          text: chip,
          style: SelType.small.copyWith(
            color: Sel.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final cx = (x(upto) - tp.width - 26).clamp(
        left,
        left + w - tp.width - 20,
      );
      final cy = math.max(top, y(reached) - 40);
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(cx, cy, tp.width + 20, tp.height + 10),
        const Radius.circular(20),
      );
      canvas.drawRRect(r, Paint()..color = Sel.card);
      canvas.drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Sel.border,
      );
      tp.paint(canvas, Offset(cx + 10, cy + 5));
    }
  }

  void _dashed(Canvas c, Offset a, Offset b, Paint p, double dash, double gap) {
    final d = (b - a).distance;
    if (d == 0) return;
    final dir = (b - a) / d;
    for (var t = 0.0; t < d; t += dash + gap) {
      c.drawLine(
        a + dir * t,
        a + dir * math.min(t + dash, d),
        p..strokeCap = StrokeCap.round,
      );
    }
  }

  void _text(
    Canvas c,
    String s,
    Offset o,
    TextStyle st,
    double maxW, {
    bool center = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: st),
      textDirection: TextDirection.ltr,
      textAlign: center ? TextAlign.center : TextAlign.left,
    )..layout(minWidth: center ? maxW : 0, maxWidth: maxW);
    tp.paint(c, o);
  }

  @override
  bool shouldRepaint(_PaceChart old) =>
      old.byMonth != byMonth || old.goal != goal || old.months != months;
}

/// Navy: the queue's oldest entries, and the one button to clear them.
class _WaitingCard extends ConsumerWidget {
  const _WaitingCard({required this.entries, required this.money});

  final List<PartnershipEntry> entries;
  final String Function(num) money;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dupes = ref.watch(duplicateBadgeCountProvider);
    final tree = ref.watch(armTreeProvider);
    final oldest = [...entries]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final total = entries.fold<double>(0, (s, e) => s + e.amountCedis);
    final days = oldest.isEmpty
        ? 0
        : DateTime.now().difference(oldest.first.createdAt).inDays;
    const soft = Color(0xFFC9DEF3);

    return Container(
      padding: const EdgeInsets.fromLTRB(26, 26, 26, 22),
      decoration: BoxDecoration(
        color: Sel.ink,
        borderRadius: BorderRadius.circular(SelRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Waiting for you', style: SelType.body.copyWith(color: soft)),
          const SizedBox(height: SelSpace.x1),
          Text(
            entries.isEmpty
                ? 'All caught up'
                : '${entries.length} ${entries.length == 1 ? 'entry' : 'entries'}',
            style: SelType.hero.copyWith(
              fontSize: 32,
              color: Sel.card,
              height: 1.15,
            ),
          ),
          if (entries.isNotEmpty)
            Text(
              '${money(total)} · oldest $days ${days == 1 ? 'day' : 'days'}',
              style: SelType.bodySm.copyWith(color: soft),
            )
          else
            Text(
              'Nothing waiting for review.',
              style: SelType.bodySm.copyWith(color: soft),
            ),
          const SizedBox(height: SelSpace.x3),
          for (final e in oldest.take(4)) ...[
            InkWell(
              onTap: () => context.go('/entries/${e.id}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.partnerSnapshot['fullName']?.toString() ?? '—',
                            style: SelType.body.copyWith(
                              color: Sel.card,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${tree.shownNameOf(e.partnershipArmId) ?? e.armSnapshot['name'] ?? ''} · ${DateFormat('d MMM').format(e.dateGiven)}',
                            style: SelType.small.copyWith(color: soft),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      money(e.amountCedis),
                      style: SelType.body.copyWith(
                        color: Sel.card,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: Sel.card.withValues(alpha: 0.12)),
          ],
          const Spacer(),
          const SizedBox(height: SelSpace.x4),
          Material(
            color: Sel.card,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => context.go('/queue?filter=pending'),
              child: SizedBox(
                height: 48,
                child: Center(
                  child: Text(
                    entries.isEmpty ? 'Open the Queue' : 'Review oldest first',
                    style: SelType.button.copyWith(color: Sel.ink),
                  ),
                ),
              ),
            ),
          ),
          if (dupes > 0) ...[
            const SizedBox(height: SelSpace.x3),
            Center(
              child: InkWell(
                onTap: () => context.go('/tools'),
                child: Text(
                  '$dupes possible ${dupes == 1 ? 'duplicate' : 'duplicates'} to check',
                  style: SelType.bodySm.copyWith(
                    color: Sel.card,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                    decorationColor: Sel.card,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ByArmCard extends StatelessWidget {
  const _ByArmCard({required this.view, required this.money});

  final GivingView view;
  final String Function(num) money;

  @override
  Widget build(BuildContext context) {
    final totals = {for (final a in view.arms) a.id: view.armTotal(a.id)};
    final arms = [...view.arms]
      ..sort((a, b) => (totals[b.id] ?? 0).compareTo(totals[a.id] ?? 0));
    final shown = arms.where((a) => (totals[a.id] ?? 0) > 0).take(5).toList();
    final maxV = view.total == 0 ? 1.0 : view.total;
    return SelCard(
      onTap: () => context.go('/records/by-arm'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('By arm', style: SelType.subtitle),
          const SizedBox(height: SelSpace.x4),
          if (shown.isEmpty)
            Text('No approved giving yet.', style: SelType.bodySm),
          for (final a in shown) ...[
            Row(
              children: [
                Expanded(child: Text(a.name, style: SelType.body)),
                Text(money(totals[a.id] ?? 0), style: SelType.bodyMedium),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (totals[a.id] ?? 0) / maxV,
                minHeight: 10,
                backgroundColor: Sel.track,
                valueColor: const AlwaysStoppedAnimation(Sel.sky),
              ),
            ),
            const SizedBox(height: SelSpace.x4),
          ],
        ],
      ),
    );
  }
}

class _TopGiversCard extends StatelessWidget {
  const _TopGiversCard({required this.view, required this.money});

  final GivingView view;
  final String Function(num) money;

  @override
  Widget build(BuildContext context) {
    final top = view.partners.take(5).toList();
    final share = view.total == 0
        ? 0
        : (top.fold<double>(0, (s, p) => s + p.total) / view.total * 100)
              .round();
    return SelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Who gives most', style: SelType.subtitle)),
              SelLink(label: 'Ranked', onTap: () => context.go('/ranked')),
            ],
          ),
          if (top.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: SelSpace.x2),
              child: Text(
                '${top.length} partners gave $share% of this year\'s giving.',
                style: SelType.bodySm.copyWith(color: Sel.text),
              ),
            ),
          if (top.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: SelSpace.x3),
              child: Text('No approved giving yet.', style: SelType.bodySm),
            ),
          for (var i = 0; i < top.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Sel.border),
            InkWell(
              onTap: () => context.go('/partners/${top[i].partnerId}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    _Avatar(name: top[i].name),
                    const SizedBox(width: SelSpace.x3),
                    Expanded(
                      child: Text(
                        top[i].name,
                        style: SelType.body,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(money(top[i].total), style: SelType.bodyMedium),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Sel.skyTint,
        shape: BoxShape.circle,
      ),
      child: Text(
        parts.take(2).map((w) => w[0].toUpperCase()).join(),
        style: SelType.tag.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// "Overview · Monday 3 November · 2026 partnership year".
String overviewSubtitle(String? periodName) {
  final today = DateFormat('EEEE d MMMM').format(DateTime.now());
  return periodName == null ? today : '$today · $periodName';
}
