import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/pillr_layout.dart';
import 'pillr_gradient_text.dart';

/// Editorial screen header.
///
/// Two densities, because a 64px headline is right above a dashboard and wrong
/// above a 200-row table:
///
/// * [PillrPageHeader.editorial] — low-density surfaces (dashboards, auth,
///   onboarding, empty states). Display type at 40–64px, optional gradient
///   keyword, generous section padding.
/// * [PillrPageHeader.dense] — list and form screens. Capped at 24–40px with a
///   hairline rule beneath, so rows stay above the fold.
class PillrPageHeader extends StatelessWidget {
  const PillrPageHeader.editorial({
    super.key,
    required this.title,
    this.highlight,
    this.titleSuffix,
    this.subtitle,
    this.actions = const [],
    this.eyebrow,
    this.centered = false,
  }) : _dense = false;

  const PillrPageHeader.dense({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  })  : _dense = true,
        highlight = null,
        titleSuffix = null,
        eyebrow = null,
        centered = false;

  final String title;

  /// The one phrase that carries the Electric Blue gradient. Editorial only.
  final String? highlight;

  /// Text following [highlight]. Ignored when [highlight] is null.
  final String? titleSuffix;

  final String? subtitle;
  final List<Widget> actions;

  /// The eyebrow pill above the headline (editorial only).
  final Widget? eyebrow;

  final bool centered;
  final bool _dense;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return _dense ? _buildDense(context, width) : _buildEditorial(context, width);
  }

  Widget _buildEditorial(BuildContext context, double width) {
    final titleStyle = AppTypography.displayFor(width);
    final align = centered ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = centered ? TextAlign.center : TextAlign.start;

    return Padding(
      padding: EdgeInsets.only(
        top: PillrLayout.isCompact(width) ? AppSpacing.xl : AppSpacing.xxxl,
        bottom: PillrLayout.isCompact(width) ? AppSpacing.lg : AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (eyebrow != null) ...[
            eyebrow!,
            const SizedBox(height: AppSpacing.lg),
          ],
          if (highlight != null)
            PillrGradientHeadline(
              before: title,
              highlight: highlight!,
              after: titleSuffix ?? '',
              style: titleStyle,
              textAlign: textAlign,
            )
          else
            Text(title, style: titleStyle, textAlign: textAlign),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.md),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: PillrLayout.proseMaxWidth),
              child: Text(
                subtitle!,
                style: AppTypography.subheading,
                textAlign: textAlign,
              ),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              alignment: centered ? WrapAlignment.center : WrapAlignment.start,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDense(BuildContext context, double width) {
    final compact = PillrLayout.isCompact(width);
    final titleStyle = compact ? AppTypography.heading : AppTypography.headingLgFor(width);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: titleStyle),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(subtitle!, style: AppTypography.caption),
                    ],
                  ],
                ),
              ),
              if (actions.isNotEmpty && !compact) ...[
                const SizedBox(width: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions,
                ),
              ],
            ],
          ),
          if (actions.isNotEmpty && compact) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: actions),
          ],
          const SizedBox(height: AppSpacing.md),
          const Divider(height: AppBorders.hairline, color: AppColors.fog),
        ],
      ),
    );
  }
}

/// Section label + optional trailing action, separated by a hairline.
/// The workhorse divider between blocks inside a screen.
class PillrSectionHeader extends StatelessWidget {
  const PillrSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.headingSm),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(subtitle!, style: AppTypography.caption),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
