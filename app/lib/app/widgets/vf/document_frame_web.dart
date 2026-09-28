import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Web builds (development screenshots, a browser preview): the document in
/// an iframe, laid out at A4 width and scaled to the box — the website's own
/// VoucherDocument frame.
Widget platformDocumentFrame({Key? key, required String html, required double scale, required bool interactive, required bool fill}) {
  return HtmlElementView.fromTagName(
    key: key,
    tagName: 'iframe',
    isVisible: true,
    onElementCreated: (Object el) {
      final frame = el as web.HTMLIFrameElement;
      frame.srcdoc = html.toJS;
      frame.style
        ..border = '0'
        ..background = '#fff'
        ..pointerEvents = interactive ? 'auto' : 'none';
      if (fill) {
        frame.style
          ..width = '100%'
          ..height = '100%';
      } else {
        frame.style
          ..width = '794px'
          ..height = '${(100 / scale).toStringAsFixed(2)}%'
          ..transformOrigin = '0 0'
          ..transform = 'scale($scale)';
      }
    },
  );
}
