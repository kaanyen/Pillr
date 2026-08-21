import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../design/seline.dart';
import '../features/entries/domain/partnership_entry.dart';

/// Full-screen playback of a bulk approval.
///
/// Runs each approved entry past the viewer in turn, with a progress bar and a
/// running total. It is a receipt, not a decision point — the approval has
/// already happened by the time this opens — so it is fully skippable and
/// never blocks the result.
///
/// Deliberately paced: fast enough that thirty entries take about fifteen
/// seconds, slow enough that a name and an amount actually register. The list
/// scrolls so earlier rows stay visible, which is what makes it feel like
/// something is being tallied rather than a spinner with extra steps.
class ApprovalPlayback extends StatefulWidget {
  const ApprovalPlayback({
    super.key,
    required this.entries,
    required this.formatMoney,
  });

  final List<PartnershipEntry> entries;
  final String Function(num) formatMoney;

  /// Shows the playback over the current screen. Returns when it is done or
  /// the viewer skips.
  static Future<void> show(
    BuildContext context, {
    required List<PartnershipEntry> entries,
    required String Function(num) formatMoney,
  }) {
    if (entries.isEmpty) return Future.value();
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Sel.canvas.withValues(alpha: 0.97),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) =>
          ApprovalPlayback(entries: entries, formatMoney: formatMoney),
      transitionBuilder: (context, anim, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: child,
      ),
    );
  }

  @override
  State<ApprovalPlayback> createState() => _ApprovalPlaybackState();
}

class _ApprovalPlaybackState extends State<ApprovalPlayback> {
  static const _minTotal = Duration(seconds: 6);
  static const _maxTotal = Duration(seconds: 16);

  int _index = 0;
  double _runningTotal = 0;
  Timer? _timer;
  final _scroll = ScrollController();

  /// Per-entry interval, bounded so five entries are not over instantly and
  /// two hundred do not take three minutes.
  Duration get _tick {
    final n = widget.entries.length;
    final ms = (_maxTotal.inMilliseconds / n).clamp(
      _minTotal.inMilliseconds / n,
      520.0,
    );
    return Duration(milliseconds: ms.round());
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_tick, (t) {
      if (!mounted) return;
      if (_index >= widget.entries.length) {
        t.cancel();
        // Hold on the finished total for a beat before closing.
        Timer(const Duration(milliseconds: 1400), () {
          if (mounted) Navigator.of(context).maybePop();
        });
        return;
      }
      setState(() {
        _runningTotal += widget.entries[_index].amountCedis;
        _index++;
      });
      _scrollToLatest();
    });
  }

  void _scrollToLatest() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.entries.length;
    final done = _index >= total;
    final progress = total == 0 ? 1.0 : _index / total;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(SelSpace.x6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          done
                              ? 'Approved $total ${total == 1 ? "entry" : "entries"}'
                              : 'Approving $total ${total == 1 ? "entry" : "entries"}',
                          style: SelType.title,
                        ),
                      ),
                      if (!done)
                        SelButton(
                          label: 'Skip',
                          kind: SelButtonKind.quiet,
                          dense: true,
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                    ],
                  ),
                  const SizedBox(height: SelSpace.x6),

                  SelCard(
                    lift: SelLift.floating,
                    padding: EdgeInsets.zero,
                    clip: true,
                    child: SizedBox(
                      height: 320,
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(
                          vertical: SelSpace.x2,
                        ),
                        itemCount: _index,
                        itemBuilder: (context, i) => _Line(
                          entry: widget.entries[i],
                          formatMoney: widget.formatMoney,
                          // Only the newest line animates in; re-animating the
                          // whole list on every tick would be a strobe.
                          isNewest: i == _index - 1,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: SelSpace.x6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(SelRadius.pill),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: progress),
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOut,
                      builder: (context, v, _) => LinearProgressIndicator(
                        value: v,
                        minHeight: 4,
                        backgroundColor: Sel.border,
                        color: done ? Sel.success : Sel.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: SelSpace.x3),
                  Row(
                    children: [
                      Text('$_index of $total', style: SelType.bodyMuted),
                      const Spacer(),
                      Text('Running total', style: SelType.small),
                      const SizedBox(width: SelSpace.x2),
                      // The number counts up rather than jumping, which is
                      // what makes the tally feel like it is accumulating.
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: _runningTotal),
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOut,
                        builder: (context, v, _) => Text(
                          widget.formatMoney(v),
                          style: SelType.subtitle.copyWith(
                            color: done ? Sel.success : Sel.ink,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (done) ...[
                    const SizedBox(height: SelSpace.x6),
                    Center(
                      child: SelButton.cyan(
                        label: 'Done',
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One entry sliding into the tally.
class _Line extends StatelessWidget {
  const _Line({
    required this.entry,
    required this.formatMoney,
    required this.isNewest,
  });

  final PartnershipEntry entry;
  final String Function(num) formatMoney;
  final bool isNewest;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SelSpace.cardPad,
        vertical: SelSpace.x2 + 2,
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.check, size: 14, color: Sel.success),
          const SizedBox(width: SelSpace.x3),
          Expanded(
            child: Text(
              entry.partnerSnapshot['fullName']?.toString() ?? '—',
              style: isNewest ? SelType.bodyMedium : SelType.bodyMuted,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            formatMoney(entry.amountCedis),
            style: (isNewest ? SelType.bodyMedium : SelType.bodyMuted).copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );

    if (!isNewest) return row;

    // Slide up and fade the arriving row.
    return TweenAnimationBuilder<double>(
      key: ValueKey(entry.id),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
      ),
      child: row,
    );
  }
}
