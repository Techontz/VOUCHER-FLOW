import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';

/// One step of a [VouchFlowStepper].
class VfStep {
  const VfStep(this.label);
  final String label;
}

/// The web's `.vf-stepper`: a boxed row of tabs, each a numbered badge and
/// label, the current one underlined in the primary and done steps ticked in
/// green. On a phone it scrolls sideways and keeps the current step in view.
class VouchFlowStepper extends StatefulWidget {
  const VouchFlowStepper({super.key, required this.steps, required this.current, this.onTap});

  final List<VfStep> steps;
  final int current;
  final ValueChanged<int>? onTap;

  @override
  State<VouchFlowStepper> createState() => _VouchFlowStepperState();
}

class _VouchFlowStepperState extends State<VouchFlowStepper> {
  final _keys = <int, GlobalKey>{};

  @override
  void didUpdateWidget(covariant VouchFlowStepper old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _keys[widget.current]?.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx, alignment: .5, duration: const Duration(milliseconds: 220));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(VfSize.radiusL),
        border: Border.all(color: t.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: IntrinsicHeight(
          child: Row(
            children: [
              for (var i = 0; i < widget.steps.length; i++)
                _item(context, t, i),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, VfTokens t, int i) {
    final state = i == widget.current ? 'current' : i < widget.current ? 'done' : 'pending';
    final key = _keys.putIfAbsent(i, GlobalKey.new);
    final (Color numBg, Color numFg, Color numBorder) = switch (state) {
      'current' => (t.primary, Colors.white, t.primary),
      'done' => (t.successSoft, t.success, Colors.transparent),
      _ => (t.surface3, t.text2, t.border),
    };
    return Semantics(
      key: key,
      button: widget.onTap != null,
      selected: state == 'current',
      child: InkWell(
        onTap: widget.onTap == null ? null : () => widget.onTap!(i),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            border: Border(
              right: i == widget.steps.length - 1 ? BorderSide.none : BorderSide(color: t.border),
              bottom: BorderSide(color: state == 'current' ? t.primary : Colors.transparent, width: 2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: numBg, shape: BoxShape.circle, border: Border.all(color: numBorder)),
                child: state == 'done'
                    ? Icon(PhosphorIconsBold.check, size: 11, color: numFg)
                    : Text('${i + 1}', style: VfType.meta.copyWith(fontSize: 11.5, height: 1, color: numFg, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 9),
              Text(
                widget.steps[i].label,
                style: VfType.label.copyWith(
                  fontSize: 14,
                  color: state == 'current' ? t.text : state == 'done' ? t.text2 : t.muted,
                  fontWeight: state == 'current' ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Icon tones used by the selection cards (the web's `data-cv-tone`).
enum VfCardTone { blue, green, orange, violet, teal, rose, slate }

extension VfCardToneColor on VfCardTone {
  Color get base => switch (this) {
    VfCardTone.blue => const Color(0xFF2563EB),
    VfCardTone.green => const Color(0xFF16A34A),
    VfCardTone.orange => const Color(0xFFEA580C),
    VfCardTone.violet => const Color(0xFF7C3AED),
    VfCardTone.teal => const Color(0xFF0D9488),
    VfCardTone.rose => const Color(0xFFE11D48),
    VfCardTone.slate => const Color(0xFF475569),
  };

  (Color fg, Color bg) colors(VfTokens t) {
    final b = this == VfCardTone.slate && t.isDark ? const Color(0xFF94A3B8) : base;
    return t.isDark
        ? (Color.lerp(b, Colors.white, .30)!, Color.alphaBlend(b.withValues(alpha: .22), t.surface))
        : (b, Color.alphaBlend(b.withValues(alpha: .12), t.surface));
  }
}

/// A large selection card: the web's Bank/Cash payment-method card (`large`)
/// and voucher-type card. Round tinted icon, title, description, and a tick
/// badge (or an empty radio for large cards) in the top-right corner.
class VouchFlowSelectCard extends StatelessWidget {
  const VouchFlowSelectCard({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    required this.icon,
    this.subtitle,
    this.tone = VfCardTone.blue,
    this.large = false,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final IconData icon;
  final VfCardTone tone;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final (fg, bg) = tone.colors(t);
    final selectBg = t.isDark
        ? Color.alphaBlend(t.primary.withValues(alpha: .14), t.surface)
        : Color.alphaBlend(t.primary.withValues(alpha: .06), t.surface);
    final iconSize = large ? 60.0 : 48.0;

    return Semantics(
      selected: selected,
      button: true,
      inMutuallyExclusiveGroup: true,
      label: title,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected ? selectBg : t.surface,
          borderRadius: BorderRadius.circular(VfSize.radiusXl),
          border: Border.all(color: selected ? t.primary : t.border, width: selected ? 2 : 1.5),
          boxShadow: selected
              ? [BoxShadow(color: t.primary.withValues(alpha: .25), blurRadius: 18, spreadRadius: -10, offset: const Offset(0, 6))]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(VfSize.radiusXl),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(large ? 16 : 14, large ? 18 : 14, large ? 46 : 30, large ? 18 : 14),
                  child: Row(
                    children: [
                      Container(
                        width: iconSize,
                        height: iconSize,
                        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                        child: Icon(icon, size: large ? 28 : 22, color: fg),
                      ),
                      SizedBox(width: large ? 16 : 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: (large ? VfType.cardTitle.copyWith(fontSize: 16.5, fontWeight: FontWeight.w700) : VfType.bodyStrong.copyWith(fontSize: 14.5))
                                  .copyWith(color: t.text),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 3),
                              Text(subtitle!, style: (large ? VfType.small : VfType.meta).copyWith(color: t.muted)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: large ? 12 : 8,
                  right: large ? 12 : 8,
                  child: selected
                      ? Container(
                          width: large ? 26 : 22,
                          height: large ? 26 : 22,
                          decoration: BoxDecoration(
                            color: t.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: t.surface, width: 2),
                          ),
                          child: Icon(PhosphorIconsBold.check, size: large ? 13 : 12, color: Colors.white),
                        )
                      : large
                      ? Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: t.borderStrong, width: 2), color: t.surface),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A segmented tab row, the web's `.app-tabs` (underlined current tab).
class VouchFlowTabs extends StatelessWidget {
  const VouchFlowTabs({super.key, required this.labels, required this.current, required this.onChanged, this.icons});

  final List<String> labels;
  final List<IconData>? icons;
  final int current;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.border))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              InkWell(
                onTap: () => onChanged(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: i == current ? t.primary : Colors.transparent, width: 2)),
                  ),
                  child: Row(
                    children: [
                      if (icons != null) ...[
                        Icon(icons![i], size: 17, color: i == current ? t.primaryText : t.muted),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        labels[i],
                        style: VfType.label.copyWith(
                          fontSize: 15,
                          color: i == current ? t.primaryText : t.muted,
                          fontWeight: i == current ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
