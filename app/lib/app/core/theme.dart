import 'package:flutter/material.dart';

/*
 * The VouchFlow design system, taken from the production web client
 * (web/styles/app.css) so the app and www.voucherflow.co.tz are one product.
 *
 * Every colour, radius and size a screen needs comes from here: through the
 * [VfTokens] object (`context.vf`) for anything that depends on the
 * appearance, or the static classes below. Screens never hard-code a colour.
 *
 * The older names (VfColors.bg, context.vfElev1 …) are kept as aliases onto
 * the same tokens so every existing widget follows the new system.
 */

/// A company's interface colour (companies.color_theme): the web client's
/// four palettes, each defined for light and dark exactly as in app.css.
class VfAccentPalette {
  const VfAccentPalette._({
    required this.key,
    required this.primaryLight,
    required this.primaryDark,
    required this.hoverLight,
    required this.hoverDark,
    required this.softLight,
    required this.softDark,
    required this.softStrongLight,
    required this.softStrongDark,
    required this.borderLight,
    required this.borderDark,
    required this.textLight,
    required this.textDark,
    required this.ring,
  });

  final String key;
  final Color primaryLight, primaryDark;
  final Color hoverLight, hoverDark;
  final Color softLight, softDark;
  final Color softStrongLight, softStrongDark;
  final Color borderLight, borderDark;
  final Color textLight, textDark;
  final Color ring;

  // ── legacy names, mapped onto the web palette ──
  Color get solid => primaryLight;
  Color get mid => hoverDark;
  Color get end => hoverDark;
  Color get lighter => borderLight;
  Color get onDark => textDark;
  Color get onDarkSoft => textDark;
  Color get onLight => textLight;
  Color get tintLight => softLight;

  static const blue = VfAccentPalette._(
    key: 'blue',
    primaryLight: Color(0xFF2563EB),
    primaryDark: Color(0xFF2563EB),
    hoverLight: Color(0xFF1D4ED8),
    hoverDark: Color(0xFF3B82F6),
    softLight: Color(0xFFEFF6FF),
    softDark: Color(0x242563EB), // rgba(37,99,235,.14)
    softStrongLight: Color(0xFFDBEAFE),
    softStrongDark: Color(0x3D2563EB), // .24
    borderLight: Color(0xFFBFDBFE),
    borderDark: Color(0x7360A5FA), // rgba(96,165,250,.45)
    textLight: Color(0xFF1D4ED8),
    textDark: Color(0xFF93C5FD),
    ring: Color(0xFF3B82F6),
  );

  static const emerald = VfAccentPalette._(
    key: 'emerald',
    primaryLight: Color(0xFF047857),
    primaryDark: Color(0xFF047F5C),
    hoverLight: Color(0xFF065F46),
    hoverDark: Color(0xFF059669),
    softLight: Color(0xFFECFDF5),
    softDark: Color(0x2110B981),
    softStrongLight: Color(0xFFD1FAE5),
    softStrongDark: Color(0x3810B981),
    borderLight: Color(0xFF6EE7B7),
    borderDark: Color(0x7334D399),
    textLight: Color(0xFF047857),
    textDark: Color(0xFF6EE7B7),
    ring: Color(0xFF10B981),
  );

  static const violet = VfAccentPalette._(
    key: 'violet',
    primaryLight: Color(0xFF6D28D9),
    primaryDark: Color(0xFF7C3AED),
    hoverLight: Color(0xFF5B21B6),
    hoverDark: Color(0xFF8B5CF6),
    softLight: Color(0xFFF5F3FF),
    softDark: Color(0x248B5CF6),
    softStrongLight: Color(0xFFEDE9FE),
    softStrongDark: Color(0x3D8B5CF6),
    borderLight: Color(0xFFC4B5FD),
    borderDark: Color(0x73A78BFA),
    textLight: Color(0xFF6D28D9),
    textDark: Color(0xFFC4B5FD),
    ring: Color(0xFF8B5CF6),
  );

