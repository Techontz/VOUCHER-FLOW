import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';

/// Small app-list building blocks shared by the queues, reports, the inbox
/// and the profile: a big screen title, a tinted icon tile, a grouped list
/// card with inset dividers, a round check, and a strip of compact figures.

/// A screen's big title, with an optional count and trailing actions.
class AppScreenTitle extends StatelessWidget {
  const AppScreenTitle({
    super.key,
    required this.title,
    this.count,
    this.trailing = const [],
  });

  final String title;
  final int? count;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VfType.pageTitle.copyWith(color: t.text, fontSize: 28),
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: t.primarySoft,
                    borderRadius: BorderRadius.circular(VfSize.radiusPill),
                  ),
                  child: Text(
                    '$count',
                    style: VfType.label.copyWith(
                      color: t.primaryText,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        for (var i = 0; i < trailing.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          trailing[i],
        ],
      ],
    );
  }
}

/// A rounded square holding an icon on a soft tint.
class AppIconTile extends StatelessWidget {
  const AppIconTile({
    super.key,
    required this.icon,
    required this.fg,
    required this.bg,
    this.size = 44,
    this.circle = false,
  });

  final IconData icon;
  final Color fg, bg;
  final double size;
  final bool circle;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: bg,
      shape: circle ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: circle ? null : BorderRadius.circular(size * .32),
    ),
    child: Icon(icon, size: size * .48, color: fg),
  );
}

/// A rounded card of rows separated by dividers that start after the
/// leading tile — the iOS / Android grouped list.
class AppListGroup extends StatelessWidget {
  const AppListGroup({
    super.key,
    required this.children,
    this.indent = 72,
    this.header,
  });

  final List<Widget> children;
  final double indent;

  /// A small label above the card ("Today", "Preferences").
  final String? header;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final card = Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(VfSize.radiusXl),
        border: Border.all(color: t.isDark ? t.border : Colors.transparent),
        boxShadow: t.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: indent,
                  color: t.border,
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
    if (header == null) return card;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
          child: Text(
            header!,
            style: VfType.label.copyWith(
              color: t.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        card,
      ],
    );
  }
}

/// A round selection check, filled in the accent when on.
class AppRoundCheck extends StatelessWidget {
  const AppRoundCheck({
    super.key,
    required this.value,
    this.enabled = true,
    this.size = 26,
  });

  final bool value;
  final bool enabled;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: value ? t.primary : Colors.transparent,
        border: Border.all(
          color: value
              ? t.primary
              : enabled
              ? t.borderStrong
              : t.border,
          width: 2,
        ),
      ),
      child: value
          ? Icon(PhosphorIconsBold.check, size: size * .55, color: Colors.white)
          : null,
    );
  }
}

/// One compact figure.
class AppStat {
  const AppStat(this.label, this.value, {this.sub, this.icon, this.tint});

  final String label, value;
  final String? sub;
  final IconData? icon;

  /// (foreground, background); the accent when null.
  final (Color, Color)? tint;
}

/// Compact figures side by side, scrolling sideways on a phone.
class AppStatStrip extends StatelessWidget {
  const AppStatStrip({super.key, required this.stats});

  final List<AppStat> stats;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: stats.any((s) => s.sub != null) ? 104 : 86,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              _tile(context, stats[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, AppStat s) {
    final t = context.vf;
    final (fg, bg) = s.tint ?? (t.primaryText, t.primarySoft);
    return Container(
      constraints: const BoxConstraints(minWidth: 132, maxWidth: 220),
      padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(VfSize.radiusXl),
        border: Border.all(color: t.isDark ? t.border : Colors.transparent),
        boxShadow: t.cardShadow,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (s.icon != null) ...[
                AppIconTile(icon: s.icon!, fg: fg, bg: bg, size: 22),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  s.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VfType.meta.copyWith(color: t.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            s.value,
            maxLines: 1,
            style: VfType.bodyStrong.copyWith(
              color: t.text,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              height: 1.2,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (s.sub != null) ...[
            const SizedBox(height: 2),
            Text(
              s.sub!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: VfType.meta.copyWith(color: t.muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

/// A small text action for a title row ("Select", "Mark all read").
class AppTextAction extends StatelessWidget {
  const AppTextAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final color = onPressed == null ? t.faint : t.primaryText;
    return Material(
      color: t.primarySoft,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: loading ? null : onPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: 38),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              else if (icon != null)
                Icon(icon, size: 17, color: color),
              if (loading || icon != null) const SizedBox(width: 6),
              Text(
                label,
                style: VfType.label.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
