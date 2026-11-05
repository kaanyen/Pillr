import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../design/seline.dart';

/// The screens before you're inside a church: a navy panel that carries the
/// brand (or the invitation you're accepting), and the form on the white page.
/// From the canvas boards 16 Sign in, 17 Join a church and 18 Setup.
///
/// On a phone the panel folds to a short navy header above the form.
class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.title,
    required this.child,
    this.highlight,
    this.titleSuffix,
    this.subtitle,
    this.footer,
    this.width = 440,
    this.panel,
    this.topLink,
  });

  final String title;

  /// Kept for screens that pass one; shown as part of the title.
  final String? highlight;
  final String? titleSuffix;
  final String? subtitle;
  final Widget child;
  final Widget? footer;
  final double width;

  /// What the navy panel shows. Defaults to the brand panel.
  final Widget? panel;

  /// A small link at the top of the form side ("New to Pillr? Join…").
  final Widget? topLink;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final wide = w >= 900;
    final heading = [title, highlight ?? '', titleSuffix ?? ''].join();

    final form = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            heading,
            style: SelType.title.copyWith(fontSize: wide ? 32 : 26),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: SelSpace.x2),
            Text(subtitle!, style: SelType.lead),
          ],
          const SizedBox(height: SelSpace.x6),
          child,
          if (footer != null) ...[
            const SizedBox(height: SelSpace.x6),
            DefaultTextStyle(style: SelType.bodySm, child: footer!),
          ],
        ],
      ),
    );

    final formSide = SafeArea(
      child: Column(
        children: [
          if (topLink != null && wide)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SelSpace.x12,
                SelSpace.x10,
                SelSpace.x12,
                0,
              ),
              child: Align(alignment: Alignment.centerRight, child: topLink),
            ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: wide ? SelSpace.x12 : SelSpace.x4,
                  vertical: SelSpace.x8,
                ),
                child: form,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: SelSpace.x6),
            child: Wrap(
              spacing: SelSpace.x4,
              children: [
                for (final l in const ['Help', 'Privacy', 'Terms'])
                  Text(
                    l,
                    style: SelType.bodySm.copyWith(
                      decoration: TextDecoration.underline,
                      decorationColor: Sel.warm,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    final brand = panel ?? const AuthBrandPanel();

    return Scaffold(
      backgroundColor: Sel.canvas,
      body: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: (w * 0.38).clamp(440, 620),
                  child: _NavyPanel(child: brand),
                ),
                Expanded(child: formSide),
              ],
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _NavyPanel(compact: true, child: brand),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      SelSpace.x4,
                      SelSpace.x6,
                      SelSpace.x4,
                      SelSpace.x8,
                    ),
                    child: form,
                  ),
                ],
              ),
            ),
    );
  }
}

/// Tells the panel's contents whether they have the full height to fill.
class AuthPanelScope extends InheritedWidget {
  const AuthPanelScope({super.key, required this.compact, required super.child});

  final bool compact;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AuthPanelScope>()?.compact ??
      false;

  @override
  bool updateShouldNotify(AuthPanelScope old) => old.compact != compact;
}

class _NavyPanel extends StatelessWidget {
  const _NavyPanel({required this.child, this.compact = false});

  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Sel.ink,
      padding: compact
          ? const EdgeInsets.fromLTRB(SelSpace.x4, SelSpace.x6, SelSpace.x4, SelSpace.x6)
          : const EdgeInsets.fromLTRB(48, 40, 48, 36),
      child: SafeArea(
        bottom: false,
        child: AuthPanelScope(compact: compact, child: child),
      ),
    );
  }
}

/// The logo on navy: the mark's tile softened, "pillr" in white.
class AuthPanelLogo extends StatelessWidget {
  const AuthPanelLogo({super.key});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const PillrMark(size: 36, onNavy: true),
      const SizedBox(width: SelSpace.x3),
      Text(
        'pillr',
        style: SelType.hero.copyWith(
          fontSize: 26,
          height: 1,
          letterSpacing: -1.2,
          color: Sel.card,
        ),
      ),
    ],
  );
}

/// Headline and line under it, white on navy.
class AuthPanelHeadline extends StatelessWidget {
  const AuthPanelHeadline({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final compact = AuthPanelScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            title,
            style: SelType.hero.copyWith(
              fontSize: compact ? 26 : 36,
              height: 1.12,
              letterSpacing: compact ? -0.9 : -1.26,
              color: Sel.card,
            ),
          ),
        ),
        const SizedBox(height: SelSpace.x3),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Text(
            body,
            style: SelType.lead.copyWith(color: const Color(0xFFC9DEF3)),
          ),
        ),
      ],
    );
  }
}

