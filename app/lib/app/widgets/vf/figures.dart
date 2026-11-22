import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import 'surfaces.dart';

/*
 * The cards of the web's ERP screens (styles/refined.css, "in the structure
 * of the M-KOPA admin"): solid cards with a hairline and a soft blue shadow
 * that falls far, figure cards with a tinted icon tile, and panels whose
 * title carries a short accent bar. Every ERP app builds its pages from
 * these three pieces.
 */

/// The solid card every ERP surface sits on: white with a hairline and the
/// web's far shadow in light, the raised charcoal without a shadow in dark.
BoxDecoration vfCardDecoration(VfTokens t, {double radius = VfSize.radiusL}) =>
    BoxDecoration(
      color: t.isDark ? t.glassFill : Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: t.isDark ? t.glassBorder : t.border),
      boxShadow: t.isDark ? null : vfFarShadow,
    );

/// A soft, far, faintly blue shadow: present enough to lift a card off the
/// page, quiet enough not to be noticed.
const vfFarShadow = [
  BoxShadow(color: Color(0x0A101828), blurRadius: 2, offset: Offset(0, 1)),
  BoxShadow(
    color: Color(0x142563EB),
    blurRadius: 24,
    spreadRadius: -12,
    offset: Offset(0, 10),
  ),
];

/// A figure on an ERP home: a small tinted icon tile, the label, the value
/// and a quieter hint. In a [VouchFlowFigureGrid] cell it stacks (icon over
/// label over value); given the full width it is one slim row. A card that
/// opens something carries a small caret.
///
/// [tone] colours the tile: [VfTone.ok], [VfTone.warn], [VfTone.bad],
/// [VfTone.info], [VfTone.neutral], or the company colour by default.
class VouchFlowFigureCard extends StatelessWidget {
  const VouchFlowFigureCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.hint,
    this.tone = VfTone.primary,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? hint;
  final VfTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final tint = switch (tone) {
      VfTone.primary => t.primary,
      VfTone.neutral => t.muted,
      _ => tone.colors(t).$1,
    };
    final radius = BorderRadius.circular(VfSize.radiusL);

    Widget tile(double size) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: t.isDark ? .18 : .1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: size * .5, color: tint),
    );

    // In a grid cell: stacked. (Told by the grid rather than measured, so the
    // grid can size its rows to the tallest card.) A narrow cell lets a long
    // label or hint take a second line.
    final stacked =
        context.dependOnInheritedWidgetOfExactType<_FigureGridScope>() != null;
    final lines = stacked ? 2 : 1;
    final labelText = Text(
      label,
      maxLines: lines,
      overflow: TextOverflow.ellipsis,
      style: VfType.meta.copyWith(
        fontSize: 12.5,
        color: t.muted,
        fontWeight: FontWeight.w500,
      ),
    );
    final valueText = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        value,
        maxLines: 1,
        style: VfType.figure.copyWith(color: t.text),
      ),
    );
    final hintText = hint == null
        ? null
        : Text(
            hint!,
            maxLines: lines,
            overflow: TextOverflow.ellipsis,
            style: VfType.meta.copyWith(fontSize: 12, color: t.muted),
          );
    final caret = Icon(PhosphorIconsBold.caretRight, size: 13, color: t.faint);

    final Widget body;
    if (stacked) {
      body = Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [tile(36), const Spacer(), if (onTap != null) caret]),
            const SizedBox(height: 12),
            labelText,
            const SizedBox(height: 2),
            valueText,
            if (hintText != null) ...[const SizedBox(height: 2), hintText],
          ],
        ),
      );
    } else {
      // The full width: one slim row.
      body = Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(
          children: [
            tile(40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  labelText,
                  const SizedBox(height: 1),
                  valueText,
                  if (hintText != null) ...[
                    const SizedBox(height: 1),
                    hintText,
                  ],
                ],
              ),
            ),
            if (onTap != null) ...[const SizedBox(width: 8), caret],
          ],
        ),
      );
    }

    return Semantics(
      button: onTap != null,
      label: [label, value, ?hint].join(', '),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: vfCardDecoration(t),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: onTap == null ? body : InkWell(onTap: onTap, child: body),
        ),
      ),
    );
  }
}

