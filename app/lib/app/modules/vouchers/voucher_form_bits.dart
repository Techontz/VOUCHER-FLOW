import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../widgets/common.dart' show Fmt;
import '../../widgets/vf/vf.dart';

/// `yyyy-MM-dd`, the date format the API takes.
String apiDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// A date control in the web's `.input` style: tap to pick, with a clear
/// button when [clearable] and a date is set.
class VfDateInput extends StatelessWidget {
  const VfDateInput({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.placeholder,
    this.clearable = false,
    this.error,
    this.hint,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String? placeholder;
  final bool clearable;
  final String? error;
  final String? hint;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5, 12, 31),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return VouchFlowField(
      label: label,
      error: error,
      hint: hint,
      child: InkWell(
        onTap: () => _pick(context),
        borderRadius: BorderRadius.circular(VfSize.radiusL),
        child: InputDecorator(
          isEmpty: value == null,
          decoration: InputDecoration(
            hintText: placeholder,
            errorText: (error != null && error!.isNotEmpty) ? '' : null,
            errorStyle: const TextStyle(height: 0, fontSize: 0),
            suffixIcon: clearable && value != null
                ? IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).deleteButtonTooltip,
                    icon: Icon(
                      PhosphorIconsRegular.x,
                      size: 16,
                      color: t.muted,
                    ),
                    onPressed: () => onChanged(null),
                  )
                : Icon(
                    PhosphorIconsRegular.calendarBlank,
                    size: 18,
                    color: t.faint,
                  ),
          ),
          child: Text(
            value == null ? '' : Fmt.date(value),
            style: VfType.body.copyWith(color: t.text),
          ),
        ),
      ),
    );
  }
}

/// The web's `.vf-fieldset`: a bordered group with an uppercase legend.
class VfFieldset extends StatelessWidget {
  const VfFieldset({super.key, required this.legend, required this.children});

  final String legend;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VfSize.radiusL),
        border: Border.all(color: t.border),
        color: t.surface2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VouchFlowEyebrow(legend),
          for (final child in children) ...[const SizedBox(height: 14), child],
        ],
      ),
    );
  }
}

/// The web's `Note`: a quiet info line.
class VfNote extends StatelessWidget {
  const VfNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(VfSize.radiusL),
        border: Border.all(color: t.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhosphorIconsRegular.info, size: 18, color: t.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: VfType.small.copyWith(color: t.text2)),
          ),
        ],
      ),
    );
  }
}
