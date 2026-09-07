import 'package:flutter/material.dart';

/// The VouchFlow v2 palette, taken from the design's token block so the app,
/// the web client and the printed voucher read as one product.
///
/// Dark is the product's default appearance; light is a stored preference.
class VfColors {
  const VfColors._();

  // ── dark (default) ──
  static const bg = Color(0xFF070A12);
  static const elev1 = Color(0xFF0C111D);
  static const elev2 = Color(0xFF111827);
  static const elev3 = Color(0xFF161F31);
  static const text = Color(0xFFEEF2FA);
  static const line = Color(0x1F94AAD6); // rgba(148,170,214,.12)
  static const lineStrong = Color(0x3D94AAD6); // rgba(148,170,214,.24)

  // ── light ──
  static const lightBg = Color(0xFFF7F9FC);
  static const lightElev1 = Color(0xFFFFFFFF);
  static const lightElev2 = Color(0xFFF2F5FA);
  static const lightElev3 = Color(0xFFE9EEF6);
  static const lightText = Color(0xFF0B1220);
  static const lightLine = Color(0x1A0F2042);
  static const lightLineStrong = Color(0x330F2042);

  // ── the blue-to-cyan accent that carries every primary action ──
  static const accent = Color(0xFF2F7BF6);
  static const accentMid = Color(0xFF22A7E8);
  static const accentEnd = Color(0xFF22D3EE);
  static const accent400 = Color(0xFF5B9BFF);
  static const accent500 = Color(0xFF2F7BF6);
  static const accent600 = Color(0xFF63A9FF);
  static const accent700 = Color(0xFF8CC2FF);
  static const accentInk = Color(0xFF05121F); // ink on the gradient

  // Accent tints for chips and icon plates.
  static const accent100Dark = Color(0x1F2F7BF6);
  static const accent100Light = Color(0xFFEAF2FF);

  // ── semantic ──
  static const ok = Color(0xFF34D399);
  static const warn = Color(0xFFFBBF24);
  static const bad = Color(0xFFFB7185);

  // ── the printed sheet, always ink on paper ──
  static const paper = Color(0xFFFFFFFF);
  static const paperInk = Color(0xFF0B1220);

  /// The gradient behind every primary action.
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accentMid, accentEnd],
    stops: [0.0, 0.55, 1.0],
  );
}

/// Palette values that depend on the active appearance.
extension VfPalette on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get vfBg => isDark ? VfColors.bg : VfColors.lightBg;
  Color get vfElev1 => isDark ? VfColors.elev1 : VfColors.lightElev1;
  Color get vfElev2 => isDark ? VfColors.elev2 : VfColors.lightElev2;
  Color get vfElev3 => isDark ? VfColors.elev3 : VfColors.lightElev3;
  Color get vfInk => isDark ? VfColors.text : VfColors.lightText;
  Color get vfLine => isDark ? VfColors.line : VfColors.lightLine;
  Color get vfLineStrong =>
      isDark ? VfColors.lineStrong : VfColors.lightLineStrong;
  Color get vfMuted => Theme.of(this).textTheme.bodySmall?.color ?? vfInk;
  Color get vfAccent => isDark ? VfColors.accent600 : VfColors.accent500;
  Color get vfAccentTint =>
      isDark ? VfColors.accent100Dark : VfColors.accent100Light;
}

class VfTheme {
  const VfTheme._();

  static const fontFamily = 'Poppins';

  /// Radii, from the design: 6 / 10 / 14 / 18.
  static const rSm = 6.0;
  static const rMd = 10.0;
  static const rLg = 14.0;
  static const rXl = 18.0;

  /// The ink a gradient-filled button paints on itself. Progress indicators
  /// inside such a button must use this, never plain white.
  static Color onPrimary(BuildContext context) => VfColors.accentInk;

  static ThemeData light() => _base(
    brightness: Brightness.light,
    background: VfColors.lightBg,
    surface: VfColors.lightElev1,
    field: VfColors.lightElev2,
    onSurface: VfColors.lightText,
    accent: VfColors.accent500,
    divider: VfColors.lightLine,
    muted: const Color(0xFF5A6782),
  );

  static ThemeData dark() => _base(
    brightness: Brightness.dark,
    background: VfColors.bg,
    surface: VfColors.elev1,
    field: VfColors.elev2,
    onSurface: VfColors.text,
    accent: VfColors.accent600,
    divider: VfColors.line,
    muted: const Color(0xFF94A3BE),
  );

