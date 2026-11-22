import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Whether this process is a `flutter test` run. Widget tests settle by
/// pumping until no frame is scheduled, which an endless animation never
/// allows, so the loader holds still there.
final bool vfUnderTest =
    const bool.fromEnvironment('FLUTTER_TEST') ||
    (!kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true');

/// The web's loader (styles/refined.css `.vf-loader`): a ring in the accent
/// colour whose two halves sweep round on the same 2s ease, one half a
/// beat (1.5s) behind the other, so the ring opens and closes as it turns.
///
/// It holds a still frame when the platform asks for reduced motion
/// (`MediaQuery.disableAnimations`) and under widget tests.
class VfLoader extends StatefulWidget {
  const VfLoader({super.key, this.size = 45, this.color, this.label});

  /// The ring's outer diameter: the web's 5em at 9px.
  final double size;

  /// Defaults to the company's primary colour.
  final Color? color;

  /// What is loading, for screen readers.
  final String? label;

  @override
  State<VfLoader> createState() => _VfLoaderState();
}

class _VfLoaderState extends State<VfLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = vfUnderTest || MediaQuery.maybeDisableAnimationsOf(context) == true;
    if (still) {
      _c.stop();
      // A frame where the ring is visibly open, so it still reads as a loader.
      _c.value = .3;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colour = widget.color ?? context.vf.primary;
    return Semantics(
      label: widget.label ?? MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
      child: SizedBox.square(
        dimension: widget.size,
        child: RepaintBoundary(
          child: CustomPaint(painter: VfRingPainter(_c, colour)),
        ),
      ),
    );
  }
}

/// Paints the ring at the controller's point in the cycle.
///
/// The CSS draws a ring in the page colour and two accent half-discs that
/// rotate over it. Here the same picture is drawn directly: two half-rings
/// in the accent colour, each starting where its half-disc has turned to.
/// While both have turned equally they meet as a whole ring; while one
/// lags, they overlap on one side and leave a gap on the other.
class VfRingPainter extends CustomPainter {
  VfRingPainter(this.progress, this.color) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;

  static const _ease = Cubic(.25, .1, .25, 1); // CSS `ease`

  @override
  void paint(Canvas canvas, Size size) {
    final v = progress.value;
    // `::after` starts at once; `::before` 1.5s into the 2s cycle.
    final lead = _ease.transform(v) * 2 * math.pi;
    final lagT = (v - .75) % 1.0;
    final lag = _ease.transform(lagT) * 2 * math.pi;

    final stroke = size.width / 5; // the 1em ring of a 5em loader
    final rect = Offset.zero & size;
    final ring = rect.deflate(stroke / 2);
    final paint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color;

    // Right half (`::after`) spans -90°..90°, left half (`::before`)
    // 90°..270°, each turned by its own rotation.
    canvas.drawArc(ring, -math.pi / 2 + lead, math.pi, false, paint);
    canvas.drawArc(ring, math.pi / 2 + lag, math.pi, false, paint);
  }

  @override
  bool shouldRepaint(VfRingPainter old) => old.color != color;
}

/// The loader centred in the space it is given: a whole screen while a page
/// opens, or a section while its rows arrive (the web's `.vf-loader-inline`).
class VfLoadingView extends StatelessWidget {
  const VfLoadingView({super.key, this.label, this.inline = false, this.size});

  final String? label;

  /// A section's loader: padded, not expanded to fill.
  final bool inline;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final loader = VfLoader(size: size ?? (inline ? 36 : 45), label: label);
    if (inline) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Center(child: loader),
      );
    }
    return Center(child: loader);
  }
}
