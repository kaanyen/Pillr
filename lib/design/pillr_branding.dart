/// Bundled Pillr brand marks (SVG + PNG).
abstract final class PillrBranding {
  /// Seline cyan — matches [Sel.cyan] in the design system.
  static const selineBlueHex = '#3BA6F1';
  static const appLogoSvg = 'assets/branding/pillr_app_logo.svg';
  static const appLogoPng = 'assets/branding/pillr_app_logo.png';

  static const mainLogoSvg = 'assets/branding/pillr_logo_main.svg';
  static const mainLogoWhiteSvg = 'assets/branding/pillr_logo_main_white.svg';
  static const mainLogoInkSvg = 'assets/branding/pillr_logo_main_ink.svg';
  static const mainLogoMutedSvg = 'assets/branding/pillr_logo_main_muted.svg';
  static const mainLogoPng = 'assets/branding/pillr_logo_main.png';
}

/// Which main mark to render on the current surface.
enum PillrLogoVariant {
  /// Brand cyan pillar — default on light backgrounds.
  main,

  /// White pillar — dark headers, photos, tenant accent fills.
  white,

  /// Ink pillar — neutral documents and high-contrast print.
  ink,

  /// Warm gray pillar — secondary/meta surfaces.
  muted,

  /// Square app icon — launcher / home-screen install only.
  app,
}

extension PillrLogoVariantAsset on PillrLogoVariant {
  String get assetPath => switch (this) {
        PillrLogoVariant.main => PillrBranding.mainLogoSvg,
        PillrLogoVariant.white => PillrBranding.mainLogoWhiteSvg,
        PillrLogoVariant.ink => PillrBranding.mainLogoInkSvg,
        PillrLogoVariant.muted => PillrBranding.mainLogoMutedSvg,
        PillrLogoVariant.app => PillrBranding.appLogoSvg,
      };
}
