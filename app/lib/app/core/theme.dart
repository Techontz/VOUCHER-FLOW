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

/// One soft light in the wallpaper: a radial bloom of [color] centred at
/// [center] (an [Alignment] over the screen) whose radius is [radius] times
/// the screen's longer side.
class VfGlow {
  const VfGlow(this.center, this.radius, this.color);

  final Alignment center;
  final double radius;
  final Color color;
}

/// Every appearance-dependent token. Read it with `context.vf`.
///
/// The interface is "liquid glass": a soft wallpaper ([wallpaper] and
/// [wallpaperGlows]) under translucent surfaces ([glassFill] and friends)
/// with a hairline [glassBorder] that brightens to [glassHighlight] along
/// the top edge. The opaque [surface] family is the colour a glass card
/// reads as over the wallpaper, for anything that must not show through
/// (menus, dropdowns, cut-out rings round badges).
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
    required this.wallpaper,
    required this.wallpaperGlows,
    required this.glassFill,
    required this.glassFillStrong,
    required this.glassRowFill,
    required this.glassBorder,
    required this.glassHighlight,
    required this.glassSheen,
    required this.glassShadow,
    required this.barFill,
    required this.sheetFill,
    required this.tabActive,
    required this.blurSigma,
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

  // ── liquid glass ──

  /// The page ground: a gradient, with [wallpaperGlows] painted over it.
  final LinearGradient wallpaper;
  final List<VfGlow> wallpaperGlows;

  /// A glass card's fill, and a denser one for raised controls (secondary
  /// buttons, the hero, chips).
  final Color glassFill, glassFillStrong;

  /// The cheap fill for list rows: translucent, drawn without blur.
  final Color glassRowFill;

  /// The hairline round every glass surface, and the brighter top edge.
  final Color glassBorder, glassHighlight;

  /// A faint light across the top of a glass surface.
  final Color glassSheen;

  /// The soft long shadow under glass (painted outside the shape only, so it
  /// never darkens the translucent fill).
  final List<BoxShadow> glassShadow;

  /// Bars that content can pass under (tab bar, top bars): at least 85%
  /// opaque so text behind never competes with the bar's own.
  final Color barFill;

  /// Sheets, dialogs and the drawer: nearly opaque glass.
  final Color sheetFill;

  /// The raised pill behind the current tab.
  final Color tabActive;

  /// Backdrop blur for bars, sheets and the few cards that blur.
  final double blurSigma;

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
    // "Glassy" light: white into pale sky blue, frosted white glass.
    background: const Color(0xFFF5F5F7),
    surface: Colors.white,
    surface2: const Color(0xFFF6F9FD),
    surface3: const Color(0xFFECF1F8),
    border: const Color(0xFFE0E7F0),
    borderStrong: const Color(0xFFCBD5E2),
    text: const Color(0xFF0F172A),
    text2: const Color(0xFF3D4859),
    muted: const Color(0xFF5B6576),
    faint: const Color(0xFF8D97A7),
    inputBg: const Color(0xB3FFFFFF),
    inputBorder: const Color(0xFFD5DEEA),
    inputDisabled: const Color(0x80F1F5FA),
    placeholder: const Color(0xFF8D97A7),
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
    neutralSoft: const Color(0xFFEEF2F7),
    neutralStrong: const Color(0xFF9CA3AF),
    // Navy chrome survives for the few full-bleed brand surfaces.
    chrome: const Color(0xFF0F172A),
    chromeLine: const Color(0xFF1E293B),
    chromeHover: const Color(0xFF1E293B),
    chromeCard: const Color(0x8C1E293B),
    chromeText: const Color(0xFFCBD5E1),
    chromeMuted: const Color(0xFF94A3B8),
    chromeLabel: const Color(0xFF64748B),
    tabBar: const Color(0xE6FFFFFF),
    overlay: const Color(0x590F172A),
    cardShadow: _lightCardShadow,
    palette: palette,
    wallpaper: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF7F7F9), Color(0xFFF4F4F7), Color(0xFFF2F2F5)],
      stops: [0, .5, 1],
    ),
    // A calm neutral ground with one faint light from above: content cards
    // are solid white, glass is kept for the bars and sheets over them.
    wallpaperGlows: [
      const VfGlow(Alignment(0, -1.25), .7, Color(0x140071E3)),
    ],
    glassFill: const Color(0xFFFFFFFF),
    glassFillStrong: const Color(0xD9FFFFFF),
    glassRowFill: const Color(0xFFFFFFFF),
    glassBorder: const Color(0x12000000),
    glassHighlight: const Color(0xFFFFFFFF),
    glassSheen: const Color(0x66FFFFFF),
    glassShadow: _lightShadow,
    barFill: const Color(0xE6FFFFFF),
    sheetFill: const Color(0xF2FAFCFF),
    tabActive: palette.softStrongLight,
    blurSigma: 24,
  );

  static const _lightShadow = [
    BoxShadow(
      color: Color(0x1A2B5DB8),
      blurRadius: 32,
      spreadRadius: -6,
      offset: Offset(0, 14),
    ),
    BoxShadow(color: Color(0x0D0F172A), blurRadius: 3, offset: Offset(0, 1)),
  ];

  /// The shorter shadow for small opaque pieces (segments, chips, tiles)
  /// that other screens decorate with `cardShadow`.
  static const _lightCardShadow = [
    BoxShadow(
      color: Color(0x142B5DB8),
      blurRadius: 16,
      spreadRadius: -4,
      offset: Offset(0, 6),
    ),
    BoxShadow(color: Color(0x0A0F172A), blurRadius: 2, offset: Offset(0, 1)),
  ];

  static const _darkCardShadow = [
    BoxShadow(
      color: Color(0x59000000),
      blurRadius: 16,
      spreadRadius: -4,
      offset: Offset(0, 6),
    ),
  ];

  static const _darkShadow = [
    BoxShadow(
      color: Color(0x80000000),
      blurRadius: 44,
      spreadRadius: -12,
      offset: Offset(0, 22),
    ),
    BoxShadow(color: Color(0x40000000), blurRadius: 3, offset: Offset(0, 1)),
  ];

  static VfTokens dark(VfAccentPalette palette) => VfTokens._(
    brightness: Brightness.dark,
    // "Pane" dark: deep charcoal ash with a faint cool aurora.
    background: const Color(0xFF000000),
    surface: const Color(0xFF17191E),
    surface2: const Color(0xFF1C1F25),
    surface3: const Color(0xFF24272E),
    border: const Color(0xFF262A31),
    borderStrong: const Color(0xFF363B44),
    text: const Color(0xFFF4F5F7),
    text2: const Color(0xFFC9CDD4),
    muted: const Color(0xFF9AA0AB),
    faint: const Color(0xFF737A86),
    inputBg: const Color(0x0FFFFFFF),
    inputBorder: const Color(0x1FFFFFFF),
    inputDisabled: const Color(0x08FFFFFF),
    placeholder: const Color(0xFF737A86),
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
    neutralSoft: const Color(0x14FFFFFF),
    neutralStrong: const Color(0xFF6B7280),
    chrome: const Color(0xFF111317),
    chromeLine: const Color(0xFF22252B),
    chromeHover: const Color(0xFF1A1C21),
    chromeCard: const Color(0xE617191E),
    chromeText: const Color(0xFFD1D5DB),
    chromeMuted: const Color(0xFF9AA0AB),
    chromeLabel: const Color(0xFF737A86),
    tabBar: const Color(0xE0181A1F),
    overlay: const Color(0xA6040507),
    cardShadow: _darkCardShadow,
    palette: palette,
    wallpaper: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF0A0A0B), Color(0xFF050505), Color(0xFF000000)],
      stops: [0, .55, 1],
    ),
    // True black with one faint blue light from above.
    wallpaperGlows: [
      const VfGlow(Alignment(0, -1.25), .7, Color(0x1F0A84FF)),
    ],
    glassFill: const Color(0xFF161618),
    glassFillStrong: const Color(0xD91C1C1E),
    glassRowFill: const Color(0xFF161618),
    glassBorder: const Color(0x14FFFFFF),
    glassHighlight: const Color(0x3DFFFFFF),
    glassSheen: const Color(0x0DFFFFFF),
    glassShadow: _darkShadow,
    barFill: const Color(0xE0181A1F),
    sheetFill: const Color(0xF0191B20),
    tabActive: const Color(0x1FFFFFFF),
    blurSigma: 24,
  );

  /// The drawer is a touch deeper than the top bar in dark, as on the web.
  Color get drawer => isDark ? const Color(0xFF0A0B0E) : chrome;
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
  static const radiusGlass = 22.0; // glass cards and panels
  static const radiusSheet = 28.0; // sheets, the drawer, the tab bar
  static const radiusPill = 999.0;

  static const controlH = 48.0; // buttons, tall for touch
  static const inputH = 52.0;
  static const topBarH = 60.0;
  static const tabBarH = 68.0;

  /// The floating tab bar: its height and its inset from the screen edges.
  static const floatingBarH = 64.0;
  static const floatingBarInset = 14.0;

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
  static const bg = Color(0xFF0B0C10);
  static const elev1 = Color(0xFF17191E);
  static const elev2 = Color(0xFF1C1F25);
  static const elev3 = Color(0xFF24272E);
  static const text = Color(0xFFF4F5F7);
  static const line = Color(0xFF262A31);
  static const lineStrong = Color(0xFF363B44);

  // light
  static const lightBg = Color(0xFFEDF3FB);
  static const lightElev1 = Color(0xFFFFFFFF);
  static const lightElev2 = Color(0xFFF6F9FD);
  static const lightElev3 = Color(0xFFECF1F8);
  static const lightText = Color(0xFF0F172A);
  static const lightLine = Color(0xFFE0E7F0);
  static const lightLineStrong = Color(0xFFCBD5E2);

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
  VfTokens get vf => isDark
      ? VfTokens.dark(VfColors.palette)
      : VfTokens.light(VfColors.palette);

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

