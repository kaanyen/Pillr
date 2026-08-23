import 'package:flutter/material.dart';

import '../seline_colors.dart';
import '../seline_metrics.dart';
import '../seline_type.dart';
import 'sel_button.dart';

/// Modal shell — white card on a warm scrim, 16px radius, hairline border.
///
/// Actions sit bottom-right: one cyan pill, everything else ghost.
class SelDialog extends StatelessWidget {
  const SelDialog({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.width = 520,
    this.scrollable = true,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final double width;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SelSpace.cardPad,
            SelSpace.cardPad,
            SelSpace.cardPad,
            SelSpace.x4,
          ),
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
        const Divider(height: 1, color: Sel.border),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.all(SelSpace.cardPad),
            child: scrollable ? SingleChildScrollView(child: child) : child,
          ),
        ),
        if (actions.isNotEmpty) ...[
          const Divider(height: 1, color: Sel.border),
          Padding(
            padding: const EdgeInsets.all(SelSpace.x4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: SelSpace.x2),
                  actions[i],
                ],
              ],
            ),
          ),
        ],
      ],
    );

    return Dialog(
      backgroundColor: Sel.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(SelSpace.x6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SelRadius.feature),
        side: const BorderSide(color: Sel.border),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: 640),
        child: content,
      ),
    );
  }
}

/// Confirmation prompt. Destructive actions are **not** red — the cyan stays
/// on the safe action and the destructive one is a ghost, so the calm choice
/// is also the visually obvious one.
Future<bool> selConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => SelDialog(
      title: title,
      width: 440,
      scrollable: false,
      actions: [
        SelButton(
          label: cancelLabel,
          kind: SelButtonKind.quiet,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        if (destructive)
          SelButton(
            label: confirmLabel,
            kind: SelButtonKind.ghost,
            onPressed: () => Navigator.of(context).pop(true),
          )
        else
          SelButton.cyan(
            label: confirmLabel,
            onPressed: () => Navigator.of(context).pop(true),
          ),
      ],
      child: Text(message, style: SelType.body),
    ),
  );
  return ok ?? false;
}
