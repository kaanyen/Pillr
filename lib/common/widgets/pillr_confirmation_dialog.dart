import 'package:flutter/material.dart';

import '../../core/theme/app_typography.dart';
import 'pillr_button.dart';

Future<bool?> showPillrConfirmationDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  PillrButtonVariant confirmVariant = PillrButtonVariant.danger,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: AppTypography.heading3),
      content: Text(message, style: AppTypography.body),
      actions: [
        PillrButton(
          label: cancelLabel,
          variant: PillrButtonVariant.ghost,
          onPressed: () => Navigator.of(ctx).pop(false),
        ),
        PillrButton(
          label: confirmLabel,
          variant: confirmVariant,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ],
    ),
  );
}