  static const rose = VfAccentPalette._(
    key: 'rose',
    primaryLight: Color(0xFFBE123C),
    primaryDark: Color(0xFFD4163F),
    hoverLight: Color(0xFF9F1239),
    hoverDark: Color(0xFFE11D48),
    softLight: Color(0xFFFFF1F2),
    softDark: Color(0x21F43F5E),
    softStrongLight: Color(0xFFFFE4E6),
    softStrongDark: Color(0x38F43F5E),
    borderLight: Color(0xFFFDA4AF),
    borderDark: Color(0x73FB7185),
    textLight: Color(0xFFBE123C),
    textDark: Color(0xFFFDA4AF),
    ring: Color(0xFFF43F5E),
  );

  static const all = [blue, emerald, violet, rose];

  /// The palette for a stored key; anything unknown is blue.
  static VfAccentPalette of(String? key) =>
      all.firstWhere((p) => p.key == key, orElse: () => blue);
}

/// Every appearance-dependent token, exactly as the web client defines them.
/// Read it with `context.vf`.
class VfTokens {
  const VfTokens._({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.text2,
    required this.muted,
    required this.faint,
    required this.inputBg,
    required this.inputBorder,
    required this.inputDisabled,
    required this.placeholder,
    required this.success,
    required this.successSoft,
    required this.successStrong,
    required this.warning,
    required this.warningSoft,
    required this.warningStrong,
    required this.danger,
    required this.dangerSoft,
    required this.dangerStrong,
    required this.info,
    required this.infoSoft,
    required this.infoStrong,
    required this.neutral,
    required this.neutralSoft,
    required this.neutralStrong,
    required this.chrome,
    required this.chromeLine,
    required this.chromeHover,
    required this.chromeCard,
    required this.chromeText,
    required this.chromeMuted,
    required this.chromeLabel,
    required this.tabBar,
    required this.overlay,
    required this.cardShadow,
    required this.palette,
  });

  final Brightness brightness;

  /// Page ground, cards, and the two quieter surface steps.
  final Color background, surface, surface2, surface3;
  final Color border, borderStrong;

  /// Text: primary, secondary, muted, faint.
  final Color text, text2, muted, faint;

  final Color inputBg, inputBorder, inputDisabled, placeholder;

  /// Status families: text colour, soft ground, strong mark.
  final Color success, successSoft, successStrong;
  final Color warning, warningSoft, warningStrong;
  final Color danger, dangerSoft, dangerStrong;
  final Color info, infoSoft, infoStrong;
  final Color neutral, neutralSoft, neutralStrong;

  /// The navy app chrome: top bar and drawer (the web's sidebar).
  final Color chrome, chromeLine, chromeHover, chromeCard;
  final Color chromeText, chromeMuted, chromeLabel;

  /// The bottom tab bar.
  final Color tabBar;

  final Color overlay;
  final List<BoxShadow> cardShadow;

  final VfAccentPalette palette;

  bool get isDark => brightness == Brightness.dark;

  // The company's primary family, in this appearance.
  Color get primary => isDark ? palette.primaryDark : palette.primaryLight;
  Color get primaryHover => isDark ? palette.hoverDark : palette.hoverLight;
  Color get primarySoft => isDark ? palette.softDark : palette.softLight;
  Color get primarySoftStrong =>
      isDark ? palette.softStrongDark : palette.softStrongLight;
  Color get primaryBorder => isDark ? palette.borderDark : palette.borderLight;
  Color get primaryText => isDark ? palette.textDark : palette.textLight;
  Color get onPrimary => Colors.white;
  Color get ring => palette.ring;

