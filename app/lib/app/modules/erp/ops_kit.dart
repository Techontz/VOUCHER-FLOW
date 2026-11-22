import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart';
import '../../data/services/api_service.dart';
import '../../widgets/vf/vf.dart';

/*
 * Pieces the Production, CRM and Documents screens share, on top of the
 * ERP kit (erp_widgets.dart): the action bar at the foot of a record, the
 * confirming buttons of an action sheet, a record's head, tone badges and
 * a horizontal chip row. They keep the three apps reading like Inventory.
 */

/// The message to show for a failed call: the API's own wording, or the
/// offline line.
String opsError(Object e) => e is ApiException ? e.message : 'state.offline'.tr;

/// "89.9%", or a dash.
String opsPercent(double? v) => v == null ? '-' : '${ErpFmt.qty(double.parse(v.toStringAsFixed(1)))}%';

/// A status pill in one of the five tones.
class OpsBadge extends StatelessWidget {
  const OpsBadge(this.label, {super.key, this.tone = VfTone.neutral, this.large = false});

  final String label;
  final VfTone tone;
  final bool large;

  @override
  Widget build(BuildContext context) => VouchFlowStatusBadge(
    label: label,
    large: large,
    tag: switch (tone) {
      VfTone.ok => 'tag-accent',
      VfTone.bad => 'tag-accent-2',
      VfTone.info || VfTone.primary => 'tag-info',
      VfTone.warn => 'tag-warn',
      VfTone.neutral => 'tag-neutral',
    },
  );
}

/// The glass bar at the foot of a pushed record page, holding its actions.
class OpsActionBar extends StatelessWidget {
  const OpsActionBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return VfGlass(
      borderRadius: BorderRadius.zero,
      fill: t.barFill,
      highlight: false,
      shadow: false,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(VfSize.pagePad, 12, VfSize.pagePad, 12),
          child: children.length == 1 ? children.single : OpsButtonRows(children: children),
        ),
      ),
    );
  }
}

/// Buttons two to a row while their labels fit, otherwise one to a row,
/// always as tall as they need (unlike a plain Column, which would fill a
/// scaffold's bottom bar).
class OpsButtonRows extends StatelessWidget {
  const OpsButtonRows({super.key, required this.children});

  final List<Widget> children;

  static double _need(Widget w) {
    if (w is! VouchFlowButton) return 120;
    final painter = TextPainter(
      text: TextSpan(text: w.label, style: VfType.bodyStrong),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width + 36 + (w.icon != null ? 26 : 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 10.0;
        final half = (c.maxWidth - gap) / 2;
        final rows = <List<Widget>>[];
        for (var i = 0; i < children.length; i += 2) {
          final pair = children.skip(i).take(2).toList();
          if (pair.length == 2 && pair.every((w) => _need(w) <= half)) {
            rows.add(pair);
          } else {
            rows.addAll([for (final w in pair) [w]]);
          }
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) const SizedBox(height: 8),
              rows[r].length == 1
                  ? rows[r].single
                  : Row(
                      children: [
                        Expanded(child: rows[r][0]),
                        const SizedBox(width: gap),
                        Expanded(child: rows[r][1]),
                      ],
                    ),
            ],
          ],
        );
      },
    );
  }
}

/// A record's head: a tinted icon tile, a kicker, the title, a quieter
/// line, and its status.
class OpsHead extends StatelessWidget {
  const OpsHead({
    super.key,
    required this.icon,
    required this.title,
    this.kicker,
    this.subtitle,
    this.badge,
    this.tint,
  });

  final IconData icon;
  final String title;
  final String? kicker, subtitle;
  final Widget? badge;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final c = tint ?? t.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: c.withValues(alpha: t.isDark ? .18 : .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 25, color: c),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (kicker != null)
                  Text(kicker!, style: VfType.small.copyWith(color: t.muted, fontWeight: FontWeight.w500)),
                Text(
                  title,
                  style: VfType.pageTitle.copyWith(
                    color: t.text,
                    fontSize: 19,
                    letterSpacing: -.3,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: VfType.small.copyWith(color: t.text2)),
                ],
                if (badge != null) ...[const SizedBox(height: 10), badge!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A row of filter chips that scrolls sideways.
class OpsChips<T> extends StatelessWidget {
  const OpsChips({super.key, required this.values, required this.selected, required this.label, required this.onChanged, this.counts});

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  final Map<T, int>? counts;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < values.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            VouchFlowFilterChip(
              label: label(values[i]),
              selected: values[i] == selected,
              count: counts?[values[i]],
              onTap: () => onChanged(values[i]),
            ),
          ],
        ],
      ),
    );
  }
}

