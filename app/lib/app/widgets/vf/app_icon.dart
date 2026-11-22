import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/*
 * App icons, drawn as the web draws them (web/components/app-icon.tsx): a
 * white tile with a soft shadow, holding a flat illustration of two or
 * three overlapping shapes on a 48 × 48 grid. The overlapping layer
 * multiplies on a light tile, so where two colours cross a third, deeper
 * one appears; on the dark tile it is painted plainly, as the web's
 * `--app-blend: normal` does. One palette for every app keeps the set
 * coherent.
 */

/// The shared palette (the web's `C`).
abstract class VfIconPalette {
  static const blue = Color(0xFF3D7BFA);
  static const sky = Color(0xFF5BC6F2);
  static const navy = Color(0xFF24386E);
  static const coral = Color(0xFFFF7759);
  static const amber = Color(0xFFFFBE3D);
  static const mint = Color(0xFF2CC4A2);
  static const rose = Color(0xFFF0628C);
  static const violet = Color(0xFF7B5CD6);
}

/// An app's icon, the same wherever the app is named (launcher, switcher,
/// menu), so people learn to find an app by its picture.
///
/// [app] is an area key ('vouchflow', 'inventory' …). [badge] adds the red
/// count; [dimmed] draws an app the company has not switched on.
class VfAppIcon extends StatelessWidget {
  const VfAppIcon({
    super.key,
    required this.app,
    this.size = 56,
    this.badge,
    this.dimmed = false,
    this.shadow = true,
  });

  final String app;
  final double size;
  final int? badge;
  final bool dimmed;
  final bool shadow;

  static const _darkTile = Color(0xFF2A2A2E);

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final dark = t.isDark;
    final radius = BorderRadius.circular(size * .2);

