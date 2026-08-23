import 'package:flutter/material.dart';

import '../seline_colors.dart';
import '../seline_metrics.dart';
import '../seline_type.dart';

/// Elevation intent for a [SelCard].
enum SelLift {
  /// Border only. For cards nested inside another card, where a shadow would
  /// stack and read as noise.
  flat,

  /// The default — 1px stone hairline plus the soft 16px-blur shadow.
  /// The border is the structure; the shadow only stops it lying flat.
  card,

  /// The deep 45px-blur shadow. **One per screen at most.** Reserved for a
  /// hero surface; never a list row, never a repeated tile.
  floating,
}

/// The flat white card — the workhorse surface of the system.
///
/// White on the warm canvas, 10px radius, 24px padding, stone hairline. Every
/// piece of content in the app lives inside one of these; the canvas itself
/// never holds content directly except nav links and page headings.
class SelCard extends StatelessWidget {
  const SelCard({
    super.key,
    required this.child,
    this.padding,
    this.lift = SelLift.card,
    this.radius = SelRadius.card,
    this.onTap,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final SelLift lift;
  final double radius;
  final VoidCallback? onTap;

  /// Clip contents to the radius — for cards wrapping images or full-bleed rows.
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final pad = padding ??
        EdgeInsets.all(SelLayout.cardPadding(MediaQuery.sizeOf(context).width));

    final shadows = switch (lift) {
      SelLift.flat => const <BoxShadow>[],
      SelLift.card => SelShadow.card,
      SelLift.floating => SelShadow.floating,
    };

    Widget body = Container(
      decoration: BoxDecoration(
        color: Sel.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Sel.border),
        boxShadow: shadows,
      ),
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      child: Padding(padding: pad, child: child),
    );

    if (onTap != null) body = _Hoverable(radius: radius, onTap: onTap!, child: body);
    return body;
  }
}

/// Inverted panel — Soot fill, white text. Surface level 3, used sparingly:
/// an active tab pill, or one emphasis block per screen.
class SelInverseCard extends StatelessWidget {
  const SelInverseCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(SelSpace.cardPad),
    this.radius = SelRadius.card,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Sel.soot,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// A card with a title row and a hairline beneath it, then content.
/// The standard container for a labelled block.
class SelPanel extends StatelessWidget {
  const SelPanel({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.lift = SelLift.card,
    this.contentPadding,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  final SelLift lift;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    return SelCard(
      lift: lift,
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SelSpace.cardPad,
              SelSpace.x4,
              SelSpace.x3,
              SelSpace.x4,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: SelType.subtitle),
                      if (subtitle != null) ...[
                        const SizedBox(height: SelSpace.x1),
                        Text(subtitle!, style: SelType.bodySm),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          const Divider(height: 1, color: Sel.border),
          Padding(
            padding: contentPadding ?? const EdgeInsets.all(SelSpace.cardPad),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _Hoverable extends StatefulWidget {
  const _Hoverable({required this.radius, required this.onTap, required this.child});

  final double radius;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<_Hoverable> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(
              color: _hover ? Sel.borderMuted : Colors.transparent,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