  static VfTokens light(VfAccentPalette palette) => VfTokens._(
    brightness: Brightness.light,
    background: const Color(0xFFF2F4F8),
    surface: Colors.white,
    surface2: const Color(0xFFF9FAFB),
    surface3: const Color(0xFFF3F4F6),
    border: const Color(0xFFE5E7EB),
    borderStrong: const Color(0xFFD1D5DB),
    text: const Color(0xFF111827),
    text2: const Color(0xFF4B5563),
    muted: const Color(0xFF6B7280),
    faint: const Color(0xFF9CA3AF),
    inputBg: Colors.white,
    inputBorder: const Color(0xFFD1D5DB),
    inputDisabled: const Color(0xFFF9FAFB),
    placeholder: const Color(0xFF9CA3AF),
    success: const Color(0xFF166534),
    successSoft: const Color(0xFFDCFCE7),
    successStrong: const Color(0xFF16A34A),
    warning: const Color(0xFF9A3412),
    warningSoft: const Color(0xFFFFEDD5),
    warningStrong: const Color(0xFFEA580C),
    danger: const Color(0xFF991B1B),
    dangerSoft: const Color(0xFFFEE2E2),
    dangerStrong: const Color(0xFFDC2626),
    info: const Color(0xFF1E40AF),
    infoSoft: const Color(0xFFDBEAFE),
    infoStrong: const Color(0xFF2563EB),
    neutral: const Color(0xFF1F2937),
    neutralSoft: const Color(0xFFF3F4F6),
    neutralStrong: const Color(0xFF9CA3AF),
    // Light appearance: navy chrome around a light work surface.
    chrome: const Color(0xFF0F172A),
    chromeLine: const Color(0xFF1E293B),
    chromeHover: const Color(0xFF1E293B),
    chromeCard: const Color(0x8C1E293B),
    chromeText: const Color(0xFFCBD5E1),
    chromeMuted: const Color(0xFF94A3B8),
    chromeLabel: const Color(0xFF64748B),
    tabBar: Colors.white,
    overlay: const Color(0x80000000),
    cardShadow: const [
      BoxShadow(color: Color(0x0F0F172A), blurRadius: 18, offset: Offset(0, 6)),
      BoxShadow(color: Color(0x0A0F172A), blurRadius: 3, offset: Offset(0, 1)),
    ],
    palette: palette,
  );

  static VfTokens dark(VfAccentPalette palette) => VfTokens._(
    brightness: Brightness.dark,
    background: const Color(0xFF0B0F17),
    surface: const Color(0xFF111827),
    surface2: const Color(0xFF161E2C),
    surface3: const Color(0xFF1F2937),
    border: const Color(0xFF1F2937),
    borderStrong: const Color(0xFF374151),
    text: const Color(0xFFF3F4F6),
    text2: const Color(0xFFD1D5DB),
    muted: const Color(0xFF9CA3AF),
    faint: const Color(0xFF6B7280),
    inputBg: const Color(0xFF0F1623),
    inputBorder: const Color(0xFF374151),
    inputDisabled: const Color(0xFF161E2C),
    placeholder: const Color(0xFF6B7280),
    success: const Color(0xFF86EFAC),
    successSoft: const Color(0x2916A34A),
    successStrong: const Color(0xFF22C55E),
    warning: const Color(0xFFFDBA74),
    warningSoft: const Color(0x29EA580C),
    warningStrong: const Color(0xFFF97316),
    danger: const Color(0xFFFCA5A5),
    dangerSoft: const Color(0x29DC2626),
    dangerStrong: const Color(0xFFEF4444),
    info: const Color(0xFF93C5FD),
    infoSoft: const Color(0x2E2563EB),
    infoStrong: const Color(0xFF3B82F6),
    neutral: const Color(0xFFD1D5DB),
    neutralSoft: const Color(0x12FFFFFF),
    neutralStrong: const Color(0xFF6B7280),
    chrome: const Color(0xFF111827),
    chromeLine: const Color(0xFF1F2937),
    chromeHover: const Color(0xFF111827),
    chromeCard: const Color(0xE6111827),
    chromeText: const Color(0xFFD1D5DB),
    chromeMuted: const Color(0xFF9CA3AF),
    chromeLabel: const Color(0xFF6B7280),
    tabBar: const Color(0xFF111827),
    overlay: const Color(0xA6000000),
    cardShadow: const [
      BoxShadow(color: Color(0x66000000), blurRadius: 3, offset: Offset(0, 1)),
    ],
    palette: palette,
  );

  /// The drawer is a touch deeper than the top bar in dark, as on the web.
  Color get drawer => isDark ? const Color(0xFF030712) : chrome;
}

/// The sizes the web client uses, in logical pixels.
class VfSize {
  const VfSize._();

  static const radiusXs = 4.0;
  static const radiusS = 6.0;
  static const radiusM = 8.0;
  static const radiusL = 14.0; // buttons, inputs, cards, panels
  static const radiusXl = 20.0; // selection cards, sheets
  static const radiusCard = 20.0; // the create-voucher cards
  static const radiusPill = 999.0;

