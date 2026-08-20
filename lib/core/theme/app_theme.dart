import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';
import 'pillr_date_picker_theme.dart';

/// Hellotime theme — flat, editorial, shadowless.
///
/// Separation comes from 1px [AppColors.fog] hairlines and [AppColors.mist]
/// surface contrast against [AppColors.paper]. The only "elevation" cue in the
/// system is the [AppColors.charcoal] filled button, which inverts the page's
/// lightness rather than floating above it.
abstract final class AppTheme {
  /// The app theme.
  ///
  /// [seedColor] carries the tenant's `primaryColorHex`. It deliberately does
  /// **not** seed the global [ColorScheme] any more: this system is monochrome,
  /// and a per-church hue leaking into buttons, focus rings and chrome would
  /// dismantle it. Tenant color is confined to identity marks — read it with
  /// [tenantAccent] and use it on the church avatar / logo mark only.
  static ThemeData light({Color? seedColor}) => _build();

  /// The tenant's identity color, clamped to a legible range.
  ///
  /// Returns [AppColors.signalGreen] — the reference's brand-mark accent —
  /// when a church has not set one. Use for identity marks only: avatars,
  /// logo lockups, the church badge in the shell. Never for actions, state,
  /// borders, or surfaces.
  static Color tenantAccent(Color? seedColor) => seedColor ?? AppColors.signalGreen;

  /// Retained for source compatibility. The system is shadowless by design;
  /// this is intentionally empty so any surviving call site is a no-op rather
  /// than a compile error.
  @Deprecated(
    'Hellotime is flat. Use a 1px AppColors.fog border and an AppColors.mist '
    'surface instead of elevation.',
  )
  static List<BoxShadow> get cardShadow => const <BoxShadow>[];

  static ThemeData _build() {
    // A monochrome scheme. Nothing here introduces a hue: "primary" is the
    // Charcoal action fill, surfaces are Paper, outlines are Fog.
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.charcoal,
      onPrimary: AppColors.paper,
      primaryContainer: AppColors.mist,
      onPrimaryContainer: AppColors.ink,
      secondary: AppColors.graphite,
      onSecondary: AppColors.paper,
      secondaryContainer: AppColors.mist,
      onSecondaryContainer: AppColors.ink,
      tertiary: AppColors.smoke,
      onTertiary: AppColors.paper,
      error: AppColors.ink,
      onError: AppColors.paper,
      errorContainer: AppColors.mist,
      onErrorContainer: AppColors.ink,
      surface: AppColors.paper,
      onSurface: AppColors.ink,
      surfaceContainerLowest: AppColors.paper,
      surfaceContainerLow: AppColors.mist,
      surfaceContainer: AppColors.mist,
      surfaceContainerHigh: AppColors.ash,
      surfaceContainerHighest: AppColors.ash,
      onSurfaceVariant: AppColors.smoke,
      outline: AppColors.fog,
      outlineVariant: AppColors.ash,
      inverseSurface: AppColors.charcoal,
      onInverseSurface: AppColors.paper,
      shadow: Colors.transparent,
      scrim: Color(0x66151619),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      // Pure white canvas — no cool-gray page tint.
      scaffoldBackgroundColor: AppColors.paper,
      colorScheme: scheme,
      dividerColor: AppColors.fog,
      shadowColor: Colors.transparent,
      splashFactory: InkSparkle.splashFactory,
      textTheme: AppTypography.textTheme(),
      fontFamily: AppTypography.textFamily,
    );

