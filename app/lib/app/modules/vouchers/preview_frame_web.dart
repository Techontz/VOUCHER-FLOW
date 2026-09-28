import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../../widgets/vf/documents.dart' show kA4Height, kA4Width;

/// Web builds only: the live preview in one iframe whose document is swapped
/// in place as the draft changes, rather than a new frame per keystroke.
Widget previewFrame({required String html, required double width}) => _PreviewFrame(html: html, width: width);

class _PreviewFrame extends StatefulWidget {
  const _PreviewFrame({required this.html, required this.width});

  final String html;
  final double width;

  @override
  State<_PreviewFrame> createState() => _PreviewFrameState();
}

class _PreviewFrameState extends State<_PreviewFrame> {
  web.HTMLIFrameElement? _frame;

  void _apply() {
    final frame = _frame;
    if (frame == null) return;
    final scale = widget.width / kA4Width;
    frame.srcdoc = widget.html.toJS;
    frame.style
      ..border = '0'
      ..background = '#fff'
      ..pointerEvents = 'none'
      ..width = '${kA4Width}px'
      ..height = '${kA4Height}px'
      ..transformOrigin = '0 0'
      ..transform = 'scale($scale)';
  }

  @override
  void didUpdateWidget(covariant _PreviewFrame old) {
    super.didUpdateWidget(old);
    if (old.html != widget.html || old.width != widget.width) _apply();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    height: kA4Height * widget.width / kA4Width,
    child: HtmlElementView.fromTagName(
      tagName: 'iframe',
      isVisible: true,
      onElementCreated: (Object el) {
        _frame = el as web.HTMLIFrameElement;
        _apply();
      },
    ),
  );
}
