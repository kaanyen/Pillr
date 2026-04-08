import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color primaryColor = Color(0xFF1A56DB);
  static const Color primaryLight = Color(0xFFEBF0FF);
  static const Color primaryDark = Color(0xFF1240A8);

  static const Color successColor = Color(0xFF0E9F6E);
  static const Color successLight = Color(0xFFDEF7EC);
  static const Color warningColor = Color(0xFFE3A008);
  static const Color warningLight = Color(0xFFFDF3DC);
  static const Color dangerColor = Color(0xFFE02424);
  static const Color dangerLight = Color(0xFFFDE8E8);
  static const Color infoColor = Color(0xFF3F83F8);

  static const Color gray50 = Color(0xFFF9FAFB);
  static const Color gray100 = Color(0xFFF3F4F6);
  static const Color gray200 = Color(0xFFE5E7EB);
  static const Color gray400 = Color(0xFF9CA3AF);
  static const Color gray600 = Color(0xFF4B5563);
  static const Color gray900 = Color(0xFF111827);

  static const Color white = Color(0xFFFFFFFF);

  /// Page / scaffold background (neutral canvas; cards sit on [white]).
  static const Color surfaceColor = Color(0xFFF3F4F6);

  /// Reference 3-style progress segments (stats header)
  static const Color progressTeal = Color(0xFF0D9488);
  static const Color progressOrange = Color(0xFFF97316);
  static const Color progressRed = Color(0xFFEF4444);
}
