import 'package:flutter/material.dart';

import '../seline_colors.dart';
import '../seline_metrics.dart';
import '../seline_type.dart';
import 'sel_card.dart';

/// Stat tile — a caption, a big quiet number, and an optional footnote.
///
/// The number is set in the display face at weight 400. In most systems a KPI
/// would be bold; here the size alone carries it, which is what keeps a row of
/// four tiles calm instead of shouty.
class SelStat extends StatelessWidget {
  const SelStat({
    super.key,
    required this.label,
    required this.value,
    this.footnote,
    this.icon,
    this.onTap,
    this.exactValue,
  });

  final String label;
  final String value;

  /// The unrounded figure, shown on hover when [value] is an abbreviation.
  final String? exactValue;
  final String? footnote;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SelCard(
      onTap: onTap,
      padding: const EdgeInsets.all(SelSpace.x6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: SelType.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (icon != null) Icon(icon, size: 14, color: Sel.ash),
            ],
          ),
          const SizedBox(height: SelSpace.x2),
          // Scale down before truncating. An ellipsised total tells you
          // neither the amount nor its size.
          Tooltip(
            message: exactValue ?? '',
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: SelType.title.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
          if (footnote != null) ...[
            const SizedBox(height: SelSpace.x1),
            Text(
              footnote!,
              style: SelType.small,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

/// Responsive row of stat tiles. Wraps to two columns, then one.
class SelStatRow extends StatelessWidget {
  const SelStatRow({super.key, required this.stats});

  final List<Widget> stats;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final perRow = c.maxWidth >= 900
            ? stats.length.clamp(1, 4)
            : c.maxWidth >= 520
                ? 2
                : 1;
        const gap = SelSpace.x4;
        final w = (c.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final s in stats) SizedBox(width: w, child: s)],
        );
      },
    );
  }
}

/// Thin progress bar on a stone track.
///
/// [color] carries the arm's identity so a column of goals is separable at a
/// glance. Falls back to Ink where there is no category to express.
class SelProgress extends StatelessWidget {
  const SelProgress({
    super.key,
    required this.value,
    this.height = 4,
    this.color,
  });

  /// 0..1
  final double value;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(SelRadius.pill),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: height,
        backgroundColor: Sel.border,
        color: color ?? Sel.ink,
      ),
    );
  }
}

/// A labelled goal line: name, progress bar, and figures beneath.
class SelGoalLine extends StatelessWidget {
  const SelGoalLine({
    super.key,
    required this.label,
    required this.value,
    required this.target,
    required this.valueText,
    required this.targetText,
    this.color,
  });

  final String label;
  final num value;
  final num target;
  final String valueText;
  final String targetText;

  /// The arm's identity colour. Also tints the bullet beside the label.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final pct = target <= 0 ? 0.0 : (value / target).clamp(0.0, 1.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (color != null) ...[
              Container(
                height: 7,
                width: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: SelSpace.x2),
            ],
            Expanded(child: Text(label, style: SelType.bodyMedium)),
            Text('${(pct * 100).round()}%', style: SelType.bodyMuted),
          ],
        ),
        const SizedBox(height: SelSpace.x2),
        SelProgress(value: pct, color: color),
        const SizedBox(height: SelSpace.x1 + 2),
        Text('$valueText of $targetText', style: SelType.small),
      ],
    );
  }
}
