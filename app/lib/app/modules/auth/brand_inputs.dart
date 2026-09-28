import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/services/auth_repository.dart';
import '../../widgets/vf/vf.dart';

final _hex = RegExp(r'^#[0-9a-fA-F]{6}$');

bool isHexColour(String value) => _hex.hasMatch(value);

Color? colourFromHex(String value) => isHexColour(value)
    ? Color(int.parse('FF${value.substring(1)}', radix: 16))
    : null;

/// Why a picked logo was refused, or null when it is accepted.
enum LogoProblem { type, size }

/// Opens the gallery for a company logo and checks it as the web does:
/// PNG, JPG or WEBP, at most 2 MB. The original file is kept (no re-encode),
/// so a transparent PNG stays transparent.
Future<(PickedLogo?, LogoProblem?)> pickCompanyLogo() async {
  final file = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (file == null) return (null, null);

  final name = file.name.isEmpty ? file.path.split('/').last : file.name;
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  final mime = switch (file.mimeType ?? '') {
    'image/png' || 'image/jpeg' || 'image/webp' => file.mimeType!,
    _ => switch (ext) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      _ => '',
    },
  };
  if (mime.isEmpty) return (null, LogoProblem.type);

  final bytes = await file.readAsBytes();
  if (bytes.length > 2 * 1024 * 1024) return (null, LogoProblem.size);
  return (PickedLogo(bytes: bytes, name: name, mime: mime), null);
}

/// Colours offered in the picker sheet. Any other colour can be typed.
const _presets = [
  '#2563EB',
  '#1D4ED8',
  '#0B1D3A',
  '#0088B0',
  '#0D9488',
  '#047857',
  '#16A34A',
  '#65A30D',
  '#CA8A04',
  '#EA580C',
  '#DC2626',
  '#D6006C',
  '#BE123C',
  '#7C3AED',
  '#6D28D9',
  '#8A4B12',
  '#475569',
  '#111827',
];

/// The web's colour field: a swatch (the native colour input) beside the hex
/// value. Tapping the swatch opens a palette; the hex can also be typed.
class ColourField extends StatelessWidget {
  const ColourField({
    super.key,
    required this.label,
    required this.controller,
    required this.onChanged,
    this.error,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? error;

  Future<void> _openPalette(BuildContext context) async {
    final t = context.vf;
    final chosen = await showVouchFlowBottomSheet<String>(
      context,
      title: 'auth.rg.pickColour'.tr,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final hex in _presets)
              Builder(
                builder: (ctx) {
                  final on = controller.text.toUpperCase() == hex;
                  return Semantics(
                    button: true,
                    selected: on,
                    label: hex,
                    child: InkWell(
                      onTap: () => Navigator.of(ctx).pop(hex),
                      borderRadius: BorderRadius.circular(VfSize.radiusL),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: colourFromHex(hex),
                          borderRadius: BorderRadius.circular(VfSize.radiusL),
                          border: Border.all(
                            color: on ? t.text : t.border,
                            width: on ? 2.5 : 1,
                          ),
                        ),
                        child: on
                            ? const Icon(
                                PhosphorIconsBold.check,
                                color: Colors.white,
                                size: 18,
                              )
                            : null,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
    if (chosen != null) {
      controller.text = chosen;
      onChanged(chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return VouchFlowField(
      label: label,
      error: error,
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'auth.rg.pickColour'.tr,
            child: InkWell(
              onTap: () => _openPalette(context),
              borderRadius: BorderRadius.circular(VfSize.radiusL),
              child: Container(
                width: VfSize.inputH,
                height: VfSize.inputH,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: t.surface,
                  border: Border.all(color: t.borderStrong),
                  borderRadius: BorderRadius.circular(VfSize.radiusL),
                ),
                child: ValueListenableBuilder(
                  valueListenable: controller,
                  builder: (_, value, _) => DecoratedBox(
                    decoration: BoxDecoration(
                      color: colourFromHex(value.text) ?? Colors.black,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              maxLength: 7,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
              ],
              onChanged: (v) {
                var next = v.trim().toUpperCase();
                if (!next.startsWith('#')) {
                  next = '#${next.replaceAll('#', '')}';
                }
                if (next != controller.text) {
                  controller.value = TextEditingValue(
                    text: next,
                    selection: TextSelection.collapsed(offset: next.length),
                  );
                }
                onChanged(next);
              },
              style: VfType.body.copyWith(
                color: t.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: t.inputBg,
                errorText: error == null ? null : '',
                errorStyle: const TextStyle(height: 0, fontSize: 0),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
