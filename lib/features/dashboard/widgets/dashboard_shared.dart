import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/text_case_utils.dart';
import '../../activity/domain/activity_log_row.dart' show ActivityLogRow;

/// Soft tints for summary stat tiles (shared across role dashboards).
abstract final class DashboardTints {
  static const totalBg = Color(0xFFEFF6FF);
  static const totalIconCircle = Color(0xFFDBEAFE);
  static const pendingBg = Color(0xFFFFFBEB);
  static const pendingIconCircle = Color(0xFFFDE68A);
  static const partnersBg = Color(0xFFECFDF5);
  static const partnersIconCircle = Color(0xFFD1FAE5);
  static const goalBg = Color(0xFFF5F3FF);
  static const goalIconCircle = Color(0xFFEDE9FE);
}

/// Hero title + subtitle under the app bar (all roles).
class DashboardWelcomeBlock extends StatelessWidget {
  const DashboardWelcomeBlock({
    super.key,
    required this.firstName,
    required this.subtitle,
  });

  final String firstName;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome back, $firstName!',
          style: AppTypography.heading1.copyWith(fontSize: 26),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          subtitle,
          style: AppTypography.bodyLarge.copyWith(color: AppColors.textSecondary, height: 1.45),
        ),
      ],
    );
  }
}

/// Section title with trailing text action.
class DashboardSectionHeader extends StatelessWidget {
  const DashboardSectionHeader({
    super.key,
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: AppTypography.heading3)),
        TextButton(
          onPressed: onAction,
          child: Text(
            actionLabel,
            style: AppTypography.label.copyWith(
              color: AppColors.primaryColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

String dashboardFormatActivityActor(String raw) {
  if (raw.contains('@') || raw.length > 48) return raw;
  return TextCaseUtils.toTitleCase(raw);
}

/// Single row in the recent-activity card.
class DashboardActivityLine extends StatelessWidget {
  const DashboardActivityLine({
    super.key,
    required this.row,
    required this.showDivider,
  });

  final ActivityLogRow row;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final t = row.createdAt;
    final when =
        '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} · ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 108,
                child: Text(
                  when,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.gray600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  '${dashboardFormatActivityActor(row.actorName)} · ${row.action} · ${row.entityType}',
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(height: 1, thickness: 1, color: AppColors.gray200),
      ],
    );
  }
}
