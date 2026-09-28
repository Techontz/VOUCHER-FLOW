import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Strokes drawn on the profile's signature canvas, exported as a PNG on
/// white so the mark reads on paper as well as on screen.
class SignatureCanvasController extends ChangeNotifier {
  final List<List<Offset>> _strokes = [];
  Size _size = Size.zero;

  bool get isEmpty => _strokes.every((s) => s.length < 2);

  void clear() {
    _strokes.clear();
    notifyListeners();
  }

  void _start(Offset p) {
    _strokes.add([p]);
    notifyListeners();
  }

  void _extend(Offset p) {
    if (_strokes.isEmpty) _strokes.add([]);
    _strokes.last.add(p);
    notifyListeners();
  }

  /// Rasterised at 3× for a crisp mark on the printed voucher.
  Future<Uint8List?> toPng() async {
    if (isEmpty || _size == Size.zero) return null;
    const scale = 3.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale);
    canvas.drawRect(Offset.zero & _size, Paint()..color = Colors.white);
    _paint(canvas, _strokes);
    final image = await recorder.endRecording().toImage(
      (_size.width * scale).round(),
      (_size.height * scale).round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }
}

void _paint(Canvas canvas, List<List<Offset>> strokes) {
  final paint = Paint()
    ..color = const Color(0xFF201E1D)
    ..strokeWidth = 2.2
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  for (final stroke in strokes) {
    if (stroke.length < 2) continue;
    final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
    for (final p in stroke.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint);
  }
}

/// The web's `.vf-sigpad-canvas`: a white pad drawn on by finger or pen.
/// [onEnd] fires when a stroke finishes (the web commits on pointer-up).
class SignatureCanvas extends StatelessWidget {
  const SignatureCanvas({
    super.key,
    required this.controller,
    this.onEnd,
    this.height = 180,
    this.semanticLabel,
  });

  final SignatureCanvasController controller;
  final VoidCallback? onEnd;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return LayoutBuilder(
      builder: (context, box) {
        controller._size = Size(box.maxWidth, height);
        return Semantics(
          label: semanticLabel,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(VfSize.radiusL),
              border: Border.all(color: t.borderStrong),
            ),
            clipBehavior: Clip.antiAlias,
            // Claims the pointer at once, so a stroke is never taken by the
            // page's scroll.
            child: RawGestureDetector(
              behavior: HitTestBehavior.opaque,
              gestures: {
                _ImmediatePan:
                    GestureRecognizerFactoryWithHandlers<_ImmediatePan>(
                      _ImmediatePan.new,
                      (r) => r
                        ..dragStartBehavior = DragStartBehavior.down
                        ..onStart = ((d) => controller._start(d.localPosition))
                        ..onUpdate = ((d) =>
                            controller._extend(d.localPosition))
                        ..onEnd = ((_) => onEnd?.call()),
                    ),
              },
              child: AnimatedBuilder(
                animation: controller,
                builder: (_, _) => CustomPaint(
                  painter: _Painter(controller._strokes),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ImmediatePan extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _Painter extends CustomPainter {
  const _Painter(this.strokes);
  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) => _paint(canvas, strokes);

  @override
  bool shouldRepaint(covariant _Painter oldDelegate) => true;
}
