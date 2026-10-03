import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';

/// Corner radius of every filled input and select.
const vfInputRadius = 16.0;

/// The app's filled-input look: a soft tinted fill, no visible outline in
/// light (a whisper of one in dark), 16px corners and a primary ring on focus.
/// Every VouchFlow input and select shares it.
InputDecoration vfInputDecoration(
  BuildContext context, {
  String? hintText,
  Widget? prefixIcon,
  String? prefixText,
  Widget? suffixIcon,
  bool hasError = false,
  bool disabled = false,
  EdgeInsetsGeometry? contentPadding,
}) {
  final t = context.vf;
  final radius = BorderRadius.circular(vfInputRadius);
  OutlineInputBorder edge(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: radius,
    borderSide: c == Colors.transparent ? BorderSide.none : BorderSide(color: c, width: w),
  );
  final rest = t.isDark ? t.border.withValues(alpha: .9) : Colors.transparent;
  return InputDecoration(
    hintText: hintText,
    hintStyle: VfType.body.copyWith(color: t.placeholder),
    counterText: '',
    filled: true,
    fillColor: disabled ? Color.alphaBlend(t.surface3.withValues(alpha: .55), t.surface) : t.surface3,
    isDense: false,
    contentPadding: contentPadding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    prefixIcon: prefixIcon,
    prefixText: prefixText,
    suffixIcon: suffixIcon,
    border: edge(rest),
    enabledBorder: edge(hasError ? t.dangerStrong : rest, hasError ? 1.4 : 1),
    disabledBorder: edge(rest),
    focusedBorder: edge(hasError ? t.dangerStrong : t.primary, 1.6),
    errorBorder: edge(t.dangerStrong, 1.4),
    focusedErrorBorder: edge(t.dangerStrong, 1.6),
    errorText: hasError ? '' : null,
    errorStyle: const TextStyle(height: 0, fontSize: 0),
  );
}

/// A small label above the control (a red asterisk when required), the
/// control, then the error — or a short hint only where one is essential.
class VouchFlowField extends StatelessWidget {
  const VouchFlowField({
    super.key,
    required this.label,
    required this.child,
    this.required = false,
    this.hint,
    this.error,
  });

  final String label;
  final Widget child;
  final bool required;
  final String? hint;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            text: label,
            children: [
              if (required)
                TextSpan(
                  text: ' *',
                  style: TextStyle(color: t.dangerStrong),
                ),
            ],
          ),
          style: VfType.label.copyWith(color: t.text2, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        child,
        if (error != null && error!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1, left: 4),
                child: Icon(PhosphorIconsFill.warningCircle, size: 15, color: t.dangerStrong),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(error!, style: VfType.meta.copyWith(color: t.dangerStrong)),
              ),
            ],
          ),
        ] else if (hint != null && hint!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(hint!, style: VfType.meta.copyWith(color: t.muted)),
          ),
        ],
      ],
    );
  }
}

/// A filled app-style text input, wrapped in a [VouchFlowField].
class VouchFlowTextField extends StatelessWidget {
  const VouchFlowTextField({
    super.key,
    required this.label,
    this.controller,
    this.initialValue,
    this.onChanged,
    this.onSubmitted,
    this.placeholder,
    this.hint,
    this.error,
    this.required = false,
    this.obscure = false,
    this.readOnly = false,
    this.enabled = true,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.prefixIcon,
    this.prefixText,
    this.suffix,
    this.autofillHints,
    this.autofocus = false,
    this.focusNode,
    this.textCapitalization = TextCapitalization.none,
    this.onTap,
  });

  final String label;
  final TextEditingController? controller;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? placeholder;
  final String? hint;
  final String? error;
  final bool required;
  final bool obscure;
  final bool readOnly;
  final bool enabled;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;
  final int? minLines;
  final int? maxLength;
  final IconData? prefixIcon;
  final String? prefixText;
  final Widget? suffix;
  final Iterable<String>? autofillHints;
  final bool autofocus;
  final FocusNode? focusNode;
  final TextCapitalization textCapitalization;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return VouchFlowField(
      label: label,
      required: required,
      hint: hint,
      error: error,
      child: TextFormField(
        controller: controller,
        initialValue: controller == null ? initialValue : null,
        onChanged: onChanged,
        onFieldSubmitted: onSubmitted,
        obscureText: obscure,
        readOnly: readOnly,
        enabled: enabled,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        inputFormatters: inputFormatters,
        maxLines: obscure ? 1 : maxLines,
        minLines: minLines,
        maxLength: maxLength,
        autofillHints: autofillHints,
        autofocus: autofocus,
        focusNode: focusNode,
        textCapitalization: textCapitalization,
        onTap: onTap,
        style: VfType.body.copyWith(color: readOnly ? t.muted : t.text),
        cursorColor: t.primary,
        decoration: vfInputDecoration(
          context,
          hintText: placeholder,
          prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 19, color: t.muted),
          prefixText: prefixText,
          suffixIcon:
              suffix ??
              (readOnly && onTap == null ? Icon(PhosphorIconsRegular.lockSimple, size: 16, color: t.faint) : null),
          hasError: error != null && error!.isNotEmpty,
          disabled: readOnly || !enabled,
        ),
      ),
    );
  }
}