    return base.copyWith(
      iconTheme: const IconThemeData(color: AppColors.ink, size: 20),
      primaryIconTheme: const IconThemeData(color: AppColors.ink, size: 20),

      dividerTheme: const DividerThemeData(
        color: AppColors.fog,
        thickness: AppBorders.hairline,
        space: AppBorders.hairline,
      ),

      // Nav strip: white, hairline bottom border, 18/600 title.
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: AppColors.paper,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        titleTextStyle: TextStyle(
          fontFamily: AppTypography.textFamily,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          height: 1.2,
          color: AppColors.ink,
        ),
        iconTheme: IconThemeData(color: AppColors.ink, size: 20),
        shape: Border(
          bottom: BorderSide(color: AppColors.fog, width: AppBorders.hairline),
        ),
      ),

      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.paper,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTypography.headingSm,
        contentTextStyle: AppTypography.body,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
          side: BorderSide(color: AppColors.fog, width: AppBorders.hairline),
        ),
      ),

      cardTheme: const CardThemeData(
        color: AppColors.paper,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
          side: BorderSide(color: AppColors.fog, width: AppBorders.hairline),
        ),
      ),

      // Inputs: Mist fill, 12px radius, Ash at rest, Ink on focus.
      // Focus is communicated by border darkness and weight, not by color.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.mist,
        floatingLabelBehavior: FloatingLabelBehavior.never,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 14,
        ),
        border: _inputBorder(AppColors.ash),
        enabledBorder: _inputBorder(AppColors.ash),
        focusedBorder: _inputBorder(AppColors.ink, width: 1.5),
        disabledBorder: _inputBorder(AppColors.ash),
        errorBorder: _inputBorder(AppColors.ink, width: 1.5),
        focusedErrorBorder: _inputBorder(AppColors.ink, width: 1.5),
        labelStyle: AppTypography.body.copyWith(color: AppColors.smoke),
        floatingLabelStyle: AppTypography.label,
        hintStyle: AppTypography.body.copyWith(color: AppColors.pewter),
        helperStyle: AppTypography.caption,
        // Errors read as weight, not as red.
        errorStyle: AppTypography.caption.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w500,
        ),
        prefixIconColor: AppColors.smoke,
        suffixIconColor: AppColors.smoke,
      ),

      // Primary action: Charcoal fill, Paper text, 8px radius, 10×20 padding.
      filledButtonTheme: FilledButtonThemeData(style: _filledStyle()),
      elevatedButtonTheme: ElevatedButtonThemeData(style: _filledStyle()),

      // Ghost: transparent, Pewter hairline, Ink text, Mist wash on hover.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(AppColors.ink),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed)) {
              return AppColors.mist;
            }
            return Colors.transparent;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            final color = states.contains(WidgetState.hovered)
                ? AppColors.ink
                : AppColors.pewter;
            return BorderSide(color: color, width: AppBorders.hairline);
          }),
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
          textStyle: const WidgetStatePropertyAll(AppTypography.label),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(AppRadius.button)),
            ),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(AppColors.ink),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) return AppColors.mist;
            return Colors.transparent;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          textStyle: const WidgetStatePropertyAll(AppTypography.label),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(AppRadius.button)),
            ),
          ),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(AppColors.ink),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) return AppColors.mist;
            return Colors.transparent;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(AppRadius.button)),
            ),
          ),
        ),
      ),

      // Pills: 9999px, hairline, Mist when selected — never a colored chip.
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.paper,
        selectedColor: AppColors.mist,
        disabledColor: AppColors.mist,
        checkmarkColor: AppColors.ink,
        labelStyle: AppTypography.pill,
        secondaryLabelStyle: AppTypography.pill,
        side: const BorderSide(color: AppColors.fog, width: AppBorders.hairline),
        elevation: 0,
        pressElevation: 0,
        shadowColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.full)),
        ),
      ),

      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.smoke,
        textColor: AppColors.ink,
        titleTextStyle: AppTypography.label,
        subtitleTextStyle: AppTypography.micro,
        selectedColor: AppColors.ink,
        selectedTileColor: AppColors.mist,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.button)),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      ),

      // Inverse surface for transient messages — the sanctioned dark block.
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.charcoal,
        contentTextStyle: TextStyle(
          fontFamily: AppTypography.textFamily,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.5,
          color: AppColors.paper,
        ),
        actionTextColor: AppColors.paper,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.button)),
        ),
      ),

      tooltipTheme: const TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.charcoal,
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.button)),
        ),
        textStyle: TextStyle(
          fontFamily: AppTypography.textFamily,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.paper,
        ),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),

      // Tabs: selection is weight + a 2px Ink underline. No color shift.
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.ink,
        unselectedLabelColor: AppColors.smoke,
        labelStyle: AppTypography.labelStrong,
        unselectedLabelStyle: AppTypography.label,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: AppColors.fog,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: AppColors.ink, width: 2),
        ),
        overlayColor: WidgetStatePropertyAll(Colors.transparent),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.paper,
        indicatorColor: AppColors.mist,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.button)),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 20,
            color: selected ? AppColors.ink : AppColors.smoke,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return AppTypography.micro.copyWith(
            color: selected ? AppColors.ink : AppColors.smoke,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          );
        }),
      ),

      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: Border(
          right: BorderSide(color: AppColors.fog, width: AppBorders.hairline),
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
          side: BorderSide(color: AppColors.fog, width: AppBorders.hairline),
        ),
      ),

      popupMenuTheme: const PopupMenuThemeData(
        color: AppColors.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        textStyle: AppTypography.label,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.input)),
          side: BorderSide(color: AppColors.fog, width: AppBorders.hairline),
        ),
      ),

      menuTheme: const MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.paper),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
          elevation: WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(AppRadius.input)),
              side: BorderSide(color: AppColors.fog, width: AppBorders.hairline),
            ),
          ),
        ),
      ),

      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: AppTypography.body,
        menuStyle: const MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.paper),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
          elevation: WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(AppRadius.input)),
              side: BorderSide(color: AppColors.fog, width: AppBorders.hairline),
            ),
          ),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.paper;
          return AppColors.paper;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.charcoal;
          return AppColors.ash;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.charcoal;
          return AppColors.fog;
        }),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.charcoal;
          return Colors.transparent;
        }),
        checkColor: const WidgetStatePropertyAll(AppColors.paper),
        side: const BorderSide(color: AppColors.pewter, width: AppBorders.hairline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.bar)),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.charcoal;
          return AppColors.pewter;
        }),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.ink,
        linearTrackColor: AppColors.ash,
        circularTrackColor: AppColors.ash,
        linearMinHeight: 4,
      ),

      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(AppRadius.bar),
        thickness: const WidgetStatePropertyAll(6),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) return AppColors.smoke;
          return AppColors.fog;
        }),
      ),

      datePickerTheme: buildPillrDatePickerTheme(),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = AppBorders.hairline}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.input),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static ButtonStyle _filledStyle() {
    return ButtonStyle(
      foregroundColor: const WidgetStatePropertyAll(AppColors.paper),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return AppColors.pewter;
        // Hover lifts to pure Ink.
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed)) {
          return AppColors.ink;
        }
        return AppColors.charcoal;
      }),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      ),
      minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(
          fontFamily: AppTypography.textFamily,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      ),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.button)),
        ),
      ),
    );
  }
}
