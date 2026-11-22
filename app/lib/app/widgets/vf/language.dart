import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';

/// The languages VouchFlow speaks, each named in itself.
const vfLanguages = [('en', 'English'), ('sw', 'Kiswahili')];

/// A language's own name ("English", "Kiswahili").
String vfLanguageName(String code) =>
    vfLanguages.firstWhere((l) => l.$1 == code, orElse: () => vfLanguages.first).$2;

/// Opens the language menu under [anchor] (the widget that was tapped) and
/// returns the code chosen, or null when it was dismissed (a tap outside,
/// Back, or Escape). The current language carries a check.
Future<String?> showVfLanguageMenu(BuildContext anchor, {required String value}) {
  final t = anchor.vf;
  final box = anchor.findRenderObject()! as RenderBox;
  final overlay = Navigator.of(anchor).overlay!.context.findRenderObject()! as RenderBox;
  final rect = RelativeRect.fromRect(
    Rect.fromPoints(
      box.localToGlobal(Offset(0, box.size.height + 6), ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    ),
    Offset.zero & overlay.size,
  );
  return showMenu<String>(
    context: anchor,
    position: rect,
    color: t.isDark ? t.surface2 : t.surface,
    elevation: 6,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(VfSize.radiusL),
      side: BorderSide(color: t.isDark ? t.glassBorder : t.border),
    ),
    constraints: const BoxConstraints(minWidth: 188),
    items: [
      for (final (code, name) in vfLanguages)
        PopupMenuItem<String>(
          value: code,
          height: 48,
          child: Semantics(
            selected: code == value,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: VfType.body.copyWith(
                      color: t.text,
                      fontWeight: code == value ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 18,
                  child: code == value ? Icon(PhosphorIconsBold.check, size: 17, color: t.primary) : null,
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

/// The language switch everywhere in the app: a compact pill with a globe,
/// the current language's name and a chevron, opening [showVfLanguageMenu].
/// [onDark] draws it for the navy hero of the sign-in screen.
class VfLanguagePicker extends StatelessWidget {
  const VfLanguagePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.onDark = false,
    this.tooltip,
  });

  /// The current language code ('en' or 'sw').
  final String value;
  final ValueChanged<String> onChanged;
  final bool onDark;

  /// What a screen reader says the control is ("Language").
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final fg = onDark ? Colors.white : t.text;
    final soft = onDark ? Colors.white.withValues(alpha: .75) : t.muted;
    return Semantics(
      button: true,
      label: [?tooltip, vfLanguageName(value)].join(', '),
      excludeSemantics: true,
      child: Builder(
        builder: (anchor) => Material(
          color: onDark ? Colors.white.withValues(alpha: .10) : t.glassFillStrong,
          shape: StadiumBorder(
            side: onDark ? BorderSide.none : BorderSide(color: t.isDark ? t.glassBorder : t.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () async {
              final code = await showVfLanguageMenu(anchor, value: value);
              if (code != null && code != value) onChanged(code);
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsRegular.globe, size: 17, color: soft),
                    const SizedBox(width: 7),
                    Text(
                      vfLanguageName(value),
                      style: VfType.label.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600, color: fg),
                    ),
                    const SizedBox(width: 5),
                    Icon(PhosphorIconsBold.caretDown, size: 12, color: soft),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
