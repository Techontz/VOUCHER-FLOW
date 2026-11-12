import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// The "liquid glass" surface every card, sheet and bar is drawn with: a
/// translucent fill with a faint top sheen, a hairline border that brightens
/// along the top edge, and a soft long shadow painted outside the shape only
/// (so it never muddies the translucent fill).
///
/// [blur] adds a backdrop blur. It is the expensive part on low-end Android,
/// so it is on for bars, sheets and a handful of feature cards, and off for
/// anything repeated in a list: [VouchFlowCard] leaves it off by default.
class VfGlass extends StatelessWidget {
  const VfGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(VfSize.radiusGlass),
    ),
    this.blur = true,
    this.sigma,
    this.fill,
    this.strong = false,
    this.borderColor,
    this.borderWidth = 1,
    this.highlight = true,
    this.shadow = true,
    this.shadows,
    this.padding,
    this.clip = true,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// Blur what lies behind (bars, sheets, a few feature cards only).
  final bool blur;

  /// Blur strength; defaults to the appearance's [VfTokens.blurSigma].
  final double? sigma;

  /// The fill; defaults to [VfTokens.glassFill] or, when [strong],
  /// [VfTokens.glassFillStrong].
  final Color? fill;
  final bool strong;

  /// The hairline; defaults to [VfTokens.glassBorder].
  final Color? borderColor;
  final double borderWidth;

  /// Brighten the top edge of the border ([VfTokens.glassHighlight]).
  final bool highlight;

  /// Paint the soft shadow ([shadows], or [VfTokens.glassShadow]).
  final bool shadow;
  final List<BoxShadow>? shadows;

  final EdgeInsetsGeometry? padding;

  /// Clip the child to the rounded shape (ink, images that reach the edge).
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final base = fill ?? (strong ? t.glassFillStrong : t.glassFill);
    final edge = borderColor ?? t.glassBorder;

    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.alphaBlend(t.glassSheen, base), base],
          stops: const [0, .55],
        ),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );

    if (blur) {
      final s = sigma ?? t.blurSigma;
      body = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: s, sigmaY: s),
          child: body,
        ),
      );
    } else if (clip) {
      body = ClipRRect(borderRadius: borderRadius, child: body);
    }

    return CustomPaint(
      painter: shadow
          ? VfOuterShadowPainter(borderRadius, shadows ?? t.glassShadow)
          : null,
      foregroundPainter: borderWidth <= 0
          ? null
          : VfGlassEdgePainter(
              borderRadius,
              edge,
              highlight ? t.glassHighlight : edge,
              borderWidth,
            ),
      child: body,
    );
  }
}

/// Paints [shadows] for a rounded rectangle, outside the shape only.
class VfOuterShadowPainter extends CustomPainter {
  const VfOuterShadowPainter(this.radius, this.shadows);

  final BorderRadius radius;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    if (shadows.isEmpty) return;
    final rrect = radius.toRRect(Offset.zero & size);
    var reach = 0.0;
    for (final s in shadows) {
      reach = math.max(
        reach,
        s.blurRadius * 2 + s.spreadRadius.abs() + s.offset.distance,
      );
    }
    canvas.save();
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect((Offset.zero & size).inflate(reach + 8))
        ..addRRect(rrect),
    );
    for (final s in shadows) {
      canvas.drawRRect(
        rrect.shift(s.offset).inflate(s.spreadRadius),
        s.toPaint(),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant VfOuterShadowPainter old) =>
      old.radius != radius || !identical(old.shadows, shadows);
}

/// The glass hairline: [top] along the upper edge fading into [color].
class VfGlassEdgePainter extends CustomPainter {
  const VfGlassEdgePainter(this.radius, this.color, this.top, this.width);

  final BorderRadius radius;
  final Color color;
  final Color top;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect).deflate(width / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    if (top == color) {
      paint.color = color;
    } else {
      paint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [top, color, color],
        stops: [0, math.min(.5, 28 / math.max(size.height, 1)), 1],
      ).createShader(rect);
    }
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant VfGlassEdgePainter old) =>
      old.radius != radius ||
      old.color != color ||
      old.top != top ||
      old.width != width;
}

/// The page ground: the appearance's wallpaper gradient with its soft glows
/// (a cool blue/violet aurora in dark, white into sky blue in light). Static
/// and isolated in its own layer, so it costs one paint per appearance.
class VfWallpaper extends StatelessWidget {
  const VfWallpaper({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    // Still, on purpose: the ground is calm and content moves over it.
    final paint = RepaintBoundary(
      child: CustomPaint(
        painter: _WallpaperPainter(t.background, t.wallpaper, t.wallpaperGlows, 0),
        child: const SizedBox.expand(),
      ),
    );
    if (child == null) return paint;
    return Stack(fit: StackFit.expand, children: [paint, child!]);
  }
}

class _WallpaperPainter extends CustomPainter {
  _WallpaperPainter(this.base, this.gradient, this.glows, this.phase);

  final Color base;
  final LinearGradient gradient;
  final List<VfGlow> glows;

  /// 0..1 round the drift cycle.
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = base);
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
    final longest = math.max(size.width, size.height);
    for (var i = 0; i < glows.length; i++) {
      final g = glows[i];
      // Each light circles its own spot, out of step with the others.
      final a = (phase + i / glows.length) * 2 * math.pi;
      final c = g.center.alongSize(size) +
          Offset(math.cos(a) * size.width * .08, math.sin(a) * size.height * .05);
      final r = g.radius * longest;
      final circle = Rect.fromCircle(center: c, radius: r);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [g.color, g.color.withValues(alpha: 0)],
          ).createShader(circle),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WallpaperPainter old) =>
      old.phase != phase ||
      old.base != base ||
      old.gradient != gradient ||
      old.glows.length != glows.length ||
      Iterable.generate(
        glows.length,
      ).any((i) => old.glows[i].color != glows[i].color);
}

/// A solid pill fill: [color] (the primary by default) with a soft top
/// gradient, a faint white rim and a glow in its own colour. Shared by
/// primary buttons, the create button and the dashboard's actions so the
/// accent reads the same everywhere. Pair it with [VfGloss] for the shine.
BoxDecoration vfPrimaryGloss(
  VfTokens t, {
  Color? color,
  BoxShape shape = BoxShape.rectangle,
  BorderRadius? radius,
  bool glow = true,
}) {
  final c = color ?? t.primary;
  return BoxDecoration(
    shape: shape,
    borderRadius: shape == BoxShape.circle
        ? null
        : (radius ?? BorderRadius.circular(VfSize.radiusPill)),
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color.lerp(c, Colors.white, .14)!, c],
    ),
    border: Border.all(
      color: Colors.white.withValues(alpha: t.isDark ? .16 : .22),
    ),
    boxShadow: glow
        ? [
            BoxShadow(
              color: c.withValues(alpha: t.isDark ? .45 : .30),
              blurRadius: 18,
              spreadRadius: -4,
              offset: const Offset(0, 8),
            ),
          ]
        : null,
  );
}

/// The thin white gloss across the top half of a primary pill. Place it in
/// a Stack inside a clipped shape; the clip gives it its corners.
class VfGloss extends StatelessWidget {
  const VfGloss({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: FractionallySizedBox(
      alignment: Alignment.topCenter,
      heightFactor: .52,
      widthFactor: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: .20),
              Colors.white.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    ),
  );
}
