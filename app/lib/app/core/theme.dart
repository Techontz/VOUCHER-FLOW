import 'package:flutter/material.dart';

/// A company's interface colour (companies.color_theme), matching the web
/// client's palettes. Crimson is the product's own colour and the default for
/// any company that has not chosen; the other four stay exactly as they were
/// for companies that picked them.
class VfAccentPalette {
  const VfAccentPalette._({
    required this.key,
    required this.solid,
    required this.pressed,
    required this.mid,
    required this.end,
    required this.lighter,
    required this.onDark,
    required this.onDarkSoft,
    required this.onLight,
    required this.tintLight,
    required this.onSolid,
  });

  final String key;

  /// Filled buttons, focus rings, progress, "done" marks.
  final Color solid;

  /// A filled button while it is held down.
  final Color pressed;
  final Color mid, end;

  /// Selected borders.
  final Color lighter;

  /// Accent text and icons on the dark ground, and a softer tone for avatars.
  final Color onDark, onDarkSoft;

  /// Accent text and icons on the light ground.
  final Color onLight;

  /// Chip and icon-plate tint on the light ground.
  final Color tintLight;

  /// The ink a filled button paints on [solid], at 4.5:1 or better.
  final Color onSolid;

  static const _darkInk = Color(0xFF05121F);

  static const crimson = VfAccentPalette._(
    key: 'crimson',
    solid: Color(0xFFB8132A),
    pressed: Color(0xFF9F0F23),
    mid: Color(0xFFB8132A),
    end: Color(0xFFB8132A),
    lighter: Color(0xFFFF6B78),
    onDark: Color(0xFFFF6B78),
    onDarkSoft: Color(0xFFFF9AA3),
    onLight: Color(0xFFB8132A),
    tintLight: Color(0xFFFBE8EA),
    onSolid: Color(0xFFFFFFFF),
  );

  static const blue = VfAccentPalette._(
    key: 'blue',
    solid: Color(0xFF2F7BF6),
    pressed: Color(0xFF2266D6),
    mid: Color(0xFF22A7E8),
    end: Color(0xFF22D3EE),
    lighter: Color(0xFF5B9BFF),
    onDark: Color(0xFF63A9FF),
    onDarkSoft: Color(0xFF8CC2FF),
    onLight: Color(0xFF2F7BF6),
    tintLight: Color(0xFFEAF2FF),
    onSolid: _darkInk,
  );

  static const emerald = VfAccentPalette._(
    key: 'emerald',
    solid: Color(0xFF10B981),
    pressed: Color(0xFF0E9F6E),
    mid: Color(0xFF2DD4BF),
    end: Color(0xFF5EEAD4),
    lighter: Color(0xFF34D399),
    onDark: Color(0xFF34D399),
    onDarkSoft: Color(0xFF6EE7B7),
    onLight: Color(0xFF047857),
    tintLight: Color(0xFFE7F8F1),
    onSolid: _darkInk,
  );

  static const violet = VfAccentPalette._(
    key: 'violet',
    solid: Color(0xFF9467F9),
    pressed: Color(0xFF7F52E6),
    mid: Color(0xFFA78BFA),
    end: Color(0xFFC4B5FD),
    lighter: Color(0xFFA78BFA),
    onDark: Color(0xFFA78BFA),
    onDarkSoft: Color(0xFFC4B5FD),
    onLight: Color(0xFF6D28D9),
    tintLight: Color(0xFFF1ECFF),
    onSolid: _darkInk,
  );

  static const rose = VfAccentPalette._(
    key: 'rose',
    solid: Color(0xFFF43F5E),
    pressed: Color(0xFFDB2F4E),
    mid: Color(0xFFFB7185),
    end: Color(0xFFFDA4AF),
    lighter: Color(0xFFFB7185),
    onDark: Color(0xFFFB7185),
    onDarkSoft: Color(0xFFFDA4AF),
    onLight: Color(0xFFBE123C),
    tintLight: Color(0xFFFFEEF1),
    onSolid: _darkInk,
  );

