import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/pillr_layout.dart';
import '../../../../common/widgets/pillr_gradient_text.dart';

/// Auth split: an editorial marketing column beside the form.
///
/// This is the one screen in the product that is genuinely a marketing
/// surface, so it gets the full reference treatment — display headline with a
/// single gradient keyword, Smoke subtext on a narrow measure, and a Paper
/// canvas separated from the form by a hairline rather than a grey panel.
class AuthSplitShell extends StatelessWidget {
  const AuthSplitShell({
    super.key,
    required this.formChild,
    this.marketingHeadline = kDefaultMarketingHeadline,
    this.marketingHighlight = kDefaultMarketingHighlight,
    this.marketingSubtitle = kDefaultMarketingSubtitle,
    this.breakpoint = kBreakpoint,
  });

  final Widget formChild;
  final String marketingHeadline;

  /// Keyword filled with the Electric Blue gradient. One or two words.
  final String marketingHighlight;

  final String marketingSubtitle;
  final double breakpoint;

  /// Default wide-layout threshold (must match [kBreakpoint] unless overridden).
  static const double kBreakpoint = 900;

  static const String kDefaultMarketingHeadline = 'Run partnership giving ';

  /// The single gradient-highlighted word on this screen.
  static const String kDefaultMarketingHighlight = 'transparently';
  static const String kDefaultMarketingSubtitle =
      'Our registration is quick and easy — verify your invite and you are ready to collaborate with your church team.';

  static const Color _panelBackground = AppColors.paper;

  /// Max total width of the split content area — keeps both panels visually close
  /// on very wide viewports instead of stretching across the full screen.
  static const double kMaxContentWidth = 1100.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _panelBackground,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= breakpoint;
            final left = _MarketingPanel(
              headline: marketingHeadline,
              highlight: marketingHighlight,
              subtitle: marketingSubtitle,
            );
            final right = _FloatingFormPanel(
              desktopSplit: wide,
              child: formChild,
            );
            if (wide) {
              // Constrain total width so the panels stay close together in the center.
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 6, child: left),
                      Expanded(flex: 4, child: right),
                    ],
                  ),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 10, child: left),
                Expanded(flex: 12, child: right),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BrandRow extends StatelessWidget {
  const _BrandRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.charcoal,
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          child: const Icon(LucideIcons.church, color: AppColors.paper, size: 18),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          'Pillr',
          style: AppTypography.headingSm.copyWith(
            fontFamily: AppTypography.textFamily,
          ),
        ),
      ],
    );
  }
}

class _MarketingPanel extends StatelessWidget {
  const _MarketingPanel({
    required this.headline,
    required this.highlight,
    required this.subtitle,
  });

  final String headline;
  final String highlight;
  final String subtitle;

  Future<void> _open(String url) async {
    final u = Uri.parse(url);
    if (await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AuthSplitShell._panelBackground,
      child: LayoutBuilder(
        builder: (context, c) {
          final inset = const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
          );
          return SingleChildScrollView(
            padding: inset,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight - inset.vertical),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: (c.maxWidth - inset.horizontal).clamp(0.0, 520.0),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _BrandRow(),
                      const SizedBox(height: AppSpacing.xxl),
                      PillrGradientHeadline(
                        before: headline,
                        highlight: highlight,
                        style: AppTypography.headingXlFor(
                          MediaQuery.sizeOf(context).width,
                        ),
                        textAlign: TextAlign.start,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: PillrLayout.proseMaxWidth,
                        ),
                        child: Text(subtitle, style: AppTypography.subheading),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      const _FeatureCarousel(),
                      const SizedBox(height: AppSpacing.xl),
                      Row(
                        children: [
                          Text(
                            '© ${DateTime.now().year} Pillr',
                            style: AppTypography.caption.copyWith(color: AppColors.pewter),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => _open('https://pillr.dev'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Privacy',
                              style: AppTypography.caption.copyWith(color: AppColors.smoke),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _open('mailto:support@pillr.dev'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Support',
                              style: AppTypography.caption.copyWith(color: AppColors.smoke),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FeatureData {
  const _FeatureData({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

const _kFeatures = <_FeatureData>[
  _FeatureData(
    icon: LucideIcons.clipboardCheck,
    title: 'Pastor approvals, one queue',
    body:
        'Staff entries land in a single review queue with full context — approve or send back without digging through spreadsheets.',
  ),
  _FeatureData(
    icon: LucideIcons.layers,
    title: 'Arms, periods, and partners',
    body:
        'Model partnership the way your church actually runs it: arms, active periods, and partner profiles in one workspace.',
  ),
  _FeatureData(
    icon: LucideIcons.fileDown,
    title: 'Exports that match ministry',
    body:
        'Generate PDF or CSV when leadership or partners need numbers — tied to the same records your team already maintains.',
  ),
];

class _FeatureCarousel extends StatefulWidget {
  const _FeatureCarousel();

  @override
  State<_FeatureCarousel> createState() => _FeatureCarouselState();
}

class _FeatureCarouselState extends State<_FeatureCarousel> {
  static const _autoAdvance = Duration(seconds: 5);
  static const _animDuration = Duration(milliseconds: 480);

  final _controller = PageController();
  int _page = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleAutoAdvance();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleAutoAdvance() {
    _timer?.cancel();
    _timer = Timer.periodic(_autoAdvance, (_) => _goNext());
  }

  void _goNext() {
    if (!mounted || !_controller.hasClients) return;
    final next = (_page + 1) % _kFeatures.length;
    _controller.animateToPage(
      next,
      duration: _animDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void _onUserPageChanged(int i) {
    setState(() => _page = i);
    _scheduleAutoAdvance();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 210,
          child: PageView.builder(
            controller: _controller,
            onPageChanged: _onUserPageChanged,
            itemCount: _kFeatures.length,
            itemBuilder: (context, i) {
              final f = _kFeatures[i];
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.charcoal,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(f.icon, color: AppColors.paper, size: 20),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        f.title,
                        style: AppTypography.body.copyWith(
                          color: AppColors.paper,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          f.body,
                          style: AppTypography.body.copyWith(
                            color: AppColors.pewter,
                            height: 1.45,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _kFeatures.length,
            (i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _page == i ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _page == i ? AppColors.charcoal : AppColors.fog,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Grey canvas + white rounded card. On wide split, card is **left-aligned** (inner edge toward center).
class _FloatingFormPanel extends StatelessWidget {
  const _FloatingFormPanel({
    required this.desktopSplit,
    required this.child,
  });

  /// Must match [AuthSplitShell]’s wide-layout decision (same [LayoutBuilder] width).
  final bool desktopSplit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AuthSplitShell._panelBackground,
      child: LayoutBuilder(
        builder: (context, c) {
          final padV = c.maxWidth >= 600 ? 28.0 : AppSpacing.md;
          // Wide: tighter padding on the inner (split) side, more air on the outer edge.
          final inset = desktopSplit
              ? EdgeInsets.fromLTRB(AppSpacing.sm, padV, AppSpacing.xl, padV)
              : EdgeInsets.all(padV);
          final card = ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.paper,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.fog, width: AppBorders.hairline),
              ),
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: child,
            ),
          );
          return SingleChildScrollView(
            padding: inset,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight - inset.vertical),
              child: desktopSplit
                  ? Align(alignment: Alignment.centerLeft, child: card)
                  : Center(child: card),
            ),
          );
        },
      ),
    );
  }
}
