import 'package:flutter/material.dart';
import 'package:the_pillr/l10n/app_localizations.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Material(
      color: AppColors.warningLight,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.wifi_off_rounded, color: AppColors.warningColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.offlineBannerMessage,
                  style: AppTypography.caption.copyWith(color: AppColors.gray900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
