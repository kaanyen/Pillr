import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/router/auth_boot_gate.dart';
import '../remove_web_splash.dart';
import '../seline_colors.dart';
import '../seline_metrics.dart';
import '../seline_type.dart';
import 'pillr_mark.dart';

/// The splash: the mark builds once on the app's own page colour, the name
/// appears under it, and if the church is still loading after a second the
/// mark turns into the loader. From the canvas board "Splash and loader".
class PillrSplash extends StatefulWidget {
  const PillrSplash({super.key, this.waiting = false});

  /// Still loading after [PillrMarkMotion.waitingAfter].
  final bool waiting;

  @override
  State<PillrSplash> createState() => _PillrSplashState();
}

class _PillrSplashState extends State<PillrSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _word = AnimationController(
    vsync: this,
    duration: PillrMarkMotion.word,
  );
  Timer? _wordDelay;

  @override
  void initState() {
    super.initState();
    _wordDelay = Timer(PillrMarkMotion.wordDelay, () {
      if (mounted) _word.forward();
    });
  }

  @override
  void dispose() {
    _wordDelay?.cancel();
    _word.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final word = CurvedAnimation(parent: _word, curve: PillrMarkMotion.easeOut);
    return ColoredBox(
      color: Sel.canvas,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PillrMark(
              size: 120,
              mode: widget.waiting
                  ? PillrMarkMode.loop
                  : PillrMarkMode.assemble,
            ),
            const SizedBox(height: 22),
            FadeTransition(
              opacity: word,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.1),
                  end: Offset.zero,
                ).animate(word),
                child: Text(
                  'pillr',
                  style: SelType.hero.copyWith(
                    fontSize: 44,
                    height: 1,
                    letterSpacing: -2.4,
                  ),
                ),
              ),
            ),
            const SizedBox(height: SelSpace.x8),
            AnimatedOpacity(
              opacity: widget.waiting ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Text(
                'Still loading your church…',
                style: SelType.bodySm,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Covers the app until sign-in has been checked, then fades away.
///
/// On web the HTML splash in web/index.html has already started the build;
/// this takes over on Flutter's first frame with the same mark on the same
/// colour, so the hand-off has no flash. Ready in under 300 ms: no splash.
class PillrBootSplash extends StatefulWidget {
  const PillrBootSplash({super.key, required this.child});

  final Widget child;

  @override
  State<PillrBootSplash> createState() => _PillrBootSplashState();
}

class _PillrBootSplashState extends State<PillrBootSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _out = AnimationController(
    vsync: this,
    duration: PillrMarkMotion.handoff,
  );
  final _started = DateTime.now();
  Timer? _waitingTimer;
  Timer? _failsafe;
  bool _waiting = false;
  bool _cover = true;

  @override
  void initState() {
    super.initState();
    AuthBootGate.ready.addListener(_onReady);
    _waitingTimer = Timer(PillrMarkMotion.waitingAfter, () {
      if (mounted && _cover) setState(() => _waiting = true);
    });
    // Hot reload can reset the gate without re-running main(); never leave
    // the cover up for good.
    _failsafe = Timer(const Duration(seconds: 5), _uncover);
    WidgetsBinding.instance.addPostFrameCallback((_) => removeWebSplash());
    if (AuthBootGate.settled) scheduleMicrotask(_onReady);
  }

  void _onReady() {
    if (!AuthBootGate.settled || !_cover || !mounted) return;
    if (DateTime.now().difference(_started) <
        PillrMarkMotion.skipIfFasterThan) {
      _uncover();
      return;
    }
    _out.forward().whenComplete(_uncover);
  }

  void _uncover() {
    if (mounted && _cover) setState(() => _cover = false);
  }

  @override
  void dispose() {
    AuthBootGate.ready.removeListener(_onReady);
    _waitingTimer?.cancel();
    _failsafe?.cancel();
    _out.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_cover) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        FadeTransition(
          opacity: Tween<double>(begin: 1, end: 0).animate(_out),
          child: IgnorePointer(child: PillrSplash(waiting: _waiting)),
        ),
      ],
    );
  }
}
