import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:the_pillr/l10n/app_localizations.dart';

import '../../../design/seline.dart';


/// The drop zone, as on the canvas: a light-sky field with a dashed edge,
/// Choose a file and Paste rows, and a line pointing to the template.
class BulkImportDropZone extends StatelessWidget {
  const BulkImportDropZone({
    super.key,
    required this.onPick,
    required this.loading,
    this.onPaste,
    this.onTemplate,
    this.fileName,
  });

  final VoidCallback onPick;
  final VoidCallback? onPaste;
  final VoidCallback? onTemplate;
  final bool loading;
  final String? fileName;

  static const _cornerRadius = 18.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasFile = fileName != null && fileName!.isNotEmpty;
    return CustomPaint(
      foregroundPainter: const _DashedRRectPainter(
        color: Color(0xFF9ACFF6),
        strokeWidth: 1.5,
        radius: _cornerRadius,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_cornerRadius),
        child: Material(
          color: Sel.skyTint,
          child: InkWell(
            onTap: loading ? null : onPick,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 44, horizontal: SelSpace.x6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    hasFile ? LucideIcons.fileSpreadsheet : LucideIcons.fileText,
                    size: 44,
                    color: Sel.cyan,
                  ),
                  const SizedBox(height: SelSpace.x4),
                  Text(
                    hasFile ? fileName! : 'Drop your spreadsheet here',
                    textAlign: TextAlign.center,
                    style: SelType.subtitle,
                  ),
                  const SizedBox(height: SelSpace.x1),
                  Text(
                    hasFile
                        ? l10n.bulkImportDropResumeHint
                        : 'Excel (.xlsx) or CSV, up to 5,000 rows. One sheet at a time.',
                    textAlign: TextAlign.center,
                    style: SelType.body.copyWith(color: Sel.warm),
                  ),
                  const SizedBox(height: SelSpace.x6),
                  Wrap(
                    spacing: SelSpace.x3,
                    runSpacing: SelSpace.x2,
                    alignment: WrapAlignment.center,
                    children: [
                      SelButton.cyan(
                        label: 'Choose a file',
                        loading: loading,
                        onPressed: loading ? null : onPick,
                      ),
                      if (onPaste != null)
                        SelButton(
                          label: 'Paste rows',
                          onPressed: loading ? null : onPaste,
                        ),
                    ],
                  ),
                  if (onTemplate != null) ...[
                    const SizedBox(height: SelSpace.x6),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('No spreadsheet handy? ', style: SelType.bodySm),
                        SelLink(label: 'Download the template', onTap: onTemplate),
                        Text(', it has the columns already named.', style: SelType.bodySm),
                      ],
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
