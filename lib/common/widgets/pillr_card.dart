import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// The base card: Paper surface, 1px Fog hairline, 16px radius, 32px padding.
///
/// Flat by design. Separation comes from the border and from Mist contrast —
/// never from a shadow.
class PillrCard extends StatelessWidget {
  const PillrCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    this.noBorder = false,
    this.surface = PillrCardSurface.paper,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool noBorder;

  /// Paper (level 0) by default; Mist (level 1) for nested or inset panels.
  final PillrCardSurface surface;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      decoration: BoxDecoration(
        color: surface == PillrCardSurface.paper ? AppColors.paper : AppColors.mist,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: noBorder
            ? null
            : Border.all(color: AppColors.fog, width: AppBorders.hairline),
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return content;

    return _CardHover(borderRadius: AppRadius.card, onTap: onTap!, child: content);
  }
}

enum PillrCardSurface { paper, mist }

/// Paper surface with clipped contents — for cards wrapping tables or images.
class PillrSurfaceCard extends StatelessWidget {
  const PillrSurfaceCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.fog, width: AppBorders.hairline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: padding != null ? Padding(padding: padding!, child: child) : child,
      ),
    );
  }
}

/// The inverse block — Charcoal fill, Paper text, used once per screen at most
/// for a final call to action.
class PillrInverseCard extends StatelessWidget {
  const PillrInverseCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.charcoal,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Hover affordance: a Mist wash and an Ink border. No lift, no shadow.
class _CardHover extends StatefulWidget {
  const _CardHover({
    required this.child,
    required this.onTap,
    required this.borderRadius,
  });

  final Widget child;
  final VoidCallback onTap;
  final double borderRadius;

  @override
  State<_CardHover> createState() => _CardHoverState();
}

class _CardHoverState extends State<_CardHover> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: _hovered ? AppColors.ink : Colors.transparent,
              width: AppBorders.hairline,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
