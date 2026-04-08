import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// One-time fade + slide for dashboard stat grids (respects reduced motion).
class FadeInOnce extends StatefulWidget {
  const FadeInOnce({
    super.key,
    required this.child,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration delay;

  @override
  State<FadeInOnce> createState() => _FadeInOnceState();
}

class _FadeInOnceState extends State<FadeInOnce> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(widget.delay, () {
        if (mounted) setState(() => _ready = true);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!_ready) return Opacity(opacity: 0, child: widget.child);
    if (reduced) return widget.child;
    return widget.child
        .animate()
        .fadeIn(duration: 320.ms, curve: Curves.easeOutCubic)
        .slideY(begin: 0.06, end: 0, duration: 320.ms, curve: Curves.easeOutCubic);
  }
}