  /// Crimson first: it is the product's colour and the default.
  static const all = [crimson, blue, emerald, violet, rose];

  /// The palette for a stored key; anything unknown is crimson.
  static VfAccentPalette of(String? key) =>
      all.firstWhere((p) => p.key == key, orElse: () => crimson);
}

/// The VouchFlow palette, taken from the design's token block so the app,
/// the web client and the printed voucher read as one product.
///
/// Dark is the product's default appearance; light is a stored preference.
class VfColors {
  const VfColors._();

  // ── dark (default) ──
  // Five neutral steps, never pure black. Depth comes from the step and a
  // hairline, not from shadow.
  static const bg = Color(0xFF0D0E10); // app background
  static const nav = Color(0xFF111215); // tab bar
  static const elev1 = Color(0xFF16171A); // surface: cards
  static const elev2 = Color(0xFF1C1D21); // raised: inputs, hovers
  static const elev3 = Color(0xFF222328); // overlay: sheets, dialogs, menus
  static const line = Color(0xFF26272C); // hairline
  static const lineStrong = Color(0xFF34353B); // strong border
  static const text = Color(0xFFECEEF1); // ink 1: titles, values
  static const text2 = Color(0xFFB3B6BD); // ink 2: body, labels
  static const muted = Color(0xFF8B8F98); // ink 3: metadata, hints
  static const faint = Color(0xFF62656D); // ink 4: disabled only

  // ── light ──
  static const lightBg = Color(0xFFF6F7F9);
  static const lightNav = Color(0xFFFFFFFF);
  static const lightElev1 = Color(0xFFFFFFFF);
  static const lightElev2 = Color(0xFFF1F2F5);
  static const lightElev3 = Color(0xFFFFFFFF);
  static const lightText = Color(0xFF15171C);
  static const lightText2 = Color(0xFF454952);
  static const lightMuted = Color(0xFF646975);
  static const lightFaint = Color(0xFF9A9EA7);
  static const lightLine = Color(0xFFE3E5E9);
  static const lightLineStrong = Color(0xFFCFD2D8);

  // ── the accent that carries every primary action ──
  /// The company's palette. Set by SessionService before the themes are
  /// built; the app rebuilds its themes whenever it changes.
  static VfAccentPalette palette = VfAccentPalette.crimson;

  static Color get accent => palette.solid;
  static Color get accentMid => palette.mid;
  static Color get accentEnd => palette.end;
  static Color get accent400 => palette.lighter;
  static Color get accent500 => palette.solid;
  static Color get accent600 => palette.onDark;
  static Color get accent700 => palette.onDarkSoft;

  /// Dark ink, for text on a light accent tone (avatars).
  static const accentInk = Color(0xFF05121F);

  /// The ink on a filled accent button: white on crimson, dark on the rest.
  static Color get onAccent => palette.onSolid;

  // Accent tints for chips and icon plates.
  static Color get accent100Dark => palette.solid.withValues(alpha: .14);
  static Color get accent100Light => palette.tintLight;

  // ── semantic: always paired with an icon and a label ──
  static const ok = Color(0xFF3FBF83);
  static const okSolid = Color(0xFF177A4F);
  static const warn = Color(0xFFE9A23B);
  static const bad = Color(0xFFF2645F);
  static const badSolid = Color(0xFFC7362F);
  static const info = Color(0xFF6AA3F5);

  // ── the printed sheet, always ink on paper ──
  static const paper = Color(0xFFFFFFFF);
  static const paperInk = Color(0xFF0B1220);

  /// Retained for callers that still ask for it; the design paints primary
  /// actions flat, so it is a single colour.
  static LinearGradient get gradient =>
      LinearGradient(colors: [accent, accent]);
}

