import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:the_pillr/l10n/app_localizations.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// Dashed drop zone + cloud icon + Browse (reference: upload panel).
class BulkImportDropZone extends StatelessWidget {
  const BulkImportDropZone({
    super.key,
    required this.onPick,
    required this.loading,
  });

  final VoidCallback onPick;
  final bool loading;

  static const _cornerRadius = 16.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CustomPaint(
      foregroundPainter: const _DashedRRectPainter(
        color: Color(0xFFD1D5DB),
        strokeWidth: 1.5,
        radius: _cornerRadius,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_cornerRadius),
        child: Material(
          color: AppColors.gray50,
          child: InkWell(
            onTap: loading ? null : onPick,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.uploadCloud,
                    size: 48,
                    color: AppColors.gray400,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    l10n.bulkImportDropPrimary,
                    textAlign: TextAlign.center,
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.gray900,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.bulkImportDropFormats,
                    textAlign: TextAlign.center,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  OutlinedButton(
                    onPressed: loading ? null : onPick,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.gray900,
                      side: const BorderSide(color: AppColors.gray200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.md,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                    child: loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            l10n.bulkImportBrowseFiles,
                            style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
  });

  final Color color;
  final double strokeWidth;
  final double radius;

  static const double _dash = 6;
  static const double _gap = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(inset, inset, size.width - strokeWidth, size.height - strokeWidth),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(r);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final seg = math.min(_dash, metric.length - d);
        if (seg > 0) {
          canvas.drawPath(metric.extractPath(d, d + seg), paint);
        }
        d += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) {
    return color != oldDelegate.color ||
        strokeWidth != oldDelegate.strokeWidth ||
        radius != oldDelegate.radius;
  }
}
