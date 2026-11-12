library phosphor_flutter;

import 'package:flutter/widgets.dart';

// Patched for Flutter 3.47, where IconData is final and cannot be extended:
// every Phosphor icon is a plain IconData on the Phosphor fonts. The duotone
// style keeps its primary layer.
typedef PhosphorIconData = IconData;
typedef PhosphorFlatIconData = IconData;
typedef PhosphorDuotoneIconData = IconData;