/// Palette values that depend on the active appearance.
extension VfPalette on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get vfBg => isDark ? VfColors.bg : VfColors.lightBg;
  Color get vfNav => isDark ? VfColors.nav : VfColors.lightNav;
  Color get vfElev1 => isDark ? VfColors.elev1 : VfColors.lightElev1;
  Color get vfElev2 => isDark ? VfColors.elev2 : VfColors.lightElev2;
  Color get vfElev3 => isDark ? VfColors.elev3 : VfColors.lightElev3;
  Color get vfInk => isDark ? VfColors.text : VfColors.lightText;
  Color get vfInk2 => isDark ? VfColors.text2 : VfColors.lightText2;
  Color get vfMuted => isDark ? VfColors.muted : VfColors.lightMuted;
  Color get vfFaint => isDark ? VfColors.faint : VfColors.lightFaint;
  Color get vfLine => isDark ? VfColors.line : VfColors.lightLine;
  Color get vfLineStrong =>
      isDark ? VfColors.lineStrong : VfColors.lightLineStrong;

  /// Brand as text or icon.
  Color get vfAccent =>
      isDark ? VfColors.accent600 : VfColors.palette.onLight;

  /// Brand soft fill: selected chips, icon plates.
  Color get vfAccentTint =>
      isDark ? VfColors.accent100Dark : VfColors.accent100Light;

  // Semantic foregrounds, tuned per appearance.
  Color get vfOk => isDark ? VfColors.ok : const Color(0xFF137046);
  Color get vfWarn => isDark ? VfColors.warn : const Color(0xFF8A5A00);
  Color get vfBad => isDark ? VfColors.bad : const Color(0xFFB42A25);
  Color get vfInfo => isDark ? VfColors.info : const Color(0xFF2A5DB0);
}

class VfTheme {
  const VfTheme._();

  static const fontFamily = 'Poppins';

  /// A monospace face for voucher numbers and references. No font is
  /// bundled for it: each platform supplies its own.
  static const monoFamily = 'monospace';
  static const monoFallback = [
    'SF Mono',
    'Menlo',
    'Roboto Mono',
    'Consolas',
    'Courier New',
  ];

  /// Radii: chips 8, inputs and buttons 12, cards 16, sheets 22.
  static const rSm = 8.0;
  static const rMd = 12.0;
  static const rLg = 16.0;
  static const rXl = 22.0;

  /// The ink a filled primary button paints on itself. Progress indicators
  /// inside such a button must use this, never plain white.
  static Color onPrimary(BuildContext context) => VfColors.onAccent;

  static const tabular = [FontFeature.tabularFigures()];

  static ThemeData light() => _base(
    brightness: Brightness.light,
    background: VfColors.lightBg,
    nav: VfColors.lightNav,
    surface: VfColors.lightElev1,
    field: VfColors.lightElev2,
    overlay: VfColors.lightElev3,
    onSurface: VfColors.lightText,
    body: VfColors.lightText2,
    accent: VfColors.palette.onLight,
    divider: VfColors.lightLine,
    strong: VfColors.lightLineStrong,
    muted: VfColors.lightMuted,
    faint: VfColors.lightFaint,
  );

  static ThemeData dark() => _base(
    brightness: Brightness.dark,
    background: VfColors.bg,
    nav: VfColors.nav,
    surface: VfColors.elev1,
    field: VfColors.elev2,
    overlay: VfColors.elev3,
    onSurface: VfColors.text,
    body: VfColors.text2,
    accent: VfColors.accent600,
    divider: VfColors.line,
    strong: VfColors.lineStrong,
    muted: VfColors.muted,
    faint: VfColors.faint,
  );

