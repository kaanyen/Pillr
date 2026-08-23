import 'package:flutter/material.dart';

import '../seline_colors.dart';
import '../seline_metrics.dart';
import '../seline_type.dart';
import 'sel_highlight.dart';

/// Page heading.
///
/// Headings sit **directly on the warm canvas**, never inside a card — the
/// canvas holds nav and titles, cards hold content. That separation is what
/// makes the cards read as floating objects rather than page regions.
class SelPageTitle extends StatelessWidget {
  const SelPageTitle({
    super.key,
    required this.title,
    this.highlight,
    this.titleSuffix,
    this.subtitle,
    this.actions = const [],
    this.hero = false,
  });

  /// Hero variant: 52px display type, for the Overview only.
  const SelPageTitle.hero({
    super.key,
    required this.title,
    this.highlight,
    this.titleSuffix,
    this.subtitle,
    this.actions = const [],
  }) : hero = true;

  final String title;

  /// The single sky-wash highlighted phrase. One per screen, at most.
  final String? highlight;

  final String? titleSuffix;
  final String? subtitle;
  final List<Widget> actions;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final style = hero ? SelType.heroFor(w) : SelType.titleFor(w);

    return Padding(
      padding: EdgeInsets.only(bottom: hero ? SelSpace.x8 : SelSpace.x6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (highlight != null)
                  SelHighlight(
                    before: title,
                    highlight: highlight!,
                    after: titleSuffix ?? '',
                    style: style,
                  )
                else
                  Text(title, style: style),
                if (subtitle != null) ...[
                  SizedBox(height: hero ? SelSpace.x4 : SelSpace.x2),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: SelLayout.prose),
                    child: Text(
                      subtitle!,
                      style: hero ? SelType.lead : SelType.bodyMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: SelSpace.x4),
            Padding(
              padding: const EdgeInsets.only(top: SelSpace.x1),
              child: Wrap(
                spacing: SelSpace.x2,
                runSpacing: SelSpace.x2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actions,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Label above a block of cards, sitting on the canvas.
class SelSectionLabel extends StatelessWidget {
  const SelSectionLabel({super.key, required this.label, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SelSpace.x3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: SelType.subtitle)),
          ?trailing,
        ],
      ),
    );
  }
}

/// Vertical rhythm between blocks. 96px on desktop, 64px below.
class SelSectionGap extends StatelessWidget {
  const SelSectionGap({super.key, this.factor = 1});

  final double factor;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: SelLayout.sectionGap(MediaQuery.sizeOf(context).width) * factor,
      );
}

/// Scrolling body for a screen: centres content at 1200px on the canvas and
/// applies the page gutters. Every screen's root.
class SelPageBody extends StatelessWidget {
  const SelPageBody({
    super.key,
    required this.children,
    this.maxWidth = SelLayout.maxWidth,
    this.onRefresh,
    this.controller,
  });

  final List<Widget> children;
  final double maxWidth;
  final Future<void> Function()? onRefresh;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final gutter = SelLayout.isCompact(w) ? SelSpace.x4 : SelSpace.x8;
    // The utility cluster floats on the canvas at the top right rather than
    // sitting in a bar, so the content column has to reserve headroom for it —
    // otherwise a page's own actions collide with the account chip.
    const clusterHeadroom = 72.0;

    final scroll = SingleChildScrollView(
      controller: controller,
      physics: onRefresh != null
          ? const AlwaysScrollableScrollPhysics()
          : null,
      padding: EdgeInsets.fromLTRB(gutter, clusterHeadroom, gutter, SelSpace.x20),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );

    if (onRefresh == null) return scroll;
    return RefreshIndicator(
      onRefresh: onRefresh!,
      color: Sel.ink,
      backgroundColor: Sel.card,
      child: scroll,
    );
  }
}