  static const controlH = 48.0; // buttons, tall for touch
  static const inputH = 52.0;
  static const topBarH = 60.0;
  static const tabBarH = 68.0;

  static const pagePad = 18.0; // the phone gutter
  static const gap = 12.0;
  static const cardPad = 16.0;

  static const iconS = 16.0;
  static const iconM = 20.0;
  static const iconL = 24.0;
}

/// Legacy colour names, now aliases onto the web tokens (default blue).
class VfColors {
  const VfColors._();

  // dark
  static const bg = Color(0xFF0B0F17);
  static const elev1 = Color(0xFF111827);
  static const elev2 = Color(0xFF161E2C);
  static const elev3 = Color(0xFF1F2937);
  static const text = Color(0xFFF3F4F6);
  static const line = Color(0xFF1F2937);
  static const lineStrong = Color(0xFF374151);

  // light
  static const lightBg = Color(0xFFF3F5F9);
  static const lightElev1 = Color(0xFFFFFFFF);
  static const lightElev2 = Color(0xFFF9FAFB);
  static const lightElev3 = Color(0xFFF3F4F6);
  static const lightText = Color(0xFF111827);
  static const lightLine = Color(0xFFE5E7EB);
  static const lightLineStrong = Color(0xFFD1D5DB);

  /// The company's palette. Set by SessionService before the themes are
  /// built; the app rebuilds its themes whenever it changes.
  static VfAccentPalette palette = VfAccentPalette.blue;

  static Color get accent => palette.primaryLight;
  static Color get accentMid => palette.primaryLight;
  static Color get accentEnd => palette.primaryLight;
  static Color get accent400 => palette.primaryLight;
  static Color get accent500 => palette.primaryLight;
  static Color get accent600 => palette.textDark;
  static Color get accent700 => palette.textDark;

  /// Text on the primary colour: white, as on every web button.
  static const accentInk = Colors.white;

  static Color get accent100Dark => palette.softDark;
  static Color get accent100Light => palette.softLight;

  // semantic marks (the "strong" family, readable in both appearances)
  static const ok = Color(0xFF16A34A);
  static const warn = Color(0xFFEA580C);
  static const bad = Color(0xFFDC2626);
  static const info = Color(0xFF2563EB);

  static const paper = Color(0xFFFFFFFF);
  static const paperInk = Color(0xFF0B1220);

  /// The web uses solid primary buttons; kept as a flat "gradient" so older
  /// callers paint the same solid colour.
  static LinearGradient get gradient =>
      LinearGradient(colors: [accent, accent]);
}

/// Appearance-dependent tokens and the legacy shortcuts.
extension VfPalette on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// Every token for the current appearance and company palette.
  VfTokens get vf =>
      isDark ? VfTokens.dark(VfColors.palette) : VfTokens.light(VfColors.palette);

  Color get vfBg => vf.background;
  Color get vfElev1 => vf.surface;
  Color get vfElev2 => vf.surface2;
  Color get vfElev3 => vf.surface3;
  Color get vfInk => vf.text;
  Color get vfLine => vf.border;
  Color get vfLineStrong => vf.borderStrong;
  Color get vfMuted => vf.muted;
  Color get vfAccent => vf.primaryText;
  Color get vfAccentTint => vf.primarySoft;
}

/// The type scale (Poppins, as on the web).
class VfType {
  const VfType._();

  static const family = 'Poppins';

  static TextStyle _t(double size, FontWeight w, {double h = 1.45, double ls = 0}) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: w,
        height: h,
        letterSpacing: ls,
      );

  /// Page title (web h1 on a phone: 26–30px, bold, tight).
  static final pageTitle = _t(26, FontWeight.w700, h: 1.15, ls: -0.5);

  /// Section / panel title (web 18px, 600).
  static final sectionTitle = _t(18, FontWeight.w600, h: 1.3, ls: -0.2);

  /// Card title.
  static final cardTitle = _t(16, FontWeight.w600, h: 1.35);

  static final body = _t(15, FontWeight.w400, h: 1.5);
  static final bodyStrong = _t(15, FontWeight.w600, h: 1.5);
  static final small = _t(13.5, FontWeight.w400, h: 1.45);
  static final meta = _t(12.5, FontWeight.w400, h: 1.4);

  /// Uppercase eyebrow / field label (web 11–13px, 600, tracked).
  static final eyebrow = _t(12.5, FontWeight.w600, h: 1.3, ls: 1.0);
  static final label = _t(14, FontWeight.w500, h: 1.35);

  /// Money and big figures.
  static final figure = _t(28, FontWeight.w700, h: 1.1, ls: -0.5);
  static final figureS = _t(20, FontWeight.w700, h: 1.2, ls: -0.3);
}

