import 'package:flutter/material.dart';

/// The broadsheet palette, carried over from the design system so the app and
/// the web client read as one product.
class VfColors {
  const VfColors._();

  // Light
  static const bg = Color(0xFFF3F2F2);
  static const surface = Color(0xFFEAE9E9);
  static const text = Color(0xFF201E1D);
  static const accent = Color(0xFF0088B0);
  static const accent2 = Color(0xFFD6006C);
  static const processYellow = Color(0xFFEDBB00);

  static const neutral100 = Color(0xFFF8F4F4);
  static const neutral200 = Color(0xFFEAE7E7);
  static const neutral300 = Color(0xFFD7D3D3);
  static const neutral400 = Color(0xFFBAB6B6);
  static const neutral500 = Color(0xFF9B9797);
  static const neutral600 = Color(0xFF7D7979);
  static const neutral700 = Color(0xFF605D5D);
  static const neutral800 = Color(0xFF444141);
  static const neutral900 = Color(0xFF2D2B2B);

  static const accent100 = Color(0xFFE9F8FF);
  static const accent200 = Color(0xFFCBEEFF);
  static const accent500 = Color(0xFF38A6CF);
  static const accent600 = Color(0xFF1186AC);
  static const accent700 = Color(0xFF006786);
  static const accent800 = Color(0xFF004961);

  static const accent2100 = Color(0xFFFFF1F4);
  static const accent2500 = Color(0xFFFF458E);
  static const accent2600 = Color(0xFFD82071);
  static const accent2700 = Color(0xFFAA0B56);
  static const accent2800 = Color(0xFF790E3D);

  // Dark
  static const darkBg = Color(0xFF191817);
  static const darkSurface = Color(0xFF232120);
  static const darkText = Color(0xFFF3F2F2);
  static const darkAccent = Color(0xFF62C5EE);
}

class VfTheme {
  const VfTheme._();

  static const fontFamily = 'Poppins';

  /// The ink a filled button paints on its own background — near-white on the
  /// light theme's cyan, near-black on the dark theme's lighter blue. Progress
  /// indicators placed inside such a button must use this, not plain white.
  static Color onPrimary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
      ? VfColors.bg
      : VfColors.darkBg;

  static ThemeData light() => _base(
    brightness: Brightness.light,
    background: VfColors.bg,
    surface: VfColors.neutral100,
    onSurface: VfColors.text,
    accent: VfColors.accent,
    divider: VfColors.text.withValues(alpha: 0.16),
    muted: VfColors.neutral700,
    field: VfColors.surface,
  );

  static ThemeData dark() => _base(
    brightness: Brightness.dark,
    background: VfColors.darkBg,
    surface: VfColors.darkSurface,
    onSurface: VfColors.darkText,
    accent: VfColors.darkAccent,
    divider: VfColors.darkText.withValues(alpha: 0.20),
    muted: const Color(0xFFBAB6B6),
    field: const Color(0xFF2D2B2B),
  );

  static ThemeData _base({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color onSurface,
    required Color accent,
    required Color divider,
    required Color muted,
    required Color field,
  }) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: brightness,
        ).copyWith(
          primary: accent,
          surface: background,
          onSurface: onSurface,
          error: brightness == Brightness.light
              ? VfColors.accent2600
              : VfColors.accent2500,
        );

    // The design sets tight, editorial type. Letter-spacing is pulled in on the
    // display sizes to match the printed voucher.
    TextStyle heading(double size, [FontWeight weight = FontWeight.w600]) =>
        TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          fontWeight: weight,
          height: 1.14,
          letterSpacing: -size * 0.016,
          color: onSurface,
        );

    TextStyle body(double size, [FontWeight weight = FontWeight.w400]) =>
        TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          fontWeight: weight,
          height: 1.45,
          color: onSurface,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      dividerColor: divider,
      dividerTheme: DividerThemeData(color: divider, thickness: 1, space: 1),
      splashFactory: InkSparkle.splashFactory,
      textTheme: TextTheme(
        displaySmall: heading(34, FontWeight.w700),
        headlineMedium: heading(28, FontWeight.w700),
        headlineSmall: heading(23),
        titleLarge: heading(20),
        titleMedium: heading(17),
        titleSmall: body(14, FontWeight.w600),
        bodyLarge: body(16),
        bodyMedium: body(14.5),
        bodySmall: body(13).copyWith(color: muted),
        labelLarge: body(14, FontWeight.w600),
        labelSmall: TextStyle(
          fontFamily: fontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.1,
          color: muted,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: heading(19),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(2),
          side: BorderSide(color: divider),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: brightness == Brightness.light
              ? background
              : VfColors.darkBg,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
          textStyle: body(15, FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurface,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          side: BorderSide(color: divider),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
          textStyle: body(15, FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brightness == Brightness.light
              ? VfColors.accent700
              : VfColors.darkAccent,
          textStyle: body(14.5, FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: field,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(2),
          borderSide: BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(2),
          borderSide: BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(2),
          borderSide: BorderSide(color: accent, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(2),
          borderSide: BorderSide(color: scheme.error),
        ),
        labelStyle: body(13.5).copyWith(color: muted),
        hintStyle: body(14.5).copyWith(color: muted),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        side: BorderSide(color: divider),
        labelStyle: body(12.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        indicatorColor: accent.withValues(alpha: 0.16),
        height: 66,
        labelTextStyle: WidgetStatePropertyAll(body(11.5, FontWeight.w500)),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: brightness == Brightness.light
            ? VfColors.neutral900
            : VfColors.neutral200,
        contentTextStyle: body(14).copyWith(
          color: brightness == Brightness.light
              ? VfColors.neutral100
              : VfColors.neutral900,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearMinHeight: 3,
      ),
    );
  }
}

/// Count badges. Small bold text on a saturated ground needs the pairing chosen
/// per theme: white on #ff458e measures only about 2.6:1.
class VfBadge {
  const VfBadge._();

  static Color background(Brightness brightness) =>
      brightness == Brightness.dark ? VfColors.accent2500 : VfColors.accent2600;

  static Color foreground(Brightness brightness) =>
      brightness == Brightness.dark ? VfColors.neutral900 : Colors.white;
}

/// Status colours shared by chips, timelines and list rows.
class VfStatus {
  const VfStatus._();

  static Color background(String tag, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    switch (tag) {
      case 'tag-accent':
        return dark
            ? VfColors.accent800.withValues(alpha: .45)
            : VfColors.accent100;
      case 'tag-accent-2':
        return dark
            ? VfColors.accent2800.withValues(alpha: .45)
            : VfColors.accent2100;
      case 'tag-outline':
        return Colors.transparent;
      default:
        return dark ? VfColors.neutral900 : VfColors.neutral200;
    }
  }

  static Color foreground(String tag, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    switch (tag) {
      case 'tag-accent':
        return dark ? VfColors.accent200 : VfColors.accent800;
      case 'tag-accent-2':
        return dark ? const Color(0xFFFFC0D0) : VfColors.accent2800;
      case 'tag-outline':
        return dark ? VfColors.darkAccent : VfColors.accent700;
      default:
        return dark ? VfColors.neutral300 : VfColors.neutral800;
    }
  }

  static Color border(String tag, Brightness brightness) =>
      tag == 'tag-outline' ? foreground(tag, brightness) : Colors.transparent;
}
