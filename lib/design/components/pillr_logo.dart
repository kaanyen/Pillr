import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../pillr_branding.dart';

/// Renders a bundled Pillr pillar mark at a consistent aspect ratio.
class PillrLogo extends StatelessWidget {
  const PillrLogo({
    super.key,
    this.variant = PillrLogoVariant.main,
    this.height = 22,
    this.semanticLabel = 'The Pillr',
  });

  final PillrLogoVariant variant;
  final double height;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final width = variant == PillrLogoVariant.app ? height : height * (56 / 72);
    final pngFallback = switch (variant) {
      PillrLogoVariant.main => PillrBranding.mainLogoPng,
      PillrLogoVariant.white => PillrBranding.mainLogoPng,
      PillrLogoVariant.ink => PillrBranding.mainLogoPng,
      PillrLogoVariant.muted => PillrBranding.mainLogoPng,
      PillrLogoVariant.app => PillrBranding.appLogoPng,
    };
    return Semantics(
      label: semanticLabel,
      child: SvgPicture.asset(
        variant.assetPath,
        height: height,
        width: width,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => Image.asset(
          pngFallback,
          height: height,
          width: width,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
