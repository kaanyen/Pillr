import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/errors/plain_error.dart';
import '../seline_colors.dart';
import '../seline_metrics.dart';
import '../seline_type.dart';

/// What a long action reports while it works (canvas 69, 71, 73, 74).
///
/// Actions done record by record call [start] with the count, then [tick]
/// for each record as they reach it. Actions done on the server in one call
/// have no count; they pass named [steps] and move through them with [step].
class SelWork extends ChangeNotifier {
  SelWork({List<String>? steps}) : steps = steps ?? const [];

  final List<String> steps;
  int? total;
  int done = 0;
  int stepAt = 0;

  /// The record being worked on now, in plain words.
  String? now;

  /// A running figure, such as "₵9,850.00 so far".
  String? running;

  /// The last few records finished, newest first.
  final List<String> log = [];

  void start(int count) {
    total = count;
    done = 0;
    notifyListeners();
  }

  /// [label] is the record now being worked on. The one before it moves to
  /// the list of finished ones.
  void tick(String label, {String? running}) {
    if (now != null) {
      log.insert(0, now!);
      if (log.length > 3) log.removeLast();
    }
    now = label;
    if (running != null) this.running = running;
    done = (done + 1).clamp(0, total ?? 1 << 30);
    notifyListeners();
  }

  void step(int index) {
    stepAt = index.clamp(0, steps.isEmpty ? 0 : steps.length - 1);
    notifyListeners();
  }
}

/// One line of the summary: what happened, ticked, or something to look at.
class SelSummaryLine {
  const SelSummaryLine(this.title, {this.detail, this.ok = true});

  final String title;
  final String? detail;
  final bool ok;
}

/// A button on the summary besides Done: the way back, or where to look.
class SelSummaryAction {
  const SelSummaryAction(this.label, this.onTap, {this.link = false});

  final String label;
  final VoidCallback onTap;

  /// Shown as a plain link rather than a button.
  final bool link;
}

/// What happened, shown when the action finishes (canvas 70, 72).
class SelSummary {
  const SelSummary({
    required this.title,
    this.subtitle,
    this.numbers = const [],
    this.lines = const [],
    this.actions = const [],
  });

  final String title;
  final String? subtitle;

  /// Up to three big figures: (value, what it is).
  final List<(String, String)> numbers;
  final List<SelSummaryLine> lines;
  final List<SelSummaryAction> actions;
}

/// Runs [run] behind a progress window that cannot be dismissed while it
/// works, then turns the window into the summary [run] returns. If [run]
/// throws, the window says what was done before it stopped and what went
/// wrong, in plain words.
///
/// Returns true when it finished, false when it stopped on an error.
Future<bool> runWithProgress(
  BuildContext context, {
  required String title,
  String? subtitle,
  List<String>? steps,
  /// Close as soon as it finishes, when the page itself shows what happened
  /// (Bring in a sheet ends on its own summary page).
  bool closeWhenDone = false,
  required Future<SelSummary> Function(SelWork p) run,
}) async {
  final progress = SelWork(steps: steps);
  final result = Completer<SelSummary?>();
  Object? failure;
  final started = DateTime.now();
  unawaited(() async {
    try {
      result.complete(await run(progress));
    } catch (e) {
      failure = e;
      result.complete(null);
    }
  }());
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: _ProgressDialog(
        title: title,
        subtitle: subtitle,
        progress: progress,
        result: result.future,
        failure: () => failure,
        started: started,
        closeWhenDone: closeWhenDone,
      ),
    ),
  );
  progress.dispose();
  return ok ?? failure == null;
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.result,
    required this.failure,
    required this.started,
    required this.closeWhenDone,
  });

  final bool closeWhenDone;

  final String title;
  final String? subtitle;
  final SelWork progress;
  final Future<SelSummary?> result;
  final Object? Function() failure;
  final DateTime started;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Sel.card,
    insetPadding: const EdgeInsets.all(SelSpace.x4),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 540),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
        child: FutureBuilder<SelSummary?>(
          future: result,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return _Working(title: title, subtitle: subtitle, progress: progress);
            }
            final s = snap.data;
            if (s != null && closeWhenDone) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) Navigator.of(context).pop(true);
              });
              return _Working(title: title, subtitle: subtitle, progress: progress);
            }
            if (s == null) {
              return _Stopped(title: title, progress: progress, error: failure());
            }
            return _Done(summary: s, seconds: DateTime.now().difference(started).inSeconds);
          },
        ),
      ),
    ),
  );
}

class _Working extends StatelessWidget {
  const _Working({required this.title, required this.subtitle, required this.progress});

  final String title;
  final String? subtitle;
  final SelWork progress;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: progress,
    builder: (context, _) {
      final total = progress.total;
      final share = total == null || total == 0 ? null : progress.done / total;
      return SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: SelType.subtitle.copyWith(fontSize: 21, color: Sel.ink, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(subtitle ?? 'Keep this page open; it takes a few seconds.', style: SelType.bodySm),
            const SizedBox(height: 18),
            Semantics(
              label: total == null ? 'Working' : '${progress.done} of $total',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LinearProgressIndicator(
                  value: share,
                  minHeight: 12,
                  backgroundColor: Sel.track,
                  valueColor: const AlwaysStoppedAnimation(Sel.sky),
                ),
              ),
            ),
            if (total != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${progress.done} of $total',
                          style: const TextStyle(color: Sel.ink, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    style: SelType.small,
                  ),
                  const Spacer(),
                  if (progress.running != null) Text(progress.running!, style: SelType.small),
                ],
              ),
            ],
            if (progress.steps.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (var i = 0; i < progress.steps.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      _Dot(
                        state: i < progress.stepAt ? _DotState.done : (i == progress.stepAt ? _DotState.now : _DotState.todo),
                        number: i + 1,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          progress.steps[i],
                          style: SelType.bodySm.copyWith(
                            color: i == progress.stepAt ? Sel.ink : Sel.warm,
                            fontWeight: i == progress.stepAt ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (progress.now != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: Sel.skyTint, borderRadius: BorderRadius.circular(14)),
                child: Semantics(
                  liveRegion: true,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'Now: '),
                        TextSpan(text: progress.now, style: const TextStyle(fontWeight: FontWeight.w800)),
                      ],
                    ),
                    style: SelType.bodySm.copyWith(color: Sel.ink),
                  ),
                ),
              ),
            ],
            if (progress.log.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final l in progress.log)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const _Dot(state: _DotState.done, number: 0, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(l, overflow: TextOverflow.ellipsis, style: SelType.small)),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 14),
            Text(
              'If it stops, nothing is half done: what was finished shows in the summary.',
              style: SelType.small,
            ),
          ],
        ),
      );
    },
  );
}

