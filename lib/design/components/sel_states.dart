import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../seline_colors.dart';
import '../seline_metrics.dart';
import '../seline_type.dart';
import 'sel_button.dart';

/// Empty state — quiet by design.
///
/// A hairline-ringed outline glyph, a display-weight line, one sentence of
/// warm-gray copy, and at most one cyan action. No illustration, no colour, no
/// exclamation: an empty list is not an error.
class SelEmpty extends StatelessWidget {
  const SelEmpty({
    super.key,
    required this.title,
    required this.message,
    this.icon = LucideIcons.inbox,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SelSpace.x6,
            vertical: SelSpace.x8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: Sel.canvas,
                  borderRadius: BorderRadius.circular(SelRadius.icon),
                  border: Border.all(color: Sel.border),
                ),
                child: Icon(icon, size: 17, color: Sel.ash),
              ),
              const SizedBox(height: SelSpace.x4),
              Text(title, style: SelType.subtitle, textAlign: TextAlign.center),
              const SizedBox(height: SelSpace.x2),
              Text(message, style: SelType.bodyMuted, textAlign: TextAlign.center),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: SelSpace.x6),
                Wrap(
                  spacing: SelSpace.x2,
                  alignment: WrapAlignment.center,
                  children: [
                    SelButton.cyan(label: actionLabel!, onPressed: onAction),
                    if (secondaryLabel != null && onSecondary != null)
                      SelButton(label: secondaryLabel!, onPressed: onSecondary),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Error state. Monochrome, like every other state here — the failure reads
/// through a Soot glyph block and weight, never through red.
class SelError extends StatelessWidget {
  const SelError({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(SelSpace.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: Sel.soot,
                  borderRadius: BorderRadius.circular(SelRadius.icon),
                ),
                child: const Icon(LucideIcons.alertCircle, size: 17, color: Sel.card),
              ),
              const SizedBox(height: SelSpace.x4),
              Text(
                'Something went wrong',
                style: SelType.subtitle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: SelSpace.x2),
              Text(message, style: SelType.bodyMuted, textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: SelSpace.x6),
                SelButton(label: 'Try again', onPressed: onRetry),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton block for loading states. A slow canvas-to-border pulse — no
/// shimmer sweep, which would be the loudest motion in an otherwise calm UI.
class SelSkeleton extends StatefulWidget {
  const SelSkeleton({
    super.key,
    this.height = 14,
    this.width,
    this.radius = SelRadius.icon,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  State<SelSkeleton> createState() => _SelSkeletonState();
}

class _SelSkeletonState extends State<SelSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: Color.lerp(Sel.canvas, Sel.border, _c.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// A few skeleton rows shaped like a ledger, for list loading states.
class SelSkeletonRows extends StatelessWidget {
  const SelSkeletonRows({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: SelSpace.x3),
            child: Row(
              children: [
                const Expanded(flex: 3, child: SelSkeleton()),
                const SizedBox(width: SelSpace.x4),
                const Expanded(flex: 2, child: SelSkeleton()),
                const SizedBox(width: SelSpace.x4),
                SizedBox(width: 80, child: SelSkeleton(width: 60 + (i % 3) * 10)),
              ],
            ),
          ),
      ],
    );
  }
}
