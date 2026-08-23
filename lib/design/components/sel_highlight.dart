import 'package:flutter/material.dart';

import '../seline_colors.dart';
import '../seline_metrics.dart';

/// The signature typographic move: one phrase per headline gets cyan-edge text
/// on a soft sky-wash pill.
///
/// Rules, from the style reference and worth honouring strictly — the restraint
/// is the whole point:
/// * **Exactly one per headline.** Never two.
/// * Never inside body copy, never on nav items, never on a button.
/// * It always lands on the value word — the name, the number, the verb that
///   matters — because it carries the headline's entire chromatic budget.
class SelHighlight extends StatelessWidget {
  const SelHighlight({
    super.key,
    this.before = '',
    required this.highlight,
    this.after = '',
    required this.style,
    this.textAlign = TextAlign.start,
    this.maxLines,
  });

  final String before;

  /// The phrase that gets the wash. One or two words.
  final String highlight;

  final String after;
  final TextStyle style;
  final TextAlign textAlign;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final base = style.color == null ? style.copyWith(color: Sel.ink) : style;

    return Text.rich(
      TextSpan(
        children: [
          if (before.isNotEmpty) TextSpan(text: before),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: _Wash(text: highlight, style: base),
          ),
          if (after.isNotEmpty) TextSpan(text: after),
        ],
      ),
      style: base,
      textAlign: textAlign,
      maxLines: maxLines,
    );
  }
}

class _Wash extends StatelessWidget {
  const _Wash({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    // Padding scales with the type size so the pill hugs large display text
    // the same way it hugs a 20px subtitle.
    final size = style.fontSize ?? 16;
    final hPad = (size * 0.16).clamp(4.0, 12.0);
    final vPad = (size * 0.04).clamp(1.0, 4.0);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: Sel.skyWash,
        borderRadius: BorderRadius.circular(SelRadius.icon),
      ),
      child: Text(text, style: style.copyWith(color: Sel.cyanEdge)),
    );
  }
}
