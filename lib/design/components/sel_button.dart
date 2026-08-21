import 'package:flutter/material.dart';

import '../seline_colors.dart';
import '../seline_metrics.dart';
import '../seline_type.dart';

/// Button hierarchy in Seline.
///
/// The cyan fill is the entire chromatic budget of the interface, so there is
/// **one [cyan] button per viewport** and everything else is a ghost pill. That
/// restraint is what makes an action feel switched on without needing size.
enum SelButtonKind {
  /// Cyan fill, white label. The single primary action.
  cyan,

  /// Transparent, stone hairline, ink label. Every other action.
  ghost,

  /// Text only, warm gray, no border. Tertiary and inline actions.
  quiet,

  /// Ghost pill whose label and icon are cyan-edge. For destructive or
  /// stateful actions that need to read as interactive without taking the
  /// primary slot. Still not a fill — never promote cyanEdge to a fill.
  edge,
}

class SelButton extends StatelessWidget {
  const SelButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = SelButtonKind.ghost,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.expanded = false,
    this.dense = false,
  });

  /// Convenience for the one primary action on a screen.
  const SelButton.cyan({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.expanded = false,
    this.dense = false,
  }) : kind = SelButtonKind.cyan;

  final String label;
  final VoidCallback? onPressed;
  final SelButtonKind kind;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool loading;
  final bool expanded;

  /// Tightens the pill for toolbar rows.
  final bool dense;

  bool get _disabled => onPressed == null || loading;

  Color get _fg {
    if (_disabled) return Sel.ash;
    return switch (kind) {
      SelButtonKind.cyan => Sel.card,
      SelButtonKind.ghost => Sel.ink,
      SelButtonKind.quiet => Sel.warm,
      SelButtonKind.edge => Sel.cyanEdge,
    };
  }

  @override
  Widget build(BuildContext context) {
    final pad = dense
        ? const EdgeInsets.symmetric(horizontal: SelSpace.x3, vertical: SelSpace.x1)
        : const EdgeInsets.symmetric(horizontal: SelSpace.x4, vertical: SelSpace.x2);
    final minH = dense ? 28.0 : 34.0;

    final body = loading
        ? SizedBox(
            height: 14,
            width: 14,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: _fg),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: _fg),
                const SizedBox(width: SelSpace.x2),
              ],
              Flexible(
                child: Text(
                  label,
                  style: SelType.button.copyWith(color: _fg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: SelSpace.x2),
                Icon(trailingIcon, size: 14, color: _fg),
              ],
            ],
          );

    final btn = _SelPill(
      kind: kind,
      disabled: _disabled,
      padding: pad,
      minHeight: minH,
      onTap: _disabled ? null : onPressed,
      child: body,
    );

    return expanded ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// The shared pill body. Hover is a fill/border shift, never a lift — the
/// shadow budget belongs to cards, not controls.
class _SelPill extends StatefulWidget {
  const _SelPill({
    required this.kind,
    required this.disabled,
    required this.padding,
    required this.minHeight,
    required this.onTap,
    required this.child,
  });

  final SelButtonKind kind;
  final bool disabled;
  final EdgeInsets padding;
  final double minHeight;
  final VoidCallback? onTap;
  final Widget child;

  @override
  State<_SelPill> createState() => _SelPillState();
}

class _SelPillState extends State<_SelPill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final h = _hover && !widget.disabled;

    final (Color bg, Color? bd) = switch (widget.kind) {
      SelButtonKind.cyan => widget.disabled
          ? (Sel.borderMuted, null)
          : (h ? Sel.cyanEdge : Sel.cyan, Sel.cyanEdge),
      SelButtonKind.ghost => (h ? Sel.card : Colors.transparent, Sel.border),
      SelButtonKind.quiet => (h ? Sel.card : Colors.transparent, null),
      SelButtonKind.edge => (h ? Sel.skyWash : Colors.transparent, Sel.cyanEdge),
    };

    return MouseRegion(
      cursor: widget.disabled
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          constraints: BoxConstraints(minHeight: widget.minHeight),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(SelRadius.pill),
            border: bd == null ? null : Border.all(color: bd),
          ),
          child: Center(widthFactor: 1, child: widget.child),
        ),
      ),
    );
  }
}

/// Icon-only round control for toolbars. Reads as chrome, not as an action.
class SelIconButton extends StatelessWidget {
  const SelIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 18,
    this.badge,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;

  /// Small count rendered as a soot dot on the icon's shoulder.
  final int? badge;

  @override
  Widget build(BuildContext context) {
    Widget child = Icon(icon, size: size, color: Sel.warm);

    if (badge != null && badge! > 0) {
      child = Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 14),
              decoration: const BoxDecoration(
                color: Sel.soot,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$badge',
                textAlign: TextAlign.center,
                style: SelType.small.copyWith(
                  color: Sel.card,
                  fontSize: 9,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      );
    }

    final btn = _SelPill(
      kind: SelButtonKind.quiet,
      disabled: onPressed == null,
      padding: const EdgeInsets.all(SelSpace.x2),
      minHeight: 32,
      onTap: onPressed,
      child: child,
    );

    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}