class _Done extends StatelessWidget {
  const _Done({required this.summary, required this.seconds});

  final SelSummary summary;
  final int seconds;

  @override
  Widget build(BuildContext context) {
    void close() => Navigator.of(context).pop(true);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(color: Sel.skyWash, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, color: Sel.ink),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(summary.title, style: SelType.subtitle.copyWith(fontSize: 21, color: Sel.ink, fontWeight: FontWeight.w800)),
                    Text(
                      summary.subtitle ?? (seconds < 2 ? 'Done.' : 'Done in $seconds seconds.'),
                      style: SelType.bodySm,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (summary.numbers.isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                for (final (i, (value, label)) in summary.numbers.take(3).indexed) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(color: const Color(0xFFF3F8FD), borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              value,
                              style: SelType.subtitle.copyWith(
                                color: Sel.ink,
                                fontWeight: FontWeight.w800,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                          Text(label, style: SelType.small),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
          if (summary.lines.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final (i, l) in summary.lines.indexed) ...[
              if (i > 0) const Divider(height: 1, color: Sel.rowLine),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Dot(state: l.ok ? _DotState.done : _DotState.look, number: 0, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.title, style: SelType.bodySm.copyWith(color: Sel.ink, fontWeight: FontWeight.w700)),
                          if (l.detail != null) Text(l.detail!, style: SelType.small),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _PillButton(label: 'Done', primary: true, onTap: close),
              for (final a in summary.actions)
                a.link
                    ? TextButton(
                        onPressed: () {
                          close();
                          a.onTap();
                        },
                        child: Text(a.label, style: SelType.bodySm.copyWith(color: Sel.cyanEdge, fontWeight: FontWeight.w700)),
                      )
                    : _PillButton(
                        label: a.label,
                        onTap: () {
                          close();
                          a.onTap();
                        },
                      ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stopped extends StatelessWidget {
  const _Stopped({required this.title, required this.progress, required this.error});

  final String title;
  final SelWork progress;
  final Object? error;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const _Dot(state: _DotState.look, number: 0, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              '$title stopped',
              style: SelType.subtitle.copyWith(fontSize: 21, color: Sel.ink, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      if (progress.total != null)
        Text(
          '${progress.done == 0 ? 'Nothing' : '${progress.done} of ${progress.total}'} was done before it stopped. '
          'Nothing is half done.',
          style: SelType.bodySm.copyWith(color: Sel.text),
        ),
      const SizedBox(height: 8),
      Text(plainError(error), style: SelType.bodySm.copyWith(color: Sel.ink, fontWeight: FontWeight.w700)),
      const SizedBox(height: 18),
      Align(
        alignment: Alignment.centerLeft,
        child: _PillButton(label: 'Close', primary: true, onTap: () => Navigator.of(context).pop(false)),
      ),
    ],
  );
}

enum _DotState { done, now, todo, look }

class _Dot extends StatelessWidget {
  const _Dot({required this.state, required this.number, this.size = 22});

  final _DotState state;
  final int number;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (fill, edge, fg) = switch (state) {
      _DotState.done => (Sel.skyWash, Sel.skyWash, Sel.ink),
      _DotState.now => (Sel.ink, Sel.ink, Sel.card),
      _DotState.todo => (Sel.card, const Color(0xFFC9D6E3), Sel.warm),
      _DotState.look => (Sel.card, Sel.ink, Sel.ink),
    };
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle, border: Border.all(color: edge, width: 1.5)),
      child: switch (state) {
        _DotState.done => Icon(Icons.check_rounded, size: size * .55, color: fg),
        _DotState.look => Text('!', style: TextStyle(fontSize: size * .5, fontWeight: FontWeight.w900, color: fg)),
        _ => Text('$number', style: TextStyle(fontSize: size * .5, fontWeight: FontWeight.w800, color: fg)),
      },
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap, this.primary = false});

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => Material(
    color: primary ? Sel.ink : Sel.card,
    shape: StadiumBorder(side: primary ? BorderSide.none : const BorderSide(color: Sel.border, width: 1.5)),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Text(label, style: SelType.button.copyWith(color: primary ? Sel.card : Sel.text)),
        ),
      ),
    ),
  );
}

/// For an action the server does in one call: the first step while it is
/// sent, the middle steps while it works, the last when it answers. The
/// server does not report each record, so the steps say what it is doing
/// rather than counting.
Future<T> runServerSteps<T>(SelWork p, Future<T> Function() call) async {
  p.step(0);
  await Future<void>.delayed(const Duration(milliseconds: 350));
  if (p.steps.length > 1) p.step(1);
  final r = await call();
  p.step(p.steps.length - 1);
  return r;
}
