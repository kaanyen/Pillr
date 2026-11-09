import 'package:flutter/material.dart';

import '../seline_colors.dart';
import '../seline_metrics.dart';

/// 2px ink ring, offset 2px outside the control. Keyboard focus only.
///
/// Painted outside the child's box so a focused pill does not jump. Ink
/// clears 3:1 as a UI component; a 1px cyan tint does not.
class SelFocusRing extends StatelessWidget {
  const SelFocusRing({
    super.key,
    required this.focused,
    required this.child,
    this.radius = SelRadius.pill,
  });

  final bool focused;
  final Widget child;
  final double radius;

  static const double _offset = 4;

  @override
  Widget build(BuildContext context) {
    return Stack(
      // Passthrough, not the default loose fit: a loose Stack lets its child
      // shrink to content, which turned every `expanded: true` button in the
      // app — the full-width Sign in button among them — into a small pill.
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        child,
        if (focused)
          Positioned(
            left: -_offset,
            top: -_offset,
            right: -_offset,
            bottom: -_offset,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius + _offset),
                  border: Border.all(color: Sel.ink, width: 2),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
