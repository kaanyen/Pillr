import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

class _Slide {
  const _Slide({required this.title, required this.body});

  final String title;
  final String body;
}

/// Left rail for auth screens — solid dark panel (no gradients), headline, carousel dots.
class AuthMarketingPanel extends StatefulWidget {
  const AuthMarketingPanel({super.key});

  @override
  State<AuthMarketingPanel> createState() => _AuthMarketingPanelState();
}

class _AuthMarketingPanelState extends State<AuthMarketingPanel> {
  final _pageController = PageController();
  int _page = 0;

  static const _slides = <_Slide>[
    _Slide(
      title: 'Partnership giving, made transparent',
      body:
          'Track partnership arms, periods, and approvals in one place — built for churches that value clarity.',
    ),
    _Slide(
      title: 'Pastors approve with confidence',
      body: 'Staff entries flow into a simple review queue with full audit context.',
    ),
    _Slide(
      title: 'Reports that match your ministry',
      body: 'Export to PDF or CSV when you need numbers for leadership or partners.',
    ),
  ];

  static const _panelBg = Color(0xFF111827);

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _panelBg,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    LucideIcons.church,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  'Pillr',
                  style: AppTypography.heading2.copyWith(color: Colors.white),
                ),
              ],
            ),
            const Spacer(),
            SizedBox(
              height: 200,
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: _slides.length,
                itemBuilder: (context, i) {
                  final s = _slides[i];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        s.title,
                        style: AppTypography.heading1.copyWith(
                          color: Colors.white,
                          fontSize: 26,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        s.body,
                        style: AppTypography.body.copyWith(
                          color: Colors.white70,
                          height: 1.5,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _slides.length,
                (i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: _page == i ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _page == i
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(50),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}
