import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import 'pillr_status_style.dart';

enum PillrBadgeKind { approved, pending, declined, active, inactive }

/// Monochrome status badge.
///
/// State reads through fill, border, weight and icon — never hue. Approved is
/// a solid Charcoal pill (settled), pending is a Mist wash with a Fog hairline
/// (in progress), declined is a bare Pewter outline (closed). The icon does
/// the work color used to, which also makes the scale legible to colorblind
/// users.
class PillrBadge extends StatelessWidget {
  const PillrBadge({
    super.key,
    required this.label,
    required this.kind,
    this.compact = false,
  });

  /// Builds directly from a raw Firestore status string.
  PillrBadge.fromStatus({
    super.key,
    required String status,
    required this.label,
    this.compact = false,
  }) : kind = _kindFor(status);

  final String label;
  final PillrBadgeKind kind;
  final bool compact;

  static PillrBadgeKind _kindFor(String status) {
    switch (status.trim().toLowerCase()) {
      case 'approved':
        return PillrBadgeKind.approved;
      case 'declined':
      case 'rejected':
      case 'expired':
        return PillrBadgeKind.declined;
      case 'active':
        return PillrBadgeKind.active;
      case 'inactive':
      case 'suspended':
        return PillrBadgeKind.inactive;
      default:
        return PillrBadgeKind.pending;
    }
  }

  PillrStatusStyle get _style => switch (kind) {
        PillrBadgeKind.approved => PillrStatusStyle.approved,
        PillrBadgeKind.pending => PillrStatusStyle.pending,
        PillrBadgeKind.declined => PillrStatusStyle.declined,
        PillrBadgeKind.active => PillrStatusStyle.active,
        PillrBadgeKind.inactive => PillrStatusStyle.inactive,
      };

  @override
  Widget build(BuildContext context) {
    final style = _style;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: style.border == null
            ? null
            : Border.all(color: style.border!, width: AppBorders.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: compact ? 12 : 14, color: style.foreground),
          SizedBox(width: compact ? 4 : 6),
          Text(
            label,
            style: AppTypography.pill.copyWith(
              color: style.foreground,
              fontWeight: style.fontWeight,
            ),
          ),
        ],
      ),
    );
  }
}

/// A neutral count/metadata pill — no state semantics, just a hairline chip.
class PillrCountBadge extends StatelessWidget {
  const PillrCountBadge({super.key, required this.label, this.emphasized = false});

  final String label;

  /// Inverts to Charcoal when the count demands attention (e.g. pending review).
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: emphasized ? AppColors.charcoal : AppColors.mist,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: emphasized
            ? null
            : Border.all(color: AppColors.fog, width: AppBorders.hairline),
      ),
      child: Text(
        label,
        style: AppTypography.pill.copyWith(
          color: emphasized ? AppColors.paper : AppColors.ink,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
