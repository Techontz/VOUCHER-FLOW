import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Web builds (development screenshots, a browser preview): the document in
/// an iframe, laid out at A4 width and scaled to the box — the website's own
/// VoucherDocument frame.
Widget platformDocumentFrame({
  Key? key,
  required String html,
  required double scale,
  required bool interactive,
  required bool fill,
}) => _DocumentFrame(key: key, html: html, scale: scale, interactive: interactive, fill: fill);

/// One iframe for the life of the view: a new document or size is applied to
/// the same element. Replacing the platform view on every change blanks the
/// whole Flutter web canvas while a route is animating.
class _DocumentFrame extends StatefulWidget {
  const _DocumentFrame({
    super.key,
    required this.html,
    required this.scale,
    required this.interactive,
    required this.fill,
  });

  final String html;
  final double scale;
  final bool interactive;
  final bool fill;

  @override
  State<_DocumentFrame> createState() => _DocumentFrameState();
}

class _DocumentFrameState extends State<_DocumentFrame> {
  web.HTMLIFrameElement? _frame;
  String? _shown;

  void _apply() {
    final frame = _frame;
    if (frame == null) return;
    if (_shown != widget.html) {
      _shown = widget.html;
      frame.srcdoc = widget.html.toJS;
    }
    frame.style
      ..border = '0'
      ..background = '#fff'
      ..pointerEvents = widget.interactive ? 'auto' : 'none';
    if (widget.fill) {
      frame.style
        ..width = '100%'
        ..height = '100%'
        ..transform = '';
    } else {
      frame.style
        ..width = '794px'
        ..height = '${(100 / widget.scale).toStringAsFixed(2)}%'
        ..transformOrigin = '0 0'
        ..transform = 'scale(${widget.scale})';
    }
  }

  @override
  void didUpdateWidget(covariant _DocumentFrame old) {
    super.didUpdateWidget(old);
    _apply();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
    tagName: 'iframe',
    isVisible: true,
    onElementCreated: (Object el) {
      _frame = el as web.HTMLIFrameElement;
      _apply();
    },
  );
}
