import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../widgets/common.dart' show Fmt;
import '../../widgets/vf/vf.dart';

/// `yyyy-MM-dd`, the date format the API takes.
String apiDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// A filled app-style date control: tap to pick, with a clear button when
/// [clearable] and a date is set.
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
        borderRadius: BorderRadius.circular(vfInputRadius),
        child: InputDecorator(
          isEmpty: value == null,
          decoration: vfInputDecoration(
            context,
            hintText: placeholder,
            hasError: error != null && error!.isNotEmpty,
            suffixIcon: clearable && value != null
                ? IconButton(
                    tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                    icon: Icon(PhosphorIconsRegular.x, size: 16, color: t.muted),
                    onPressed: () => onChanged(null),
                  )
                : Icon(PhosphorIconsRegular.calendarBlank, size: 19, color: t.muted),
          ),
          child: Text(value == null ? '' : Fmt.date(value), style: VfType.body.copyWith(color: t.text)),
        ),
      ),
    );
  }
}

/// A labelled group of fields: a short bold label, then the fields with
/// app spacing — no box around them.
class VfFieldset extends StatelessWidget {
  const VfFieldset({super.key, required this.legend, required this.children});

  final String legend;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          legend,
          style: VfType.bodyStrong.copyWith(fontSize: 15.5, fontWeight: FontWeight.w700, color: t.text),
        ),
        for (final child in children) ...[const SizedBox(height: 14), child],
      ],
    );
  }
}

/// A compact info line in a soft tinted pill.
class VfNote extends StatelessWidget {
  const VfNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(color: t.primarySoft, borderRadius: BorderRadius.circular(VfSize.radiusL)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhosphorIconsFill.info, size: 17, color: t.primaryText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: VfType.small.copyWith(color: t.text2)),
          ),
        ],
      ),
    );
  }
}
