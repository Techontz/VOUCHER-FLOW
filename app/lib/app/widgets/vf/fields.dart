import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';

/// The web's `.field`: a label above the control (with a red asterisk when
/// required), the control, then either the error or a quiet hint.
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
                TextSpan(text: ' *', style: TextStyle(color: t.dangerStrong)),
            ],
          ),
          style: VfType.label.copyWith(color: t.text2),
        ),
        const SizedBox(height: 6),
        child,
        if (error != null && error!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(PhosphorIconsRegular.warningCircle, size: 15, color: t.dangerStrong),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(error!, style: VfType.meta.copyWith(color: t.dangerStrong)),
              ),
            ],
          ),
        ] else if (hint != null && hint!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(hint!, style: VfType.meta.copyWith(color: t.muted)),
        ],
      ],
    );
  }
}

/// A text input in the web's `.input` style, wrapped in a [VouchFlowField].
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
        decoration: InputDecoration(
          hintText: placeholder,
          counterText: '',
          filled: true,
          fillColor: readOnly || !enabled ? t.inputDisabled : t.inputBg,
          prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 18),
          prefixText: prefixText,
          suffixIcon: suffix,
          errorText: (error != null && error!.isNotEmpty) ? '' : null,
          errorStyle: const TextStyle(height: 0, fontSize: 0),
        ),
      ),
    );
  }
}

/// A select in the web's `.input` style.
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
        icon: Icon(PhosphorIconsRegular.caretDown, size: 16, color: t.muted),
        dropdownColor: t.surface,
        borderRadius: BorderRadius.circular(VfSize.radiusL),
        hint: placeholder == null
            ? null
            : Text(placeholder!, style: VfType.body.copyWith(color: t.placeholder)),
        style: VfType.body.copyWith(color: t.text),
        decoration: InputDecoration(
          filled: true,
          fillColor: onChanged == null ? t.inputDisabled : t.inputBg,
          errorText: (error != null && error!.isNotEmpty) ? '' : null,
          errorStyle: const TextStyle(height: 0, fontSize: 0),
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

/// The web's search field: a leading magnifier, clear button when filled.
class VouchFlowSearchField extends StatefulWidget {
  const VouchFlowSearchField({
    super.key,
    required this.placeholder,
    this.controller,
    this.onChanged,
    this.onSubmitted,
  });

  final String placeholder;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<VouchFlowSearchField> createState() => _VouchFlowSearchFieldState();
}

class _VouchFlowSearchFieldState extends State<VouchFlowSearchField> {
  late final TextEditingController _c =
      widget.controller ?? TextEditingController();

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
      decoration: InputDecoration(
        hintText: widget.placeholder,
        prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass, size: 18, color: t.faint),
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

/// A status filter pill (the web's register pills: "All 65", "Drafts" …).
class VouchFlowFilterChip extends StatelessWidget {
  const VouchFlowFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

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
        shape: StadiumBorder(side: BorderSide(color: selected ? t.primary : t.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
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
