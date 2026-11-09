import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../seline_colors.dart';
import '../seline_metrics.dart';
import '../seline_type.dart';
import 'sel_button.dart';

/// Right-side panel on desktop, bottom sheet on mobile — for forms and pickers
/// that should keep the page behind them visible.
Future<T?> showSelSideSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
  String? subtitle,
  List<Widget> actions = const [],
  double width = 520,
  bool scrollable = true,
  bool barrierDismissible = true,
}) {
  final compact = MediaQuery.sizeOf(context).width < 900;
  if (compact) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Sel.card,
      barrierColor: Sel.soot.withValues(alpha: 0.28),
      isDismissible: barrierDismissible,
      enableDrag: barrierDismissible,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(SelRadius.feature)),
      ),
      builder: (ctx) => _SelSideSheetBody(
        title: title,
        subtitle: subtitle,
        actions: actions,
        scrollable: scrollable,
        child: child,
      ),
    );
  }

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: title,
    barrierColor: Sel.soot.withValues(alpha: 0.22),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, _) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: width,
          height: MediaQuery.sizeOf(ctx).height,
          child: _SelSideSheetBody(
            title: title,
            subtitle: subtitle,
            actions: actions,
            scrollable: scrollable,
            child: child,
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      final offset = Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ));
      return SlideTransition(position: offset, child: child);
    },
  );
}

class _SelSideSheetBody extends StatelessWidget {
  const _SelSideSheetBody({
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.scrollable = true,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 900;
    final body = scrollable
        ? SingleChildScrollView(
            padding: const EdgeInsets.all(SelSpace.cardPad),
            child: child,
          )
        : Padding(
            padding: const EdgeInsets.all(SelSpace.cardPad),
            child: child,
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Sel.card,
        border: Border(
          left: compact ? BorderSide.none : const BorderSide(color: Sel.border),
          top: compact ? const BorderSide(color: Sel.border) : BorderSide.none,
        ),
        boxShadow: compact ? null : SelShadow.card,
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SelSpace.cardPad,
                SelSpace.cardPad,
                SelSpace.x4,
                SelSpace.x4,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: SelType.subtitle),
                        if (subtitle != null) ...[
                          const SizedBox(height: SelSpace.x1),
                          Text(subtitle!, style: SelType.bodySm),
                        ],
                      ],
                    ),
                  ),
                  SelButton(
                    label: 'Close',
                    icon: LucideIcons.x,
                    kind: SelButtonKind.quiet,
                    dense: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Sel.border),
            Expanded(child: body),
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
        ),
      ),
    );
  }
}
