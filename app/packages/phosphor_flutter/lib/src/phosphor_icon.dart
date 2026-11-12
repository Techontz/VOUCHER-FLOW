library phosphor_flutter;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class PhosphorIcon extends Icon {
  const PhosphorIcon(
    IconData icon, {
    Key? key,
    double? size,
    double? fill,
    double? weight,
    double? grade,
    double? opticalSize,
    Color? color,
    List<Shadow>? shadows,
    String? semanticLabel,
    TextDirection? textDirection,
    this.duotoneSecondaryOpacity = 0.20,
    this.duotoneSecondaryColor,
  }) : super(
          icon,
          color: color,
          fill: fill,
          grade: grade,
          key: key,
          opticalSize: opticalSize,
          semanticLabel: semanticLabel,
          shadows: shadows,
          size: size,
          textDirection: textDirection,
          weight: weight,
        );

  final double duotoneSecondaryOpacity;
  final Color? duotoneSecondaryColor;

  // Patched: with IconData final, every icon (duotone included) draws as a
  // single glyph, exactly like Flutter's own Icon.
  @override
  Widget build(BuildContext context) => super.build(context);
}
