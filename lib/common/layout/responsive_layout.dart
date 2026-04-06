import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

enum AppBreakpoint { mobile, tablet, desktop }

AppBreakpoint breakpointFor(double width) {
  if (width >= AppConstants.breakpointDesktop) return AppBreakpoint.desktop;
  if (width >= AppConstants.breakpointTablet) return AppBreakpoint.tablet;
  return AppBreakpoint.mobile;
}

class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    required this.desktop,
  });

  final Widget mobile;
  final Widget? tablet;
  final Widget desktop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final bp = breakpointFor(c.maxWidth);
        return switch (bp) {
          AppBreakpoint.mobile => mobile,
          AppBreakpoint.tablet => tablet ?? desktop,
          AppBreakpoint.desktop => desktop,
        };
      },
    );
  }
}