  static ThemeData _base({
    required Brightness brightness,
    required Color background,
    required Color nav,
    required Color surface,
    required Color field,
    required Color overlay,
    required Color onSurface,
    required Color body,
    required Color accent,
    required Color divider,
    required Color strong,
    required Color muted,
    required Color faint,
  }) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: VfColors.accent500,
          brightness: brightness,
        ).copyWith(
          primary: accent,
          onPrimary: VfColors.onAccent,
          surface: background,
          onSurface: onSurface,
          onSurfaceVariant: muted,
          surfaceContainerLowest: background,
          surfaceContainerLow: surface,
          surfaceContainer: surface,
          surfaceContainerHigh: field,
          surfaceContainerHighest: overlay,
          error: dark ? VfColors.bad : const Color(0xFFB42A25),
          outline: strong,
          outlineVariant: divider,
        );

    TextStyle heading(double size, [FontWeight weight = FontWeight.w600]) =>
        TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          fontWeight: weight,
          height: 1.2,
          letterSpacing: -size * 0.015,
          color: onSurface,
        );

    TextStyle text(double size, [FontWeight weight = FontWeight.w400]) =>
        TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          fontWeight: weight,
          height: 1.45,
          color: onSurface,
        );

    final radius = BorderRadius.circular(rMd);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      dividerColor: divider,
      dividerTheme: DividerThemeData(color: divider, thickness: 1, space: 1),
      splashFactory: InkRipple.splashFactory,
      textTheme: TextTheme(
        // Screen title 26 · greeting 22 · section 17 · body 14–15 · meta 12.5.
        displaySmall: heading(26),
        headlineMedium: heading(22),
        headlineSmall: heading(19),
        titleLarge: heading(17),
        titleMedium: text(15, FontWeight.w500),
        titleSmall: text(14, FontWeight.w500),
        bodyLarge: text(15),
        bodyMedium: text(14).copyWith(color: body),
        bodySmall: text(12.5).copyWith(color: muted),
        labelLarge: text(15, FontWeight.w500),
        labelMedium: text(13, FontWeight.w500).copyWith(color: body),
        labelSmall: TextStyle(
          fontFamily: fontFamily,
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.6,
          color: muted,
        ),
      ),
      iconTheme: IconThemeData(color: body, size: 20),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: text(15.5, FontWeight.w500),
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
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return dark ? VfColors.elev2 : VfColors.lightElev2;
            }
            if (states.contains(WidgetState.pressed)) {
              return VfColors.palette.pressed;
            }
            return VfColors.accent500;
          }),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? faint
                : VfColors.onAccent,
          ),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          minimumSize: const WidgetStatePropertyAll(Size(0, 50)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: radius),
          ),
          textStyle: WidgetStatePropertyAll(text(15, FontWeight.w500)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurface,
          backgroundColor: field,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          side: BorderSide(color: strong),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: text(15, FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          minimumSize: const Size(44, 44),
          textStyle: text(14, FontWeight.w500),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: onSurface,
          minimumSize: const Size(44, 44),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: VfColors.accent500,
        foregroundColor: VfColors.onAccent,
        elevation: 2,
        highlightElevation: 2,
        extendedTextStyle: text(14.5, FontWeight.w500),
        shape: const StadiumBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: field,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: dark ? divider : strong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: accent, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.error, width: 1.4),
        ),
        labelStyle: text(13.5).copyWith(color: muted),
        floatingLabelStyle: text(13.5).copyWith(color: body),
        hintStyle: text(14.5).copyWith(color: muted),
        prefixIconColor: muted,
        suffixIconColor: muted,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: field,
        selectedColor: onSurface,
        side: BorderSide(color: divider),
        labelStyle: text(13, FontWeight.w500).copyWith(color: body),
        secondaryLabelStyle: text(
          13,
          FontWeight.w500,
        ).copyWith(color: background),
        showCheckmark: false,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? overlay : field,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? onSurface : muted,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: divider)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          textStyle: WidgetStatePropertyAll(text(13, FontWeight.w500)),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? VfColors.accent500
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(VfColors.onAccent),
        side: BorderSide(color: strong, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? VfColors.accent500
              : field,
        ),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? VfColors.onAccent
              : muted,
        ),
        trackOutlineColor: WidgetStatePropertyAll(strong),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: nav,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        elevation: 0,
        height: 64,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected) ? accent : muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text(11, FontWeight.w500).copyWith(
            color: states.contains(WidgetState.selected) ? onSurface : muted,
          ),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: overlay,
        modalBackgroundColor: overlay,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: strong,
        dragHandleSize: const Size(36, 4),
        modalBarrierColor: Colors.black.withValues(alpha: dark ? .6 : .35),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(rXl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: overlay,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rLg),
          side: BorderSide(color: divider),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: overlay,
        surfaceTintColor: Colors.transparent,
        textStyle: text(14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rMd),
          side: BorderSide(color: divider),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? VfColors.elev3 : VfColors.lightText,
        contentTextStyle: text(
          14,
        ).copyWith(color: dark ? VfColors.text : VfColors.lightBg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearMinHeight: 3,
      ),
      listTileTheme: ListTileThemeData(iconColor: body),
    );
  }
}

