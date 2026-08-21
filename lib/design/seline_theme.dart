import 'package:flutter/material.dart';

import 'seline_colors.dart';
import 'seline_metrics.dart';
import 'seline_type.dart';

/// The Seline [ThemeData].
///
/// Defaults here matter more than usual, because the system's discipline is
/// mostly about *not* doing things: no second accent, no dark filled buttons,
/// no heavy shadows on ordinary surfaces. Anything a Material default would
/// hand you in the wrong colour is overridden.
abstract final class SelTheme {
  /// [seedColor] carries the tenant's `primaryColorHex`. It does **not** seed
  /// the scheme — Seline's palette is stone plus one cyan, and a per-church hue
  /// leaking into chrome would dismantle it. Tenant colour is confined to
  /// identity marks; read it with [tenantMark].
  static ThemeData light({Color? seedColor}) => _build();

  /// The tenant's identity colour, for the church avatar / logo lockup only.
  /// Falls back to the brand cyan.
  static Color tenantMark(Color? seedColor) => seedColor ?? Sel.cyan;

  static ThemeData _build() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: Sel.cyan,
      onPrimary: Sel.card,
      primaryContainer: Sel.skyWash,
      onPrimaryContainer: Sel.cyanEdge,
      secondary: Sel.warm,
      onSecondary: Sel.card,
      secondaryContainer: Sel.canvas,
      onSecondaryContainer: Sel.ink,
      tertiary: Sel.ash,
      onTertiary: Sel.card,
      // State is monochrome in this system; "error" resolves to ink so a
      // stray Material default cannot introduce red.
      error: Sel.ink,
      onError: Sel.card,
      errorContainer: Sel.canvas,
      onErrorContainer: Sel.ink,
      surface: Sel.card,
      onSurface: Sel.ink,
      surfaceContainerLowest: Sel.card,
      surfaceContainerLow: Sel.canvas,
      surfaceContainer: Sel.canvas,
      surfaceContainerHigh: Sel.border,
      surfaceContainerHighest: Sel.borderMuted,
      onSurfaceVariant: Sel.warm,
      outline: Sel.border,
      outlineVariant: Sel.borderMuted,
      inverseSurface: Sel.soot,
      onInverseSurface: Sel.card,
      shadow: Color(0x0D000000),
      scrim: Color(0x660C0A09),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      // Warm paper, never screen-white.
      scaffoldBackgroundColor: Sel.canvas,
      canvasColor: Sel.canvas,
      dividerColor: Sel.border,
      textTheme: SelType.textTheme(),
      fontFamily: SelType.text,
      splashFactory: NoSplash.splashFactory,
    );

    return base.copyWith(
      iconTheme: const IconThemeData(color: Sel.warm, size: 16),

      dividerTheme: const DividerThemeData(
        color: Sel.border,
        thickness: 1,
        space: 1,
      ),

      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: Sel.canvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Sel.ink,
        titleTextStyle: SelType.subtitleSm,
        iconTheme: IconThemeData(color: Sel.warm, size: 18),
      ),

      cardTheme: const CardThemeData(
        color: Sel.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(SelRadius.card)),
          side: BorderSide(color: Sel.border),
        ),
      ),

      dialogTheme: const DialogThemeData(
        backgroundColor: Sel.card,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: SelType.subtitle,
        contentTextStyle: SelType.body,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(SelRadius.feature)),
          side: BorderSide(color: Sel.border),
        ),
      ),

      // Inputs: white fill on the warm canvas, 6px radius, cyan focus ring.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Sel.card,
        floatingLabelBehavior: FloatingLabelBehavior.never,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: SelSpace.x3,
          vertical: 10,
        ),
        border: _inputBorder(Sel.borderMuted),
        enabledBorder: _inputBorder(Sel.borderMuted),
        focusedBorder: _inputBorder(Sel.cyan, width: 2),
        disabledBorder: _inputBorder(Sel.border),
        // Errors read through weight, not colour.
        errorBorder: _inputBorder(Sel.ink, width: 1.5),
        focusedErrorBorder: _inputBorder(Sel.ink, width: 2),
        hintStyle: SelType.body.copyWith(color: Sel.warm),
        labelStyle: SelType.bodyMuted,
        helperStyle: SelType.small,
        errorStyle: SelType.small.copyWith(
          color: Sel.ink,
          fontWeight: FontWeight.w500,
        ),
        prefixIconColor: Sel.ash,
        suffixIconColor: Sel.ash,
      ),

      // The one filled colour in the system.
      filledButtonTheme: FilledButtonThemeData(style: _cyanPill()),
      elevatedButtonTheme: ElevatedButtonThemeData(style: _cyanPill()),

      // Ghost pill — the quiet companion.
      outlinedButtonTheme: OutlinedButtonThemeData(style: _ghostPill()),

      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.hovered) ? Sel.ink : Sel.warm),
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: SelSpace.x3, vertical: SelSpace.x1),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
          textStyle: const WidgetStatePropertyAll(SelType.button),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(SelRadius.pill)),
            ),
          ),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.hovered) ? Sel.ink : Sel.warm),
          backgroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.hovered) ? Sel.canvas : Colors.transparent),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          iconSize: const WidgetStatePropertyAll(18),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(SelRadius.pill)),
            ),
          ),
        ),
      ),

      chipTheme: const ChipThemeData(
        backgroundColor: Sel.card,
        selectedColor: Sel.soot,
        disabledColor: Sel.canvas,
        checkmarkColor: Sel.card,
        labelStyle: SelType.tag,
        secondaryLabelStyle: SelType.tag,
        side: BorderSide(color: Sel.border),
        elevation: 0,
        pressElevation: 0,
        shadowColor: Colors.transparent,
        padding: EdgeInsets.symmetric(horizontal: SelSpace.x3, vertical: SelSpace.x1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(SelRadius.pill)),
        ),
      ),

      listTileTheme: const ListTileThemeData(
        iconColor: Sel.ash,
        textColor: Sel.ink,
        titleTextStyle: SelType.bodyMedium,
        subtitleTextStyle: SelType.small,
        selectedColor: Sel.ink,
        selectedTileColor: Sel.canvas,
        contentPadding: EdgeInsets.symmetric(horizontal: SelSpace.x3, vertical: SelSpace.x1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(SelRadius.input)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: Sel.soot,
        contentTextStyle: SelType.body.copyWith(color: Sel.card),
        actionTextColor: Sel.cyan,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(SelRadius.card)),
        ),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: const BoxDecoration(
          color: Sel.soot,
          borderRadius: BorderRadius.all(Radius.circular(SelRadius.input)),
        ),
        textStyle: SelType.small.copyWith(color: Sel.card),
        padding: const EdgeInsets.symmetric(horizontal: SelSpace.x2, vertical: SelSpace.x1),
      ),

      // Tabs read as pills elsewhere; the underline variant stays monochrome.
      tabBarTheme: const TabBarThemeData(
        labelColor: Sel.ink,
        unselectedLabelColor: Sel.warm,
        labelStyle: SelType.bodyMedium,
        unselectedLabelStyle: SelType.bodyMuted,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Sel.border,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: Sel.ink, width: 1.5),
        ),
        overlayColor: WidgetStatePropertyAll(Colors.transparent),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Sel.card,
        indicatorColor: Sel.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 60,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(SelRadius.pill)),
        ),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              size: 18,
              color: s.contains(WidgetState.selected) ? Sel.ink : Sel.ash,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => SelType.small.copyWith(
              color: s.contains(WidgetState.selected) ? Sel.ink : Sel.warm,
              fontWeight: s.contains(WidgetState.selected)
                  ? FontWeight.w500
                  : FontWeight.w400,
            )),
      ),

      drawerTheme: const DrawerThemeData(
        backgroundColor: Sel.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Sel.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(SelRadius.feature)),
        ),
      ),

      popupMenuTheme: const PopupMenuThemeData(
        color: Sel.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        textStyle: SelType.body,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(SelRadius.card)),
          side: BorderSide(color: Sel.border),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Sel.card),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Sel.cyan : Sel.borderMuted),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Sel.cyan : Sel.borderMuted),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Sel.cyan : Colors.transparent),
        checkColor: const WidgetStatePropertyAll(Sel.card),
        side: const BorderSide(color: Sel.borderMuted),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SelRadius.icon),
        ),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Sel.cyan : Sel.borderMuted),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Sel.ink,
        linearTrackColor: Sel.border,
        circularTrackColor: Sel.border,
        linearMinHeight: 4,
      ),

      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(SelRadius.pill),
        thickness: const WidgetStatePropertyAll(6),
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.hovered) ? Sel.ash : Sel.borderMuted),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color c, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(SelRadius.input),
        borderSide: BorderSide(color: c, width: width),
      );

  /// Cyan filled pill — the only chromatic filled element in the system.
  static ButtonStyle _cyanPill() => ButtonStyle(
        foregroundColor: const WidgetStatePropertyAll(Sel.card),
        backgroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return Sel.borderMuted;
          if (s.contains(WidgetState.hovered) || s.contains(WidgetState.pressed)) {
            return Sel.cyanEdge;
          }
          return Sel.cyan;
        }),
        side: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled)
            ? BorderSide.none
            : const BorderSide(color: Sel.cyanEdge)),
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: SelSpace.x4, vertical: SelSpace.x2),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
        textStyle: const WidgetStatePropertyAll(SelType.button),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(SelRadius.pill)),
          ),
        ),
      );

  /// Ghost pill — transparent, stone hairline, ink text.
  static ButtonStyle _ghostPill() => ButtonStyle(
        foregroundColor: const WidgetStatePropertyAll(Sel.ink),
        backgroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.hovered) ? Sel.card : Colors.transparent),
        side: WidgetStateProperty.resolveWith((s) => BorderSide(
              color: s.contains(WidgetState.hovered) ? Sel.borderMuted : Sel.border,
            )),
        elevation: const WidgetStatePropertyAll(0),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: SelSpace.x4, vertical: SelSpace.x2),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
        textStyle: const WidgetStatePropertyAll(SelType.button),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(SelRadius.pill)),
          ),
        ),
      );
}