/// The type scale. Poppins is the bundled face (Inter is not bundled and no
/// dependency carries it); large sizes are tracked tight for the glass look.
class VfType {
  const VfType._();

  static const family = 'Poppins';

  static TextStyle _t(
    double size,
    FontWeight w, {
    double h = 1.45,
    double ls = 0,
  }) => TextStyle(
    fontFamily: family,
    fontSize: size,
    fontWeight: w,
    height: h,
    letterSpacing: ls,
  );

  /// Page title (web h1 on a phone: 26–30px, bold, tight).
  static final pageTitle = _t(26, FontWeight.w700, h: 1.15, ls: -0.5);

  /// The greeting and large page titles: 32–36 on a phone, very tight.
  static final display = _t(34, FontWeight.w700, h: 1.1, ls: -1.2);

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
    final glassRadius = BorderRadius.circular(VfSize.radiusGlass);

    return ThemeData(
      useMaterial3: true,
      brightness: t.brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: t.background,
      canvasColor: t.background,
      dividerColor: t.isDark ? t.glassBorder : t.border,
      dividerTheme: DividerThemeData(
        color: t.isDark ? t.glassBorder : t.border,
        thickness: 1,
        space: 1,
      ),
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
        color: t.glassFill,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: glassRadius,
          side: BorderSide(color: t.glassBorder),
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
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          textStyle: WidgetStatePropertyAll(
            VfType.bodyStrong.copyWith(fontSize: 15),
          ),
          elevation: const WidgetStatePropertyAll(0),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.text,
          backgroundColor: t.glassFillStrong,
          minimumSize: const Size(0, VfSize.controlH),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          side: BorderSide(color: t.isDark ? t.glassBorder : t.borderStrong),
          shape: const StadiumBorder(),
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 13,
        ),
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
        backgroundColor: t.glassFillStrong,
        selectedColor: t.primarySoftStrong,
        side: BorderSide(color: t.isDark ? t.glassBorder : t.borderStrong),
        labelStyle: VfType.small.copyWith(color: t.text2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VfSize.radiusPill),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: t.tabBar,
        surfaceTintColor: Colors.transparent,
        indicatorColor: t.tabActive,
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
      // Sheets and dialogs nobody wrapped in glass are still near-opaque
      // glass: legible over anything, and no blur to pay for.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.sheetFill,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: t.sheetFill,
        modalBarrierColor: t.overlay,
        showDragHandle: true,
        dragHandleColor: t.borderStrong,
        elevation: 0,
        modalElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(VfSize.radiusSheet),
          ),
          side: BorderSide(color: t.glassBorder),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.sheetFill,
        surfaceTintColor: Colors.transparent,
        barrierColor: t.overlay,
        elevation: 0,
        titleTextStyle: VfType.sectionTitle.copyWith(color: t.text),
        contentTextStyle: VfType.body.copyWith(color: t.text2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VfSize.radiusSheet),
          side: BorderSide(color: t.glassBorder),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: t.sheetFill,
        surfaceTintColor: Colors.transparent,
        scrimColor: t.overlay,
        elevation: 0,
        width: 304,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(
            right: Radius.circular(VfSize.radiusSheet),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: t.isDark ? t.surface2 : t.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        textStyle: VfType.small.copyWith(color: t.text, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VfSize.radiusXl),
          side: BorderSide(color: t.isDark ? t.glassBorder : t.border),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (st) =>
                st.contains(WidgetState.selected) ? t.tabActive : t.glassFill,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (st) => st.contains(WidgetState.selected) ? t.primaryText : t.text2,
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: t.isDark ? t.glassBorder : t.border),
          ),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          textStyle: WidgetStatePropertyAll(
            VfType.label.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: t.isDark ? t.surface3 : t.text,
        contentTextStyle: VfType.small.copyWith(
          color: t.isDark ? t.text : Colors.white,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VfSize.radiusXl),
        ),
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
        dividerColor: t.isDark ? t.glassBorder : t.border,
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