/// A panel's quiet empty line.
class OpsPanelEmpty extends StatelessWidget {
  const OpsPanelEmpty(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(22),
    child: Text(text, textAlign: TextAlign.center, style: VfType.small.copyWith(color: context.vf.muted)),
  );
}

/// The foot of an action sheet: an optional text field (a reason, a note),
/// the API's refusal in place, Back and the confirming button, which runs
/// [run] and closes the sheet with its result.
class OpsConfirm extends StatefulWidget {
  const OpsConfirm({
    super.key,
    required this.confirmLabel,
    required this.run,
    this.backLabel,
    this.danger = false,
    this.fieldLabel,
    this.fieldHint,
    this.minLength = 0,
    this.ready = true,
    this.icon,
  });

  final String confirmLabel;
  final String? backLabel;
  final bool danger;
  final IconData? icon;

  /// When set, a text field above the buttons, needing [minLength] characters.
  final String? fieldLabel;
  final String? fieldHint;
  final int minLength;

  /// False keeps the confirming button off (a form above is incomplete).
  final bool ready;
  final Future<String> Function(String text) run;

  @override
  State<OpsConfirm> createState() => _OpsConfirmState();
}

class _OpsConfirmState extends State<OpsConfirm> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; });
    try {
      final result = await widget.run(_text.text.trim());
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = opsError(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final ready = widget.ready && (widget.fieldLabel == null || _text.text.trim().length >= widget.minLength);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.fieldLabel != null) ...[
          VouchFlowTextField(
            label: widget.fieldLabel!,
            required: widget.minLength > 0,
            hint: widget.minLength > 0 ? null : 'inv.optional'.tr,
            controller: _text,
            placeholder: widget.fieldHint,
            maxLines: 3,
            minLines: 1,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 4),
        ],
        if (_error != null) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(PhosphorIconsRegular.warningCircle, size: 16, color: t.dangerStrong),
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(_error!, style: VfType.small.copyWith(color: t.dangerStrong))),
            ],
          ),
          const SizedBox(height: 4),
        ],
        const SizedBox(height: 14),
        VouchFlowActions(
          children: [
            VouchFlowButton(
              label: widget.backLabel ?? 'action.back'.tr,
              variant: VfButtonVariant.secondary,
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
            ),
            VouchFlowButton(
              label: widget.confirmLabel,
              icon: widget.icon,
              variant: widget.danger ? VfButtonVariant.dangerSolid : VfButtonVariant.primary,
              loading: _busy,
              onPressed: ready && !_busy ? _go : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// A two-figure tile row inside a panel ("Planned 800", "Produced 700").
class OpsFigureGrid extends StatelessWidget {
  const OpsFigureGrid({super.key, required this.items});

  final List<(String label, String value)> items;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return LayoutBuilder(
      builder: (context, box) {
        final cols = box.maxWidth >= 480 ? 3 : 2;
        final w = (box.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final (label, value) in items)
              Container(
                width: w,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: t.isDark ? t.glassFillStrong : t.background,
                  borderRadius: BorderRadius.circular(VfSize.radiusM + 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: VfType.meta.copyWith(color: t.muted)),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: VfType.bodyStrong.copyWith(
                          color: t.text,
                          fontSize: 17,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A thin progress bar (an order's released against planned).
class OpsProgress extends StatelessWidget {
  const OpsProgress(this.value, {super.key, this.color});

  final double value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return ClipRRect(
      borderRadius: BorderRadius.circular(VfSize.radiusPill),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: 5,
        color: color ?? t.primary,
        backgroundColor: (color ?? t.primary).withValues(alpha: t.isDark ? .18 : .12),
      ),
    );
  }
}
