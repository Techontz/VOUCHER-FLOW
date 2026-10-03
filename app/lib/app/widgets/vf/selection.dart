import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';

/// One step of a [VouchFlowStepper].
class VfStep {
  const VfStep(this.label);
  final String label;
}

/// An app progress header: the step's name in bold with "Step n of N"
/// beside it, over a row of rounded segments that fill with the primary as
/// the flow advances. Tapping a segment jumps to that step via [onTap].
class VouchFlowStepper extends StatelessWidget {
  const VouchFlowStepper({super.key, required this.steps, required this.current, this.onTap, this.progressLabel});

  final List<VfStep> steps;
  final int current;
  final ValueChanged<int>? onTap;

  /// The small "Step 1 of 5" line, given the 1-based step and the total.
  /// Defaults to "1 / 5".
  final String Function(int step, int total)? progressLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final n = steps.length;
    final i = current.clamp(0, n - 1);
    final counter = progressLabel?.call(i + 1, n) ?? '${i + 1} / $n';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                layoutBuilder: (cur, prev) => Stack(alignment: Alignment.centerLeft, children: [...prev, ?cur]),
                child: Text(
                  steps[i].label,
                  key: ValueKey(i),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VfType.cardTitle.copyWith(fontSize: 17, fontWeight: FontWeight.w700, color: t.text),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              counter,
              style: VfType.meta.copyWith(
                color: t.muted,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (var s = 0; s < n; s++) ...[
              if (s > 0) const SizedBox(width: 6),
              Expanded(
                child: Semantics(
                  button: onTap != null,
                  selected: s == i,
                  label: steps[s].label,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onTap == null ? null : () => onTap!(s),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        height: 6,
                        decoration: BoxDecoration(
                          color: s <= i ? t.primary : t.surface3,
                          borderRadius: BorderRadius.circular(VfSize.radiusPill),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
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

/// A large, rounded tappable choice: a tinted icon circle, a bold title and a
/// few-word hint, with a filled check when chosen (an empty ring for [large]
/// cards). The chosen card takes a primary border and a soft primary fill.
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
        ? Color.alphaBlend(t.primary.withValues(alpha: .16), t.surface)
        : Color.alphaBlend(t.primary.withValues(alpha: .07), t.surface);
    final iconSize = large ? 52.0 : 44.0;
    final radius = BorderRadius.circular(VfSize.radiusXl);

    return Semantics(
      selected: selected,
      button: true,
      inMutuallyExclusiveGroup: true,
      label: title,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? selectBg : t.surface,
          borderRadius: radius,
          border: Border.all(
            color: selected ? t.primary : (t.isDark ? t.border : Colors.transparent),
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: t.primary.withValues(alpha: .22),
                    blurRadius: 20,
                    spreadRadius: -8,
                    offset: const Offset(0, 8),
                  ),
                ]
              : t.cardShadow,
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: large ? 18 : 14),
              child: Row(
                children: [
                  Container(
                    width: iconSize,
                    height: iconSize,
                    decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                    child: Icon(icon, size: large ? 25 : 21, color: fg),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: VfType.bodyStrong.copyWith(
                            fontSize: large ? 16.5 : 15,
                            fontWeight: FontWeight.w700,
                            color: t.text,
                            height: 1.3,
                          ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: VfType.meta.copyWith(color: t.muted, fontSize: 13),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                    child: selected
                        ? Container(
                            key: const ValueKey('on'),
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(color: t.primary, shape: BoxShape.circle),
                            child: const Icon(PhosphorIconsBold.check, size: 14, color: Colors.white),
                          )
                        : Container(
                            key: const ValueKey('off'),
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: large ? t.borderStrong : t.border, width: 2),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of rounded tab pills that scrolls sideways; the current one sits in
/// a soft primary pill.
class VouchFlowTabs extends StatefulWidget {
  const VouchFlowTabs({super.key, required this.labels, required this.current, required this.onChanged, this.icons});

  final List<String> labels;
  final List<IconData>? icons;
  final int current;
  final ValueChanged<int> onChanged;

  @override
  State<VouchFlowTabs> createState() => _VouchFlowTabsState();
}

class _VouchFlowTabsState extends State<VouchFlowTabs> {
  final _keys = <int, GlobalKey>{};
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  GlobalKey _key(int i) => _keys.putIfAbsent(i, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void didUpdateWidget(covariant VouchFlowTabs old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) _reveal();
  }

  /// Keeps the current tab on screen when it is chosen in code (a deep link,
  /// a "view all" button) rather than by a tap on the row.
  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tab = _keys[widget.current]?.currentContext?.findRenderObject() as RenderBox?;
      final row = context.findRenderObject() as RenderBox?;
      if (!mounted || tab == null || row == null || !_scroll.hasClients) return;
      // Only the row scrolls sideways; the page around it stays put.
      final left = tab.localToGlobal(Offset.zero, ancestor: row).dx;
      final target = _scroll.offset + left - (row.size.width - tab.size.width) / 2;
      final pos = _scroll.position;
      _scroll.animateTo(
        target.clamp(pos.minScrollExtent, pos.maxScrollExtent),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final labels = widget.labels, icons = widget.icons, current = widget.current, onChanged = widget.onChanged;
    return SizedBox(
      height: 44,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Material(
                key: _key(i),
                color: i == current ? t.primarySoftStrong : Colors.transparent,
                shape: const StadiumBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onChanged(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        if (icons != null) ...[
                          Icon(icons[i], size: 17, color: i == current ? t.primaryText : t.muted),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          labels[i],
                          style: VfType.label.copyWith(
                            fontSize: 14.5,
                            color: i == current ? t.primaryText : t.muted,
                            fontWeight: i == current ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
