import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// The Electric Blue keyword highlight — the single gradient in the system.
///
/// Renders a headline where one phrase is filled with the left-to-right blue
/// gradient while the rest stays [AppColors.ink]. Think marker pen, not
/// decoration: reserve it for **one or two words per screen**, and only inside
/// a headline. Never a background, never a button, never body copy.
///
/// ```dart
/// PillrGradientHeadline(
///   before: 'Track every ',
///   highlight: 'partnership',
///   after: ' in one place',
///   style: AppTypography.heroFor(width),
/// )
/// ```
class PillrGradientHeadline extends StatelessWidget {
  const PillrGradientHeadline({
    super.key,
    this.before = '',
    required this.highlight,
    this.after = '',
    required this.style,
    this.textAlign = TextAlign.center,
    this.maxLines,
  });

  /// Text preceding the highlighted phrase, in solid Ink.
  final String before;

  /// The phrase that "lights up". Keep it to one or two words.
  final String highlight;

  /// Text following the highlighted phrase, in solid Ink.
  final String after;

  final TextStyle style;
  final TextAlign textAlign;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final inkStyle = style.color == null
        ? style.copyWith(color: AppColors.ink)
        : style;

    return Text.rich(
      TextSpan(
        children: [
          if (before.isNotEmpty) TextSpan(text: before),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: _GradientSpan(text: highlight, style: inkStyle),
          ),
          if (after.isNotEmpty) TextSpan(text: after),
        ],
      ),
      style: inkStyle,
      textAlign: textAlign,
      maxLines: maxLines,
    );
  }
}

class _GradientSpan extends StatelessWidget {
  const _GradientSpan({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => AppColors.electricBlue.createShader(
        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      ),
      child: Text(text, style: style.copyWith(color: AppColors.paper)),
    );
  }
}

/// Applies the gradient to an arbitrary child (an icon, a logo mark, a number).
///
/// Same restraint applies: one per screen at most.
class PillrGradientMask extends StatelessWidget {
  const PillrGradientMask({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => AppColors.electricBlue.createShader(
        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      ),
      child: child,
    );
  }
}