/// A filled app-style select.
class VouchFlowDropdown<T> extends StatelessWidget {
  const VouchFlowDropdown({
    super.key,
    required this.label,
    required this.items,
    required this.value,
    required this.onChanged,
    required this.itemLabel,
    this.hint,
    this.error,
    this.required = false,
    this.placeholder,
  });

  final String label;
  final List<T> items;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final String Function(T) itemLabel;
  final String? hint;
  final String? error;
  final bool required;
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return VouchFlowField(
      label: label,
      required: required,
      hint: hint,
      error: error,
      child: DropdownButtonFormField<T>(
        initialValue: items.contains(value) ? value : null,
        isExpanded: true,
        onChanged: onChanged,
        icon: Icon(
          onChanged == null ? PhosphorIconsRegular.lockSimple : PhosphorIconsBold.caretDown,
          size: onChanged == null ? 16 : 14,
          color: onChanged == null ? t.faint : t.muted,
        ),
        dropdownColor: t.surface,
        borderRadius: BorderRadius.circular(vfInputRadius),
        hint: placeholder == null ? null : Text(placeholder!, style: VfType.body.copyWith(color: t.placeholder)),
        style: VfType.body.copyWith(color: onChanged == null ? t.text2 : t.text),
        decoration: vfInputDecoration(
          context,
          hasError: error != null && error!.isNotEmpty,
          disabled: onChanged == null,
          contentPadding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
        ),
        items: [
          for (final item in items)
            DropdownMenuItem<T>(
              value: item,
              child: Text(itemLabel(item), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    );
  }
}

/// A rounded filled search bar: a leading magnifier, clear button when filled.
class VouchFlowSearchField extends StatefulWidget {
  const VouchFlowSearchField({super.key, required this.placeholder, this.controller, this.onChanged, this.onSubmitted});

  final String placeholder;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<VouchFlowSearchField> createState() => _VouchFlowSearchFieldState();
}

class _VouchFlowSearchFieldState extends State<VouchFlowSearchField> {
  late final TextEditingController _c = widget.controller ?? TextEditingController();

  @override
  void dispose() {
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return TextField(
      controller: _c,
      onChanged: (v) {
        setState(() {});
        widget.onChanged?.call(v);
      },
      onSubmitted: widget.onSubmitted,
      textInputAction: TextInputAction.search,
      style: VfType.body.copyWith(color: t.text),
      cursorColor: t.primary,
      decoration: vfInputDecoration(
        context,
        hintText: widget.placeholder,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass, size: 19, color: t.muted),
        suffixIcon: _c.text.isEmpty
            ? null
            : IconButton(
                tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                icon: Icon(PhosphorIconsRegular.x, size: 16, color: t.muted),
                onPressed: () {
                  _c.clear();
                  setState(() {});
                  widget.onChanged?.call('');
                },
              ),
      ),
    );
  }
}

/// A rounded status filter pill ("All 65", "Drafts" …): solid primary when
/// chosen, a soft tinted pill otherwise.
class VouchFlowFilterChip extends StatelessWidget {
  const VouchFlowFilterChip({super.key, required this.label, required this.selected, required this.onTap, this.count});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? t.primary : t.surface,
        shape: StadiumBorder(side: selected || !t.isDark ? BorderSide.none : BorderSide(color: t.border)),
        elevation: 0,
        shadowColor: Colors.transparent,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: VfType.label.copyWith(
                    fontSize: 14.5,
                    color: selected ? Colors.white : t.text2,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(
                      color: selected ? Colors.white.withValues(alpha: .22) : t.surface3,
                      borderRadius: BorderRadius.circular(VfSize.radiusPill),
                    ),
                    child: Text(
                      '$count',
                      style: VfType.meta.copyWith(
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : t.text2,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