class VfTheme {
  const VfTheme._();

  static const fontFamily = VfType.family;

  /// Radii, from the web client: 6 / 10 / 14 / 18.
  static const rSm = VfSize.radiusS;
  static const rMd = VfSize.radiusL;
  static const rLg = VfSize.radiusXl;
  static const rXl = 28.0;

  /// The ink a primary button paints on itself: white, as on the web.
  static Color onPrimary(BuildContext context) => Colors.white;

  static ThemeData light() => _base(VfTokens.light(VfColors.palette));
  static ThemeData dark() => _base(VfTokens.dark(VfColors.palette));

  static ThemeData _base(VfTokens t) {
    final scheme = ColorScheme(
      brightness: t.brightness,
      primary: t.primary,
      onPrimary: Colors.white,
      primaryContainer: t.primarySoftStrong,
      onPrimaryContainer: t.primaryText,
      secondary: t.primary,
      onSecondary: Colors.white,
      error: t.dangerStrong,
      onError: Colors.white,
      surface: t.background,
      onSurface: t.text,
      surfaceContainerLowest: t.surface,
      surfaceContainerLow: t.surface,
      surfaceContainer: t.surface,
      surfaceContainerHigh: t.surface2,
      surfaceContainerHighest: t.surface3,
      onSurfaceVariant: t.muted,
      outline: t.borderStrong,
      outlineVariant: t.border,
    );

    TextStyle s(TextStyle base, Color c) => base.copyWith(color: c);

    final radius = BorderRadius.circular(VfSize.radiusL);

    return ThemeData(
      useMaterial3: true,
      brightness: t.brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: t.background,
      canvasColor: t.background,
      dividerColor: t.border,
      dividerTheme: DividerThemeData(color: t.border, thickness: 1, space: 1),
      splashFactory: InkRipple.splashFactory,
      textTheme: TextTheme(
        displaySmall: s(VfType.pageTitle.copyWith(fontSize: 28), t.text),
        headlineMedium: s(VfType.pageTitle, t.text),
        headlineSmall: s(VfType.sectionTitle.copyWith(fontSize: 20), t.text),
        titleLarge: s(VfType.sectionTitle, t.text),
        titleMedium: s(VfType.cardTitle, t.text),
        titleSmall: s(VfType.bodyStrong.copyWith(fontSize: 14.5), t.text),
        bodyLarge: s(VfType.body.copyWith(fontSize: 16), t.text),
        bodyMedium: s(VfType.body, t.text),
        bodySmall: s(VfType.small, t.muted),
        labelLarge: s(VfType.bodyStrong, t.text),
        labelMedium: s(VfType.label, t.text2),
        labelSmall: s(VfType.eyebrow.copyWith(fontSize: 11.5), t.muted),
      ),
      iconTheme: IconThemeData(color: t.text2, size: VfSize.iconM),
      appBarTheme: AppBarTheme(
        backgroundColor: t.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: t.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: VfType.cardTitle.copyWith(color: t.text, fontSize: 17),
        iconTheme: IconThemeData(color: t.text),
      ),
      cardTheme: CardThemeData(
        color: t.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: t.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (st) => st.contains(WidgetState.disabled)
                ? t.borderStrong
                : st.contains(WidgetState.pressed)
                ? t.primaryHover
                : t.primary,
          ),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          minimumSize: const WidgetStatePropertyAll(Size(0, VfSize.controlH)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: radius),
          ),
          textStyle: WidgetStatePropertyAll(
            VfType.bodyStrong.copyWith(fontSize: 15),
          ),
          elevation: const WidgetStatePropertyAll(0),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.text,
          backgroundColor: t.surface,
          minimumSize: const Size(0, VfSize.controlH),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          side: BorderSide(color: t.borderStrong),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: VfType.bodyStrong.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: t.primaryText,
          textStyle: VfType.bodyStrong.copyWith(fontSize: 14.5),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: t.text2,
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.inputBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: t.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: t.inputBorder),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: t.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: t.ring, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: Color(0xFFF87171)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2),
        ),
        labelStyle: VfType.label.copyWith(color: t.text2),
        floatingLabelStyle: VfType.label.copyWith(color: t.primaryText),
        hintStyle: VfType.body.copyWith(color: t.placeholder),
        helperStyle: VfType.meta.copyWith(color: t.muted),
        errorStyle: VfType.meta.copyWith(color: t.dangerStrong),
        prefixIconColor: t.faint,
        suffixIconColor: t.faint,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: t.surface,
        selectedColor: t.primarySoftStrong,
        side: BorderSide(color: t.borderStrong),
        labelStyle: VfType.small.copyWith(color: t.text2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VfSize.radiusPill),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: t.tabBar,
        surfaceTintColor: Colors.transparent,
        indicatorColor: t.primarySoftStrong,
        indicatorShape: const StadiumBorder(),
        height: VfSize.tabBarH,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (st) => VfType.meta.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: st.contains(WidgetState.selected) ? t.primary : t.muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (st) => IconThemeData(
            size: 21,
            color: st.contains(WidgetState.selected) ? t.primary : t.muted,
          ),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: t.surface,
        showDragHandle: true,
        dragHandleColor: t.borderStrong,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(rXl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: VfType.sectionTitle.copyWith(color: t.text),
        contentTextStyle: VfType.body.copyWith(color: t.text2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VfSize.radiusXl),
          side: BorderSide(color: t.border),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: t.drawer,
        surfaceTintColor: Colors.transparent,
        width: 300,
        shape: const RoundedRectangleBorder(),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: t.surface,
        surfaceTintColor: Colors.transparent,
        textStyle: VfType.small.copyWith(color: t.text, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: t.border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: t.isDark ? t.surface3 : t.text,
        contentTextStyle: VfType.small.copyWith(
          color: t.isDark ? t.text : Colors.white,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.primary,
        linearMinHeight: 3,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? t.primary : null,
        ),
        side: BorderSide(color: t.borderStrong, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VfSize.radiusXs),
        ),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? t.primary : t.surface3,
        ),
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackOutlineColor: WidgetStatePropertyAll(t.borderStrong),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: t.primaryText,
        unselectedLabelColor: t.muted,
        indicatorColor: t.primary,
        dividerColor: t.border,
        labelStyle: VfType.bodyStrong.copyWith(fontSize: 14.5),
        unselectedLabelStyle: VfType.body.copyWith(fontSize: 14.5),
      ),
    );
  }
}