/// Figure cards two to a row (three on a wide screen), each row as tall as
/// its tallest card, 10 apart. Children may be any widgets; a lone last card
/// takes the full width.
class VouchFlowFigureGrid extends StatelessWidget {
  const VouchFlowFigureGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    const gap = 10.0;
    return LayoutBuilder(
      builder: (context, box) {
        final cols = box.maxWidth >= 600 ? 3 : 2;
        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += cols) {
          final run = children.sublist(i, (i + cols).clamp(0, children.length));
          if (rows.isNotEmpty) rows.add(const SizedBox(height: gap));
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var k = 0; k < run.length; k++) ...[
                    if (k > 0) const SizedBox(width: gap),
                    Expanded(child: _FigureGridScope(child: run[k])),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: rows,
        );
      },
    );
  }
}

/// A section card (the web's `.vf-panel`): a title with a short 4px accent
/// bar on its left, an optional line under it, an optional outlined action
/// on the right, then the body.
///
/// Lists run to the card's edges: leave [padded] false and give each row
/// its own padding ([VouchFlowListRow] does).
class VouchFlowPanel extends StatelessWidget {
  const VouchFlowPanel({
    super.key,
    this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.trailing,
    required this.child,
    this.padded = true,
  });

  final String? title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Anything else beside the title (a count, a menu), instead of an action.
  final Widget? trailing;
  final Widget child;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return DecoratedBox(
      decoration: vfCardDecoration(t),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(VfSize.radiusL),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 15, 12, padded ? 4 : 11),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 4,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: t.primary,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Semantics(
                                    header: true,
                                    child: Text(
                                      title!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: VfType.cardTitle.copyWith(
                                        fontSize: 15.5,
                                        color: t.text,
                                        letterSpacing: -.1,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (subtitle != null)
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 14,
                                  top: 2,
                                ),
                                child: Text(
                                  subtitle!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: VfType.meta.copyWith(color: t.muted),
                                ),
                              ),
                          ],
                        ),
                      ),
                      ?trailing,
                      if (actionLabel != null && onAction != null)
                        VouchFlowPanelAction(
                          label: actionLabel!,
                          onTap: onAction!,
                        ),
                    ],
                  ),
                ),
              if (padded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: child,
                )
              else ...[
                if (title != null)
                  Divider(
                    height: 1,
                    color: t.isDark ? t.glassBorder : t.border,
                  ),
                child,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The small outlined button in a panel's head (the web's `.vf-card-link`).
class VouchFlowPanelAction extends StatelessWidget {
  const VouchFlowPanelAction({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VfSize.radiusM),
        side: BorderSide(color: t.isDark ? t.borderStrong : t.borderStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          // Short to look at, still a full touch target.
          constraints: const BoxConstraints(minHeight: 32),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            child: Text(
              label,
              style: VfType.meta.copyWith(
                fontSize: 13,
                color: t.text,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One row in a panel's list: a tinted icon tile, a title, a quieter line
/// and something on the right (a badge, a figure, a caret).
class VouchFlowListRow extends StatelessWidget {
  const VouchFlowListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.trailing,
    this.onTap,
    this.divider = true,
    this.titleMaxLines = 1,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// A hairline above the row; leave it off on the first row.
  final bool divider;
  final int titleMaxLines;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final tint = iconColor ?? t.primary;
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: t.isDark ? .18 : .1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 19, color: tint),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: titleMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: VfType.bodyStrong.copyWith(
                    fontSize: 14.5,
                    color: t.text,
                    height: 1.3,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VfType.meta.copyWith(
                      color: t.muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: divider
            ? Border(
                top: BorderSide(color: t.isDark ? t.glassBorder : t.border),
              )
            : null,
      ),
      child: onTap == null ? row : InkWell(onTap: onTap, child: row),
    );
  }
}

class _FigureGridScope extends InheritedWidget {
  const _FigureGridScope({required super.child});

  @override
  bool updateShouldNotify(_FigureGridScope oldWidget) => false;
}
