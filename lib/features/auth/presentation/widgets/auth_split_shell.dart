import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import 'auth_marketing_panel.dart';

/// Split marketing + form layout for login / join. On narrow viewports, [formFirst] shows the form on top.
class AuthSplitShell extends StatelessWidget {
  const AuthSplitShell({
    super.key,
    required this.form,
    this.formFirstOnNarrow = true,
    this.maxOuterWidth = 1080,
    this.breakpoint = 880,
  });

  final Widget form;
  final bool formFirstOnNarrow;
  final double maxOuterWidth;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    final bg = const Color(0xFFF4F1EB);
    return ColoredBox(
      color: bg,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= breakpoint;
            final pad = c.maxWidth >= 600 ? AppSpacing.xl : AppSpacing.md;
            final shell = Container(
              constraints: BoxConstraints(maxWidth: maxOuterWidth),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppColors.gray200),
              ),
              clipBehavior: Clip.antiAlias,
              child: wide
                  ? IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Expanded(
                            flex: 46,
                            child: AuthMarketingPanel(),
                          ),
                          Expanded(
                            flex: 54,
                            child: form,
                          ),
                        ],
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: formFirstOnNarrow
                          ? [
                              form,
                              const SizedBox(
                                height: 280,
                                child: AuthMarketingPanel(),
                              ),
                            ]
                          : [
                              const SizedBox(
                                height: 240,
                                child: AuthMarketingPanel(),
                              ),
                              form,
                            ],
                    ),
            );
            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(pad),
                child: shell,
              ),
            );
          },
        ),
      ),
    );
  }
}
