import 'package:flutter/widgets.dart';

/// Native builds never reach this: they use the platform web view.
Widget platformDocumentFrame({Key? key, required String html, required double scale, required bool interactive, required bool fill}) =>
    const SizedBox.shrink();
