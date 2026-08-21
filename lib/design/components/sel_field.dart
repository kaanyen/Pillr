import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../seline_colors.dart';
import '../seline_metrics.dart';
import '../seline_type.dart';

/// Text field with the label above the box, never floating.
///
/// White fill on the warm canvas, 6px radius, stone hairline. Focus is the one
/// place cyan appears outside a button: a 2px cyan ring, per the reference.
class SelField extends StatelessWidget {
  const SelField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.helper,
    this.errorText,
    this.obscureText = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.onSubmitted,
    this.autofillHints,
    this.enabled = true,
    this.maxLines = 1,
    this.readOnly = false,
    this.onTap,
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? helper;
  final String? errorText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  final bool enabled;
  final int maxLines;
  final bool readOnly;
  final VoidCallback? onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      autofillHints: autofillHints,
      enabled: enabled,
      maxLines: maxLines,
      readOnly: readOnly,
      onTap: onTap,
      autofocus: autofocus,
      style: SelType.body,
      cursorColor: Sel.ink,
      cursorWidth: 1.5,
      decoration: InputDecoration(
        // Set explicitly rather than inheriting: a Material fallback fill
        // (grey.shade100) leaks through on some field configurations, which
        // showed up as one input in a form rendering grey while its
        // neighbours rendered white.
        filled: true,
        fillColor: enabled ? Sel.card : Sel.canvas,
        hintText: hint,
        errorText: errorText,
        helperText: helper,
        prefixIcon: prefixIcon == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: SelSpace.x3, right: SelSpace.x2),
                child: Icon(prefixIcon, size: 15, color: Sel.ash),
              ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: suffixIcon,
      ),
    );

    if (label == null || label!.isEmpty) return field;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label!, style: SelType.bodyMedium),
        const SizedBox(height: SelSpace.x2),
        field,
      ],
    );
  }
}

/// Bordered select. Matches [SelField]'s box so a form row reads evenly.
class SelSelect<T> extends StatelessWidget {
  const SelSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.hint,
    this.expanded = true,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? label;
  final Widget? hint;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: const EdgeInsets.symmetric(horizontal: SelSpace.x3),
      decoration: BoxDecoration(
        color: Sel.card,
        borderRadius: BorderRadius.circular(SelRadius.input),
        border: Border.all(color: Sel.borderMuted),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          hint: hint,
          isExpanded: expanded,
          isDense: true,
          padding: const EdgeInsets.symmetric(vertical: 9),
          borderRadius: BorderRadius.circular(SelRadius.card),
          dropdownColor: Sel.card,
          style: SelType.body,
          icon: const Icon(LucideIcons.chevronDown, size: 14, color: Sel.ash),
        ),
      ),
    );

    if (label == null) return box;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label!, style: SelType.bodyMedium),
        const SizedBox(height: SelSpace.x2),
        box,
      ],
    );
  }
}

/// Pill-shaped filter group. Active pill is Soot filled, inactive are ghosts —
/// Seline's tab-pill pattern, reused for in-page filtering.
class SelPillGroup<T> extends StatelessWidget {
  const SelPillGroup({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<(T value, String label)> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: SelSpace.x2,
      runSpacing: SelSpace.x2,
      children: [
        for (final (value, label) in options)
          _Pill(
            label: label,
            active: value == selected,
            onTap: () => onChanged(value),
          ),
      ],
    );
  }
}

class _Pill extends StatefulWidget {
  const _Pill({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(
            horizontal: SelSpace.x3 + 2,
            vertical: SelSpace.x1 + 2,
          ),
          decoration: BoxDecoration(
            color: active
                ? Sel.soot
                : _hover
                    ? Sel.card
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(SelRadius.pill),
            border: Border.all(color: active ? Sel.soot : Sel.border),
          ),
          child: Text(
            widget.label,
            style: SelType.button.copyWith(color: active ? Sel.card : Sel.ink),
          ),
        ),
      ),
    );
  }
}