    Widget tile = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: dark ? _darkTile : Colors.white,
        borderRadius: radius,
        border: Border.all(
          color: dark ? const Color(0x0FFFFFFF) : const Color(0x0A101828),
        ),
        boxShadow: !shadow
            ? null
            : dark
            ? const [
                BoxShadow(
                  color: Color(0xCC000000),
                  blurRadius: 18,
                  spreadRadius: -8,
                  offset: Offset(0, 6),
                ),
              ]
            : const [
                // The web's --rf-shadow-far: a crisp contact shadow and a
                // soft blue glow that falls far.
                BoxShadow(color: Color(0x0D101828), blurRadius: 2, offset: Offset(0, 1)),
                BoxShadow(color: Color(0x382563EB), blurRadius: 32, spreadRadius: -14, offset: Offset(0, 14)),
                BoxShadow(color: Color(0x4D3B82F6), blurRadius: 72, spreadRadius: -36, offset: Offset(0, 36)),
              ],
      ),
      alignment: Alignment.center,
      child: SizedBox.square(
        dimension: size * .68,
        child: CustomPaint(painter: VfAppGlyphPainter(app, multiply: !dark)),
      ),
    );

    if (dimmed) {
      tile = Opacity(
        opacity: .45,
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            .2126, .7152, .0722, 0, 0, //
            .2126, .7152, .0722, 0, 0,
            .2126, .7152, .0722, 0, 0,
            0, 0, 0, 1, 0,
          ]),
          child: tile,
        ),
      );
    }

    final count = badge;
    if (count == null || count <= 0) return tile;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        tile,
        Positioned(
          top: -6,
          right: -6,
          child: Container(
            constraints: const BoxConstraints(minWidth: 22),
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFF3B30),
              borderRadius: BorderRadius.circular(11),
              // A ring in the page colour cuts the badge out of the tile.
              border: Border.all(
                color: dark ? Colors.black : Colors.white,
                width: 2.5,
                strokeAlign: BorderSide.strokeAlignOutside,
              ),
            ),
            child: Text(
              count > 99 ? '99+' : '$count',
              style: const TextStyle(
                fontFamily: VfType.family,
                fontSize: 12,
                height: 1,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Paints one app's illustration into its box, on the web's 48 × 48 grid.
class VfAppGlyphPainter extends CustomPainter {
  VfAppGlyphPainter(this.app, {this.multiply = true});

  final String app;

  /// Multiply the overlapping layers (light tile) or paint them plainly.
  final bool multiply;

  late Canvas _c;

  @override
  void paint(Canvas canvas, Size size) {
    _c = canvas;
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);
    switch (app) {
      case 'vouchflow':
        _rect(10, 6, 23, 31, 4, VfIconPalette.blue);
        _rect(14.5, 12, 14, 3, 1.5, Colors.white, opacity: .9);
        _rect(14.5, 18, 10, 3, 1.5, Colors.white, opacity: .9);
        _circle(32, 33, 9.5, VfIconPalette.amber, m: true);
        _stroke([const Offset(27.5, 33.2), const Offset(30.7, 36.4), const Offset(36.7, 29.8)], VfIconPalette.navy, 3);
      case 'inventory':
        _poly([24, 7, 41, 15.5, 24, 24, 7, 15.5], VfIconPalette.amber);
        _poly([7, 15.5, 24, 24, 24, 42, 7, 33.5], VfIconPalette.coral);
        _poly([41, 15.5, 41, 33.5, 24, 42, 24, 24], VfIconPalette.navy);
      case 'sales':
        _fill(
          Path()
            ..moveTo(9, 11.5)
            ..arcToPoint(const Offset(11.5, 9), radius: const Radius.circular(2.5))
            ..lineTo(24, 9)
            ..lineTo(39, 24)
            ..lineTo(24, 39)
            ..lineTo(9, 24)
            ..close(),
          VfIconPalette.mint,
        );
        _circle(16.5, 16.5, 3.2, Colors.white);
        _circle(33, 33, 9, VfIconPalette.coral, m: true);
      case 'dispatch':
        _rect(5, 11, 25, 20, 3.5, VfIconPalette.sky);
        _fill(
          Path()
            ..moveTo(27, 17)
            ..lineTo(35.5, 17)
            ..arcToPoint(const Offset(38.1, 18.5), radius: const Radius.circular(3))
            ..lineTo(41.5, 24.5)
            ..lineTo(41.5, 31)
            ..lineTo(27, 31)
            ..close(),
          VfIconPalette.blue,
          m: true,
        );
        _rect(31, 19.5, 5.5, 4.5, 1.2, Colors.white, opacity: .9);
        _circle(14, 33.5, 5, VfIconPalette.navy);
        _circle(35, 33.5, 5, VfIconPalette.navy);
        _circle(14, 33.5, 1.8, Colors.white);
        _circle(35, 33.5, 1.8, Colors.white);
      case 'procurement':
        _rect(13, 5, 9, 12, 2, VfIconPalette.amber);
        _rect(23, 3, 9, 14, 2, VfIconPalette.mint);
        _fill(
          Path()
            ..moveTo(7, 13)
            ..lineTo(41, 13)
            ..lineTo(36.8, 30.2)
            ..arcToPoint(const Offset(33.9, 32.5), radius: const Radius.circular(3))
            ..lineTo(14.2, 32.5)
            ..arcToPoint(const Offset(11.3, 30.2), radius: const Radius.circular(3))
            ..close(),
          VfIconPalette.coral,
          m: true,
        );
        _circle(16, 39, 3.6, VfIconPalette.navy);
        _circle(32, 39, 3.6, VfIconPalette.navy);
      case 'finance':
        _circle(18, 28.5, 12.5, VfIconPalette.amber);
        _circle(30, 19.5, 12.5, VfIconPalette.violet, m: true);
        _stroke([
          const Offset(21.5, 25.5),
          const Offset(26.5, 20.5),
          const Offset(30.5, 23.5),
          const Offset(37, 16),
        ], Colors.white, 3);
      case 'assets':
        _rect(8, 15, 17, 27, 2.5, VfIconPalette.navy);
        _rect(22, 6, 18, 36, 2.5, VfIconPalette.sky, m: true);
        for (final y in [12.0, 18.5, 25.0]) {
          for (final x in [27.0, 33.5]) {
            _rect(x, y, 3.5, 3.5, .8, Colors.white, opacity: .9);
          }
        }
        _rect(13, 33, 7, 9, 1.5, VfIconPalette.amber);
      case 'production':
        _teeth(20, 27, 11.5, 5, 6, VfIconPalette.mint, 8);
        _circle(20, 27, 11.5, VfIconPalette.mint);
        _circle(20, 27, 4.5, Colors.white);
        _teeth(33, 15, 7.5, 3.6, 4.5, VfIconPalette.coral, 6);
        _circle(33, 15, 7.5, VfIconPalette.coral, m: true);
        _circle(33, 15, 2.6, Colors.white);
      case 'fleet':
        _strokePath(
          Path()
            ..moveTo(9, 39)
            ..cubicTo(17, 33, 13, 24, 24, 22)
            ..cubicTo(35, 20, 32, 10, 39, 8),
          VfIconPalette.sky,
          6,
        );
        _circle(9, 39, 4.2, VfIconPalette.navy);
        _fill(
          Path()
            ..moveTo(30, 4.5)
            ..arcToPoint(const Offset(39, 13.5), radius: const Radius.circular(9))
            ..cubicTo(39, 20.3, 30, 29, 30, 29)
            ..cubicTo(30, 29, 21, 20.3, 21, 13.5)
            ..arcToPoint(const Offset(30, 4.5), radius: const Radius.circular(9))
            ..close(),
          VfIconPalette.coral,
          m: true,
        );
        _circle(30, 13.5, 3.3, Colors.white);
      case 'hr':
        _circle(31, 14, 6.5, VfIconPalette.sky);
        _rect(21, 22.5, 20, 15, 7.5, VfIconPalette.sky);
        _circle(18.5, 17.5, 7.5, VfIconPalette.rose, m: true);
        _rect(7, 27, 23, 15, 7.5, VfIconPalette.amber, m: true);
      case 'crm':
        _fill(
          Path()
            ..moveTo(8, 10.5)
            ..arcToPoint(const Offset(10.5, 8), radius: const Radius.circular(2.5))
            ..lineTo(37.5, 8)
            ..arcToPoint(const Offset(39.4, 12.1), radius: const Radius.circular(2.5))
            ..lineTo(28.5, 25)
            ..lineTo(28.5, 37.6)
            ..arcToPoint(const Offset(27.4, 39.4), radius: const Radius.circular(2))
            ..lineTo(22.4, 41.9)
            ..arcToPoint(const Offset(19.5, 40.1), radius: const Radius.circular(2))
            ..lineTo(19.5, 25)
            ..lineTo(8.6, 12.1)
            ..arcToPoint(const Offset(8, 10.5), radius: const Radius.circular(2.5))
            ..close(),
          VfIconPalette.mint,
        );
        _circle(34, 33, 8.5, VfIconPalette.violet, m: true);
      case 'files':
        _fill(
          Path()
            ..moveTo(6, 12.5)
            ..arcToPoint(const Offset(9.5, 9), radius: const Radius.circular(3.5))
            ..lineTo(18.1, 9)
            ..arcToPoint(const Offset(20.2, 9.9), radius: const Radius.circular(3))
            ..lineTo(23.5, 13)
            ..lineTo(38.5, 13)
            ..arcToPoint(const Offset(42, 16.5), radius: const Radius.circular(3.5))
            ..lineTo(42, 36)
            ..arcToPoint(const Offset(38.5, 39.5), radius: const Radius.circular(3.5))
            ..lineTo(9.5, 39.5)
            ..arcToPoint(const Offset(6, 36), radius: const Radius.circular(3.5))
            ..close(),
          VfIconPalette.amber,
        );
        _rect(13, 7, 20, 18, 2.5, Colors.white, opacity: .95);
        _fill(
          Path()
            ..moveTo(6, 21)
            ..lineTo(42, 21)
            ..lineTo(42, 36)
            ..arcToPoint(const Offset(38.5, 39.5), radius: const Radius.circular(3.5))
            ..lineTo(9.5, 39.5)
            ..arcToPoint(const Offset(6, 36), radius: const Radius.circular(3.5))
            ..close(),
          VfIconPalette.coral,
          m: true,
        );
      case 'settings':
        for (final y in [13.0, 23.0, 33.0]) {
          _rect(7, y, 34, 4, 2, VfIconPalette.navy, opacity: .22);
        }
        _circle(16, 15, 5.5, VfIconPalette.blue);
        _circle(32, 25, 5.5, VfIconPalette.mint);
        _circle(21, 35, 5.5, VfIconPalette.coral);
      case 'platform':
        _circle(24, 24, 16, VfIconPalette.sky);
        _oval(19.5, 19, 7.5, 5, VfIconPalette.mint, m: true);
        _oval(31, 31, 6, 4.2, VfIconPalette.mint, m: true);
        canvas.save();
        canvas.translate(24, 24);
        canvas.rotate(-22 * math.pi / 180);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: 42, height: 14),
          Paint()
            ..isAntiAlias = true
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.6
            ..color = VfIconPalette.navy,
        );
        canvas.restore();
    }
    canvas.restore();
  }

  Paint _paint(Color color, {bool m = false, double opacity = 1}) => Paint()
    ..isAntiAlias = true
    ..color = color.withValues(alpha: color.a * opacity)
    ..blendMode = m && multiply ? BlendMode.multiply : BlendMode.srcOver;

  void _rect(double x, double y, double w, double h, double r, Color c, {bool m = false, double opacity = 1}) =>
      _c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)),
        _paint(c, m: m, opacity: opacity),
      );

  void _circle(double cx, double cy, double r, Color c, {bool m = false}) =>
      _c.drawCircle(Offset(cx, cy), r, _paint(c, m: m));

  void _oval(double cx, double cy, double rx, double ry, Color c, {bool m = false}) =>
      _c.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2), _paint(c, m: m));

  void _fill(Path p, Color c, {bool m = false}) => _c.drawPath(p, _paint(c, m: m));

  void _poly(List<double> xy, Color c) {
    final p = Path()..moveTo(xy[0], xy[1]);
    for (var i = 2; i < xy.length; i += 2) {
      p.lineTo(xy[i], xy[i + 1]);
    }
    _c.drawPath(p..close(), _paint(c));
  }

  void _strokePath(Path p, Color c, double width) => _c.drawPath(
    p,
    _paint(c)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round,
  );

  void _stroke(List<Offset> points, Color c, double width) {
    final p = Path()..moveTo(points.first.dx, points.first.dy);
    for (final o in points.skip(1)) {
      p.lineTo(o.dx, o.dy);
    }
    _strokePath(p, c, width);
  }

  /// A gear's teeth: [n] small rounded bars round (cx, cy), the web's
  /// `gearTeeth`.
  void _teeth(double cx, double cy, double r, double w, double h, Color c, int n) {
    for (var i = 0; i < n; i++) {
      _c.save();
      _c.translate(cx, cy);
      _c.rotate(2 * math.pi / n * i);
      _c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(-w / 2, -r - h / 2, w, h), const Radius.circular(1.2)),
        _paint(c),
      );
      _c.restore();
    }
  }

  @override
  bool shouldRepaint(VfAppGlyphPainter old) => old.app != app || old.multiply != multiply;
}