  static ThemeData _base({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color field,
    required Color onSurface,
    required Color accent,
    required Color divider,
    required Color muted,
  }) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: VfColors.accent500,
          brightness: brightness,
        ).copyWith(
          primary: accent,
          surface: background,
          onSurface: onSurface,
          error: VfColors.bad,
          outline: divider,
        );

    // Tight display type, matching the web client and the printed voucher.
    TextStyle heading(double size, [FontWeight weight = FontWeight.w600]) =>
        TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          fontWeight: weight,
          height: 1.1,
          letterSpacing: -size * 0.03,
          color: onSurface,
        );

    TextStyle body(double size, [FontWeight weight = FontWeight.w400]) =>
        TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          fontWeight: weight,
          height: 1.5,
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
        displaySmall: heading(32, FontWeight.w600),
        headlineMedium: heading(27),
        headlineSmall: heading(22),
        titleLarge: heading(19),
        titleMedium: heading(16.5),
        titleSmall: body(14, FontWeight.w600),
        bodyLarge: body(16),
        bodyMedium: body(14.5),
        bodySmall: body(13).copyWith(color: muted),
        labelLarge: body(14.5, FontWeight.w600),
        labelSmall: TextStyle(
          fontFamily: fontFamily,
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.9,
          color: muted,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: heading(19),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rLg),
          side: BorderSide(color: divider),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: VfColors.accent500,
          foregroundColor: VfColors.accentInk,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rMd),
          ),
          textStyle: body(15, FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurface,
          backgroundColor: field,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          side: BorderSide(
            color: brightness == Brightness.dark
                ? VfColors.lineStrong
                : VfColors.lightLineStrong,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rMd),
          ),
          textStyle: body(15, FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: body(14.5, FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: field,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: const BorderSide(color: VfColors.accent500, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: const BorderSide(color: VfColors.bad),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: const BorderSide(color: VfColors.bad, width: 1.6),
        ),
        labelStyle: body(13.5).copyWith(color: muted),
        hintStyle: body(14.5).copyWith(color: muted),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: field,
        side: BorderSide(color: divider),
        labelStyle: body(12.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rSm)),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: VfColors.accent500.withValues(alpha: 0.18),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rMd),
        ),
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(body(11.5, FontWeight.w500)),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(rXl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rXl),
          side: BorderSide(color: divider),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: brightness == Brightness.dark
            ? VfColors.elev3
            : VfColors.lightText,
        contentTextStyle: body(14).copyWith(
          color: brightness == Brightness.dark
              ? VfColors.text
              : VfColors.lightBg,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rMd)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: VfColors.accent500,
        linearMinHeight: 3,
      ),
    );
  }
}

/// Count badges. Small bold text on a saturated ground needs the pairing
/// chosen deliberately — white on the warn amber measures far too low.
class VfBadge {
  const VfBadge._();

  static Color background(Brightness brightness) =>
      VfColors.warn.withValues(alpha: brightness == Brightness.dark ? .22 : .2);

  static Color foreground(Brightness brightness) =>
      brightness == Brightness.dark ? VfColors.warn : const Color(0xFF7A5300);
}

/// Status colours shared by chips, timelines and list rows.
///
/// The tags mirror the web client: neutral for drafts, amber for anything
/// waiting on a person, blue for approved-and-awaiting-payment, green for
/// paid, rose for rejected or returned.
class VfStatus {
  const VfStatus._();

  static Color _base(String tag) {
    switch (tag) {
      case 'tag-accent':
        return VfColors.ok;
      case 'tag-accent-2':
        return VfColors.bad;
      case 'tag-info':
        return VfColors.accent500;
      case 'tag-outline':
        return VfColors.warn;
      default:
        return const Color(0xFF8494B0);
    }
  }

  static Color background(String tag, Brightness brightness) {
    if (tag == 'tag-neutral' || tag.isEmpty) {
      return brightness == Brightness.dark
          ? VfColors.elev3
          : VfColors.lightElev3;
    }
    return _base(
      tag,
    ).withValues(alpha: brightness == Brightness.dark ? .15 : .13);
  }

  static Color foreground(String tag, Brightness brightness) {
    if (tag == 'tag-neutral' || tag.isEmpty) {
      return brightness == Brightness.dark
          ? const Color(0xFFB9C4D8)
          : const Color(0xFF44506A);
    }
    // The amber and green read well on dark; on light they need darkening.
    final base = _base(tag);
    if (brightness == Brightness.dark) return base;
    switch (tag) {
      case 'tag-accent':
        return const Color(0xFF0F7A54);
      case 'tag-accent-2':
        return const Color(0xFFA3183A);
      case 'tag-info':
        return const Color(0xFF1A4FAE);
      case 'tag-outline':
        return const Color(0xFF7A5300);
      default:
        return base;
    }
  }

  static Color border(String tag, Brightness brightness) {
    if (tag == 'tag-neutral' || tag.isEmpty) {
      return brightness == Brightness.dark ? VfColors.line : VfColors.lightLine;
    }
    return _base(tag).withValues(alpha: .34);
  }
}
