import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../design/seline.dart';

/// The unauthenticated shell.
///
/// A single centred column on the warm canvas, with the form in one white
/// card. No split panel, no marketing column, no feature carousel — the old
/// shell sold the product to someone who had already been invited to it. This
/// one just gets them in, and spends its one highlight on the headline.
class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.title,
    required this.child,
    this.highlight,
    this.titleSuffix,
    this.subtitle,
    this.footer,
    this.width = 420,
  });

  final String title;

  /// The single sky-wash phrase. One per screen.
  final String? highlight;

  final String? titleSuffix;
  final String? subtitle;
  final Widget child;
  final Widget? footer;
  final double width;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final compact = SelLayout.isCompact(w);

    return Scaffold(
      backgroundColor: Sel.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: SelSpace.x6,
              vertical: compact ? SelSpace.x8 : SelSpace.x16,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Wordmark, centred, small — it identifies, it does not sell.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        height: 22,
                        width: 22,
                        decoration: BoxDecoration(
                          color: Sel.card,
                          borderRadius: BorderRadius.circular(SelRadius.icon),
                          border: Border.all(color: Sel.border),
                        ),
                        child: const Icon(
                          LucideIcons.church,
                          size: 12,
                          color: Sel.cyan,
                        ),
                      ),
                      const SizedBox(width: SelSpace.x2),
                      Text('Pillr', style: SelType.bodyMedium),
                    ],
                  ),
                  SizedBox(height: compact ? SelSpace.x8 : SelSpace.x12),

                  if (highlight != null)
                    SelHighlight(
                      before: title,
                      highlight: highlight!,
                      after: titleSuffix ?? '',
                      style: compact
                          ? SelType.title.copyWith(fontSize: 26)
                          : SelType.title,
                      textAlign: TextAlign.center,
                    )
                  else
                    Text(
                      title,
                      style: compact
                          ? SelType.title.copyWith(fontSize: 26)
                          : SelType.title,
                      textAlign: TextAlign.center,
                    ),

                  if (subtitle != null) ...[
                    const SizedBox(height: SelSpace.x3),
                    Text(
                      subtitle!,
                      style: SelType.bodyMuted,
                      textAlign: TextAlign.center,
                    ),
                  ],

                  const SizedBox(height: SelSpace.x8),
                  SelCard(child: child),

                  if (footer != null) ...[
                    const SizedBox(height: SelSpace.x6),
                    DefaultTextStyle(
                      style: SelType.small,
                      textAlign: TextAlign.center,
                      child: footer!,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline error notice for auth forms. Ink text on a canvas strip — a failed
/// sign-in is information, not an alarm, and red would be the only red in the
/// product.
class AuthNotice extends StatelessWidget {
  const AuthNotice({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: SelSpace.x4),
      padding: const EdgeInsets.symmetric(
        horizontal: SelSpace.x3,
        vertical: SelSpace.x2 + 2,
      ),
      decoration: BoxDecoration(
        color: Sel.canvas,
        borderRadius: BorderRadius.circular(SelRadius.input),
        border: Border.all(color: Sel.borderMuted),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(LucideIcons.alertCircle, size: 14, color: Sel.ink),
          ),
          const SizedBox(width: SelSpace.x2),
          Expanded(
            child: Text(
              message,
              style: SelType.bodySm.copyWith(color: Sel.ink),
            ),
          ),
        ],
      ),
    );
  }
}
