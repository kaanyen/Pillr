import 'package:flutter/material.dart';

import '../seline_colors.dart';

/// How a [PillrMark] moves.
enum PillrMarkMode {
  /// Drawn whole, no motion: the sidebar, headers.
  still,

  /// Built once, base first and the sky capital last: the splash.
  assemble,

  /// Built, held, faded, built again: the loader.
  loop,
}

/// Timing for the mark, from the canvas board "Splash and loader".
abstract final class PillrMarkMotion {
  /// The whole build, tile to capital.
  static const assemble = Duration(milliseconds: 600);

  /// One loader cycle.
  static const loop = Duration(milliseconds: 1400);

  /// When the name appears under the mark on the splash.
  static const wordDelay = Duration(milliseconds: 560);
  static const word = Duration(milliseconds: 200);

  /// Still loading after this: the splash mark turns into the loader.
  static const waitingAfter = Duration(milliseconds: 1100);

  /// Ready this fast: show no splash at all, a flash of logo is worse.
  static const skipIfFasterThan = Duration(milliseconds: 300);

  /// The splash fading into the first page.
  static const handoff = Duration(milliseconds: 200);

  /// Strong ease-out, cubic-bezier(0.23, 1, 0.32, 1).
  static const easeOut = Cubic(0.23, 1, 0.32, 1);
}

/// The Pillr mark: a navy tile holding four stacked courses — a white base,
/// two white drums, and the sky capital on top.
///
/// [onColor] draws the courses alone, white with a light-sky capital, for
/// use on a filled surface such as a primary button.
class PillrMark extends StatefulWidget {
  const PillrMark({
    super.key,
    this.size = 48,
    this.mode = PillrMarkMode.still,
    this.onColor = false,
  });

  final double size;
  final PillrMarkMode mode;
  final bool onColor;

  @override
  State<PillrMark> createState() => _PillrMarkState();
}

class _PillrMarkState extends State<PillrMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant PillrMark old) {
    super.didUpdateWidget(old);
    if (old.mode != widget.mode) _start();
  }

  void _start() {
    switch (widget.mode) {
      case PillrMarkMode.still:
        _c
          ..stop()
          ..value = 1;
      case PillrMarkMode.assemble:
        _c
          ..duration = PillrMarkMotion.assemble
          ..forward(from: 0);
      case PillrMarkMode.loop:
        _c
          ..duration = PillrMarkMotion.loop
          ..repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      label: widget.mode == PillrMarkMode.loop ? 'Loading' : 'Pillr',
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _MarkPainter(
              poses: _poses(widget.mode, _c.value, reduce),
              onColor: widget.onColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// Opacity and vertical offset (in 48-unit mark space) of one part.
typedef _Pose = ({double opacity, double dy});

const _shown = (opacity: 1.0, dy: 0.0);

/// Tile, base, drum, drum, capital — where each is at time [t] (0–1).
List<_Pose> _poses(PillrMarkMode mode, double t, bool reduce) {
  if (mode == PillrMarkMode.still) return List.filled(5, _shown);

  if (mode == PillrMarkMode.assemble) {
    if (reduce) {
      final o = (t / 0.33).clamp(0.0, 1.0);
      return List.filled(5, (opacity: o, dy: 0.0));
    }
    // Starts and lengths in ms over a 600 ms build: the tile, then the base
    // and each drum 70 ms apart, then the capital lowered on.
    _Pose part(double startMs, double lengthMs, double fromDy) {
      final p = ((t * 600 - startMs) / lengthMs).clamp(0.0, 1.0);
      final e = PillrMarkMotion.easeOut.transform(p);
      return (opacity: e, dy: fromDy * (1 - e));
    }

    return [
      part(0, 200, 0),
      part(120, 220, 3),
      part(190, 220, 3),
      part(260, 220, 3),
      part(330, 260, -5),
    ];
  }

  // The loader: build base-up, hold, fade, again.
  if (reduce) {
    // Reduced motion: no building, only a gentle fade.
    final o = 0.75 + 0.25 * (1 - (2 * t - 1).abs());
    return List.filled(5, (opacity: o, dy: 0.0));
  }
  _Pose course(double inStart, double inEnd, double fromDy) {
    if (t < inStart) return (opacity: 0, dy: fromDy);
    if (t < inEnd) {
      final e = PillrMarkMotion.easeOut.transform(
        (t - inStart) / (inEnd - inStart),
      );
      return (opacity: e, dy: fromDy * (1 - e));
    }
    if (t < 0.78) return _shown;
    if (t < 0.92) return (opacity: 1 - (t - 0.78) / 0.14, dy: 0);
    return (opacity: 0, dy: 0);
  }

  return [
    _shown,
    course(0, 0.12, 2.5),
    course(0.12, 0.24, 2.5),
    course(0.24, 0.36, 2.5),
    course(0.36, 0.52, -4),
  ];
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.poses, required this.onColor});

  final List<_Pose> poses;
  final bool onColor;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 48;
    void rrect(Rect r, double radius, Color c, _Pose pose) {
      if (pose.opacity <= 0) return;
      final paint = Paint()..color = c.withValues(alpha: c.a * pose.opacity);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            r.left * k,
            (r.top + pose.dy) * k,
            r.width * k,
            r.height * k,
          ),
          Radius.circular(radius * k),
        ),
        paint,
      );
    }

    if (!onColor) {
      rrect(const Rect.fromLTWH(0, 0, 48, 48), 12, Sel.ink, poses[0]);
    }
    const white = Color(0xFFFFFFFF);
    rrect(const Rect.fromLTWH(11, 36, 26, 5), 2.5, white, poses[1]);
    rrect(const Rect.fromLTWH(16, 26, 16, 7), 3.5, white, poses[2]);
    rrect(const Rect.fromLTWH(16, 16, 16, 7), 3.5, white, poses[3]);
    rrect(
      const Rect.fromLTWH(11, 8, 26, 5),
      2.5,
      onColor ? Sel.skyWash : Sel.sky,
      poses[4],
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.onColor != onColor || old.poses != poses;
}

/// The loader: the mark building on a loop. It replaces the spinning circle
/// everywhere Pillr waits.
class PillrLoader extends StatelessWidget {
  const PillrLoader({super.key, this.size = 32, this.onColor = false});

  final double size;

  /// Bars only, for a filled surface such as a primary button.
  final bool onColor;

  @override
  Widget build(BuildContext context) =>
      PillrMark(size: size, mode: PillrMarkMode.loop, onColor: onColor);
}