/// The brand panel for Sign in: headline, the church front drawn from the
/// mark's bars, and two promises about privacy.
class AuthBrandPanel extends StatelessWidget {
  const AuthBrandPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final compact = AuthPanelScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AuthPanelLogo(),
        SizedBox(height: compact ? SelSpace.x4 : SelSpace.x10),
        const AuthPanelHeadline(
          title: 'All your giving counted, every partner known.',
          body:
              "Pillr keeps your church's giving in one place: what came in, "
              'from whom, and for which arm.',
        ),
        if (!compact) ...[
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: SelSpace.x6),
                child: AspectRatio(
                  aspectRatio: 440 / 340,
                  child: CustomPaint(painter: ChurchFrontPainter()),
                ),
              ),
            ),
          ),
          const AuthPanelFoot(),
        ],
      ],
    );
  }
}

/// Two small promises at the foot of the navy panel.
class AuthPanelFoot extends StatelessWidget {
  const AuthPanelFoot({super.key, this.items});

  final List<(IconData, String)>? items;

  @override
  Widget build(BuildContext context) {
    final list = items ??
        const [
          (LucideIcons.shieldCheck, 'Only your church sees its giving'),
          (LucideIcons.lock, 'Signed in on this device only'),
        ];
    return Wrap(
      spacing: SelSpace.x4,
      runSpacing: SelSpace.x2,
      children: [
        for (final (icon, label) in list)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: const Color(0xFFA9C7E6)),
              const SizedBox(width: SelSpace.x2),
              Text(
                label,
                style: SelType.bodySm.copyWith(color: const Color(0xFFA9C7E6)),
              ),
            ],
          ),
      ],
    );
  }
}

/// A church front built from the mark's bars: a sky roof in three steps over a
/// light-sky lintel, five white pillars and three steps. Drawn, so it stays
/// crisp and in the brand's own shapes. 440 × 340 design units.
class ChurchFrontPainter extends CustomPainter {
  const ChurchFrontPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 440;
    void bar(double x, double y, double w, double h, Color c) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x * k, y * k, w * k, h * k),
          Radius.circular(h * k / 2),
        ),
        Paint()..color = c,
      );
    }

    const sky = Sel.sky;
    bar(160, 14, 120, 16, sky.withValues(alpha: 0.45));
    bar(122, 40, 196, 20, sky.withValues(alpha: 0.7));
    bar(96, 70, 248, 22, sky);
    bar(112, 102, 216, 12, Sel.skyWash);
    for (final x in [128.0, 168, 208, 248, 288]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x * k, 124 * k, 24 * k, 136 * k),
          Radius.circular(12 * k),
        ),
        Paint()..color = Sel.card,
      );
    }
    bar(104, 270, 232, 14, Sel.card);
    bar(88, 292, 264, 14, Sel.card.withValues(alpha: 0.8));
    bar(72, 314, 296, 14, Sel.card.withValues(alpha: 0.6));
  }

  @override
  bool shouldRepaint(ChurchFrontPainter old) => false;
}

/// A large tappable choice row: icon tile, title, one line, arrow.
class AuthChoice extends StatelessWidget {
  const AuthChoice({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SelCard(
      onTap: onTap,
      radius: 20,
      padding: const EdgeInsets.symmetric(
        horizontal: SelSpace.x4,
        vertical: 14,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Sel.skyTint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 22, color: Sel.ink),
          ),
          const SizedBox(width: SelSpace.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: SelType.bodyMedium),
                Text(body, style: SelType.bodySm),
              ],
            ),
          ),
          const Icon(LucideIcons.arrowRight, size: 20, color: Sel.cyanEdge),
        ],
      ),
    );
  }
}

/// "New here?" between two hairlines.
class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(child: Divider(color: Sel.border)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: SelSpace.x4),
        child: Text(label, style: SelType.bodySm),
      ),
      const Expanded(child: Divider(color: Sel.border)),
    ],
  );
}

/// Inline error notice for auth forms.
class AuthNotice extends StatelessWidget {
  const AuthNotice({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: SelSpace.x4),
      padding: const EdgeInsets.symmetric(
        horizontal: SelSpace.x4,
        vertical: SelSpace.x3,
      ),
      decoration: BoxDecoration(
        color: Sel.skyTint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(LucideIcons.alertCircle, size: 16, color: Sel.ink),
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