/// Count badges on the tab bar: brand fill, white figure.
class VfBadge {
  const VfBadge._();

  static Color background(Brightness brightness) => VfColors.accent500;

  static Color foreground(Brightness brightness) => VfColors.onAccent;
}

/// Status colours for any tag-driven chip (the API's `status_tag`).
///
/// Voucher statuses themselves are drawn by `StatusBadge`, which pairs each
/// colour with an icon; this remains for the generic chips.
class VfStatus {
  const VfStatus._();

  static Color _base(String tag, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    switch (tag) {
      case 'tag-accent':
        return dark ? VfColors.ok : const Color(0xFF137046);
      case 'tag-accent-2':
        return dark ? VfColors.bad : const Color(0xFFB42A25);
      case 'tag-info':
        return dark ? VfColors.info : const Color(0xFF2A5DB0);
      case 'tag-outline':
        return dark ? VfColors.warn : const Color(0xFF8A5A00);
      default:
        return dark ? VfColors.text2 : VfColors.lightText2;
    }
  }

  static bool _neutral(String tag) => tag == 'tag-neutral' || tag.isEmpty;

  static Color background(String tag, Brightness brightness) {
    if (_neutral(tag)) {
      return brightness == Brightness.dark
          ? VfColors.elev2
          : VfColors.lightElev2;
    }
    return _base(tag, brightness).withValues(alpha: .13);
  }

  static Color foreground(String tag, Brightness brightness) =>
      _base(tag, brightness);

  static Color border(String tag, Brightness brightness) {
    if (_neutral(tag)) {
      return brightness == Brightness.dark ? VfColors.line : VfColors.lightLine;
    }
    return _base(tag, brightness).withValues(alpha: .28);
  }
}

/// The printed document's palette and type.
///
/// The voucher is white with dark ink whatever appearance the interface is
/// wearing, because it is a preview of a piece of paper. These are therefore
/// literal colours, not theme tokens.
class VfDoc {
  const VfDoc._();

  static const ink = Color(0xFF0B1220);
  static const body = Color(0xFF33405A);
  static const muted = Color(0xFF6B7789);
  static const faint = Color(0xFF98A2B3);
  static const rule = Color(0xFFE2E7EF);
  static const wash = Color(0xFFF6F8FC);
  static const paper = Color(0xFFFFFFFF);

  static const label = TextStyle(
    fontFamily: VfTheme.fontFamily,
    fontSize: 7.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.1,
    height: 1.4,
    color: faint,
  );

  static const strong = TextStyle(
    fontFamily: VfTheme.fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.35,
    color: ink,
  );

  static const bodyText = TextStyle(
    fontFamily: VfTheme.fontFamily,
    fontSize: 10,
    height: 1.55,
    color: body,
  );

  static const mutedStyle = TextStyle(
    fontFamily: VfTheme.fontFamily,
    fontSize: 9,
    height: 1.45,
    color: muted,
  );

  static const faintStyle = TextStyle(
    fontFamily: VfTheme.fontFamily,
    fontSize: 8.5,
    height: 1.4,
    color: faint,
  );

  // Convenience aliases so widgets read naturally.
}
