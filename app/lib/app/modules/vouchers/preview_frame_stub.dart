import 'package:flutter/widgets.dart';

/// Native builds render the preview with VouchFlowDocumentView; this is
/// never called off the web.
Widget previewFrame({required String html, required double width}) => const SizedBox.shrink();