/// Count badges: the web's solid red dot with white figures.
class VfBadge {
  const VfBadge._();

  static Color background(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFFEF4444)
      : const Color(0xFFDC2626);

  static Color foreground(Brightness brightness) => Colors.white;
}

/// Status colours for the web's `tag-*` classes, shared by badges, timelines
/// and list rows: neutral for drafts, info for anything in progress, success
/// for paid, danger for rejected or returned.
class VfStatus {
  const VfStatus._();

  static VfTokens _t(Brightness b) => b == Brightness.dark
      ? VfTokens.dark(VfColors.palette)
      : VfTokens.light(VfColors.palette);

  static Color background(String tag, Brightness brightness) {
    final t = _t(brightness);
    return switch (tag) {
      'tag-accent' => t.successSoft,
      'tag-accent-2' => t.dangerSoft,
      'tag-info' || 'tag-outline' => t.infoSoft,
      'tag-warn' => t.warningSoft,
      _ => t.neutralSoft,
    };
  }

  static Color foreground(String tag, Brightness brightness) {
    final t = _t(brightness);
    return switch (tag) {
      'tag-accent' => t.success,
      'tag-accent-2' => t.danger,
      'tag-info' || 'tag-outline' => t.info,
      'tag-warn' => t.warning,
      _ => t.neutral,
    };
  }

  /// The web badges have no border; kept for callers that draw one.
  static Color border(String tag, Brightness brightness) =>
      background(tag, brightness);
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
}
