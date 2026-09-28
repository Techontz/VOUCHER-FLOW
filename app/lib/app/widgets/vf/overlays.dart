import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'surfaces.dart';

/// One labelled line in a dialog's summary (the web's `Dialog summary`).
class VfSummaryRow {
  const VfSummaryRow(this.label, this.value);
  final String label;
  final String value;
}

/// The web's `Dialog`: a tone-coloured icon plate, title, subtitle, an
/// optional summary block, optional body, and actions — on a phone it rises
/// as a bottom sheet, as the web dialog does under 640px.
class VouchFlowDialog extends StatelessWidget {
  const VouchFlowDialog({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.tone = VfTone.info,
    this.summary = const [],
    this.child,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final VfTone tone;
  final List<VfSummaryRow> summary;
  final Widget? child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final (fg, bg) = tone.colors(t);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(VfSize.radiusL)),
                    child: Icon(icon, color: fg, size: 22),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Text(title, style: VfType.sectionTitle.copyWith(color: t.text)),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(subtitle!, style: VfType.body.copyWith(color: t.text2)),
              ],
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: t.surface2,
                    borderRadius: BorderRadius.circular(VfSize.radiusL),
                    border: Border.all(color: t.border),
                  ),
                  child: Column(
                    children: [
                      for (final row in summary)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: Text(row.label, style: VfType.small.copyWith(color: t.muted))),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  row.value,
                                  textAlign: TextAlign.right,
                                  style: VfType.small.copyWith(color: t.text, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (child != null) ...[const SizedBox(height: 16), child!],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(child: actions[i]),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows a [VouchFlowDialog] as a bottom sheet (the web dialog's phone form).
Future<T?> showVouchFlowDialog<T>(
  BuildContext context, {
  required VouchFlowDialog dialog,
  bool dismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    useSafeArea: true,
    builder: (_) => dialog,
  );
}

/// A titled bottom sheet for filters and pickers.
Future<T?> showVouchFlowBottomSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
  List<Widget> actions = const [],
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      final t = ctx.vf;
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .88),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(title, style: VfType.sectionTitle.copyWith(color: t.text)),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: child,
                ),
              ),
              if (actions.isNotEmpty)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                    child: Row(
                      children: [
                        for (var i = 0; i < actions.length; i++) ...[
                          if (i > 0) const SizedBox(width: 10),
                          Expanded(child: actions[i]),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
