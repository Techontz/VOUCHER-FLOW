import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/theme.dart';

/// Captures a signature by finger or stylus and exports it as PNG bytes.
///
/// Drawn on white so the mark reads on paper as well as on screen — the same
/// image is embedded in the generated A4 voucher.
class SignaturePad extends StatefulWidget {
  const SignaturePad({super.key, required this.controller, this.height = 190});

  final SignaturePadController controller;
  final double height;

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class SignaturePadController extends ChangeNotifier {
  final List<List<Offset>> _strokes = [];
  Size _size = Size.zero;

  bool get isEmpty => _strokes.every((stroke) => stroke.length < 2);
  bool get isNotEmpty => !isEmpty;

  void clear() {
    _strokes.clear();
    notifyListeners();
  }

  void _start(Offset point) {
    _strokes.add([point]);
    notifyListeners();
  }

  void _extend(Offset point) {
    if (_strokes.isEmpty) _strokes.add([]);
    _strokes.last.add(point);
    notifyListeners();
  }

  /// Rasterises the strokes at 3× for a crisp mark on the printed voucher.
  Future<Uint8List?> toPng() async {
    if (isEmpty || _size == Size.zero) return null;

    const scale = 3.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.scale(scale);
    canvas.drawRect(Offset.zero & _size, Paint()..color = Colors.white);
    _paintStrokes(canvas, _strokes, Colors.black);

    final image = await recorder.endRecording().toImage(
      (_size.width * scale).round(),
      (_size.height * scale).round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }
}

void _paintStrokes(Canvas canvas, List<List<Offset>> strokes, Color colour) {
  final paint = Paint()
    ..color = colour
    ..strokeWidth = 2.6
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

  for (final stroke in strokes) {
    if (stroke.length < 2) continue;
    final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
    for (final point in stroke.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }
}

class _SignaturePadState extends State<SignaturePad> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            widget.controller._size = Size(constraints.maxWidth, widget.height);
            return Container(
              height: widget.height,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: VfColors.lineStrong),
                borderRadius: BorderRadius.circular(2),
              ),
              child: GestureDetector(
                onPanStart: (d) => widget.controller._start(d.localPosition),
                onPanUpdate: (d) => widget.controller._extend(d.localPosition),
                child: AnimatedBuilder(
                  animation: widget.controller,
                  builder: (_, _) => CustomPaint(
                    painter: _SignaturePainter(widget.controller._strokes),
                    size: Size.infinite,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                'sign.hint'.tr,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            TextButton.icon(
              onPressed: widget.controller.clear,
              icon: const Icon(Icons.backspace_outlined, size: 16),
              label: Text('action.clear'.tr),
            ),
          ],
        ),
      ],
    );
  }
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter(this.strokes);

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) =>
      _paintStrokes(canvas, strokes, const Color(0xFF201E1D));

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
