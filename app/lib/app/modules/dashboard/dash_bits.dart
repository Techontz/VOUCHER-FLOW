import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../widgets/vf/vf.dart';

/// Translates a key the API sent, filling `@name` placeholders from [params].
/// An unknown key falls back to the English text the API sent — the web's
/// `translateKey`.
String dashTr(
  String? key,
  String fallback, [
  Map<String, String> params = const {},
]) {
  if (key == null || key.isEmpty) return fallback;
  final text = params.isEmpty ? key.tr : key.trParams(params);
  return text == key ? fallback : text;
}

bool get dashIsSw => Get.locale?.languageCode == 'sw';

/// "2 hours ago", "yesterday", "3 weeks ago" — the web's `relativeTime`.
String dashRelative(DateTime? value) {
  if (value == null) return '—';
  final seconds = DateTime.now().difference(value).inSeconds;
  String n(String key, int v) => key.trParams({'n': '$v'});

  if (seconds < 60) return 'dashboard.time.now'.tr;
  final minutes = (seconds / 60).round();
  if (seconds < 3600) {
    return minutes <= 1
        ? 'dashboard.time.minute'.tr
        : n('dashboard.time.minutes', minutes);
  }
  final hours = (seconds / 3600).round();
  if (seconds < 86400) {
    return hours <= 1
        ? 'dashboard.time.hour'.tr
        : n('dashboard.time.hours', hours);
  }
  final days = (seconds / 86400).round();
  if (seconds < 604800) {
    return days <= 1
        ? 'dashboard.time.yesterday'.tr
        : n('dashboard.time.days', days);
  }
  final weeks = (seconds / 604800).round();
  if (seconds < 2629800) {
    return weeks <= 1
        ? 'dashboard.time.lastWeek'.tr
        : n('dashboard.time.weeks', weeks);
  }
  final months = (seconds / 2629800).round();
  if (seconds < 31557600) {
    return months <= 1
        ? 'dashboard.time.lastMonth'.tr
        : n('dashboard.time.months', months);
  }
  return dashDate(value);
}

/// "24 Sep 2026" (en-GB) or the Swahili month name.
String dashDate(DateTime? value) {
  if (value == null) return '—';
  final months = dashIsSw ? _monthsSw : _monthsEn;
  return '${value.day} ${months[value.month - 1]} ${value.year}';
}

const _monthsEn = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _monthsSw = [
  'Jan', 'Feb', 'Mac', 'Apr', 'Mei', 'Jun', //
  'Jul', 'Ago', 'Sep', 'Okt', 'Nov', 'Des',
];

/// "24 Sep 2026 · 14:05".
String dashDateTime(DateTime? value) => value == null
    ? '—'
    : '${dashDate(value)} · ${DateFormat('HH:mm').format(value)}';

/// "TZS 450,000".
String dashMoney(double amount, [String currency = 'TZS']) {
  final pattern = amount % 1 == 0 ? '#,##0' : '#,##0.00';
  return '$currency ${NumberFormat(pattern, 'en_US').format(amount)}';
}

/// "TZS 4.9M", "TZS 450K" — the web's `compactMoney`.
String dashCompactMoney(double amount, [String currency = 'TZS']) {
  if (amount.abs() >= 1000000) {
    return '$currency ${(amount / 1000000).toStringAsFixed(1)}M';
  }
  if (amount.abs() >= 1000) {
    return '$currency ${(amount / 1000).toStringAsFixed(0)}K';
  }
  return dashMoney(amount, currency);
}

/// The web's Phosphor class names, for icons the API chooses.
IconData phIcon(String? name) => switch (name) {
  'ph-alarm' => PhosphorIconsRegular.alarm,
  'ph-arrow-u-up-left' => PhosphorIconsRegular.arrowUUpLeft,
  'ph-buildings' => PhosphorIconsRegular.buildings,
  'ph-calendar' => PhosphorIconsRegular.calendar,
  'ph-chat-circle-text' => PhosphorIconsRegular.chatCircleText,
  'ph-check-circle' => PhosphorIconsRegular.checkCircle,
  'ph-circle-dashed' => PhosphorIconsRegular.circleDashed,
  'ph-coins' => PhosphorIconsRegular.coins,
  'ph-envelope-simple' => PhosphorIconsRegular.envelopeSimple,
  'ph-file-pdf' => PhosphorIconsRegular.filePdf,
  'ph-hourglass-medium' => PhosphorIconsRegular.hourglassMedium,
  'ph-image' => PhosphorIconsRegular.image,
  'ph-layout' => PhosphorIconsRegular.layout,
  'ph-list-checks' => PhosphorIconsRegular.listChecks,
  'ph-money' => PhosphorIconsRegular.money,
  'ph-receipt' => PhosphorIconsRegular.receipt,
  'ph-seal-check' => PhosphorIconsRegular.sealCheck,
  'ph-signature' => PhosphorIconsRegular.signature,
  'ph-user' => PhosphorIconsRegular.user,
  'ph-wallet' => PhosphorIconsRegular.wallet,
  'ph-x-circle' => PhosphorIconsRegular.xCircle,
  'ph-bank' => PhosphorIconsRegular.bank,
  'ph-credit-card' => PhosphorIconsRegular.creditCard,
  'ph-warning-circle' => PhosphorIconsRegular.warningCircle,
  'ph-paper-plane-tilt' => PhosphorIconsRegular.paperPlaneTilt,
  'ph-pencil-simple' => PhosphorIconsRegular.pencilSimple,
  'ph-crown-simple' => PhosphorIconsRegular.crownSimple,
  'ph-users-three' => PhosphorIconsRegular.usersThree,
  _ => PhosphorIconsRegular.bell,
};

/// A home section: a short title (with an optional count and a "See all"
/// link) above a rounded card whose body runs to the edges.
class DashPanel extends StatelessWidget {
  const DashPanel({
    super.key,
    required this.title,
    this.count,
    this.subtitle,
    this.trailing,
    this.below,
    required this.child,
    this.footer,
  });

  final String title;
  final int? count;

  /// Kept for callers outside home; home itself shows no subtitles.
  final String? subtitle;
  final Widget? trailing;

  /// A line under the title row, above the card (an action).
  final Widget? below;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 0, 10),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VfType.sectionTitle.copyWith(
                    color: t.text,
                    fontSize: 17,
                  ),
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 8),
                DashCount(count!),
              ],
              const Spacer(),
              ?trailing,
            ],
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 0, 10),
            child: Text(
              subtitle!,
              style: VfType.small.copyWith(color: t.muted),
            ),
          ),
        if (below != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: below,
          ),
        VouchFlowCard(
          radius: VfSize.radiusXl,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [child, ?footer],
          ),
        ),
      ],
    );
  }
}

/// A small tinted pill with a number.
class DashCount extends StatelessWidget {
  const DashCount(this.count, {super.key});
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: t.primarySoft,
        borderRadius: BorderRadius.circular(VfSize.radiusPill),
      ),
      child: Text(
        '$count',
        style: VfType.meta.copyWith(
          color: t.primaryText,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// A quiet link beside a section title: "See all ›".
class DashLink extends StatelessWidget {
  const DashLink({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VfSize.radiusPill),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: VfType.small.copyWith(
                    color: t.primaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  PhosphorIconsBold.caretRight,
                  size: 13,
                  color: t.primaryText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A quiet line inside a section ("No activity yet.").
class DashEmpty extends StatelessWidget {
  const DashEmpty(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(18),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: VfType.small.copyWith(color: context.vf.muted),
    ),
  );
}

/// A rounded, tinted square holding an icon: the lead of every list row.
class DashIconTile extends StatelessWidget {
  const DashIconTile({
    super.key,
    required this.icon,
    required this.color,
    this.background,
    this.size = 40,
  });

  final IconData icon;
  final Color color;
  final Color? background;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: background ?? color.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(size * .32),
    ),
    alignment: Alignment.center,
    child: Icon(icon, size: size * .5, color: color),
  );
}

/// Label left, value right, inset hairlines between.
class DashFacts extends StatelessWidget {
  const DashFacts(this.rows, {super.key});

  /// (label, value, muted value)
  final List<(String, String, bool)> rows;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          DashRow(
            last: i == rows.length - 1,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    rows[i].$1,
                    style: VfType.small.copyWith(color: t.text2),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    rows[i].$2,
                    textAlign: TextAlign.right,
                    style: VfType.small.copyWith(
                      color: rows[i].$3 ? t.muted : t.text,
                      fontWeight: rows[i].$3
                          ? FontWeight.w400
                          : FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Name and value over a rounded meter.
class DashBars extends StatelessWidget {
  const DashBars(this.rows, {super.key});

  /// (name, count, value, share 0–1)
  final List<(String, int, String, double)> rows;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final figures = const [FontFeature.tabularFigures()];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            Semantics(
              label: '${rows[i].$1}: ${rows[i].$2} · ${rows[i].$3}',
              child: ExcludeSemantics(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            rows[i].$1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: VfType.small.copyWith(
                              color: t.text,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          rows[i].$3,
                          style: VfType.small.copyWith(
                            color: t.text,
                            fontWeight: FontWeight.w600,
                            fontFeatures: figures,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(VfSize.radiusPill),
                      child: SizedBox(
                        height: 8,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ColoredBox(color: t.surface3),
                            ),
                            FractionallySizedBox(
                              widthFactor: rows[i].$4,
                              heightFactor: 1,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      t.palette.hoverDark,
                                      t.palette.primaryLight,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    VfSize.radiusPill,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A tappable row in a section list, with an inset hairline under it.
class DashRow extends StatelessWidget {
  const DashRow({
    super.key,
    required this.child,
    this.onTap,
    this.last = false,
    this.inset = 16,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool last;

  /// Where the hairline starts: past the row's leading tile.
  final double inset;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final body = Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: padding,
      alignment: Alignment.centerLeft,
      child: child,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onTap == null)
          body
        else
          Material(
            type: MaterialType.transparency,
            child: InkWell(onTap: onTap, child: body),
          ),
        if (!last)
          Padding(
            padding: EdgeInsets.only(left: inset),
            child: Container(height: 1, color: t.border),
          ),
      ],
    );
  }
}

/// A slim tappable notice: tinted icon, one short line, a chevron.
class DashAlertRow extends StatelessWidget {
  const DashAlertRow({
    super.key,
    required this.icon,
    required this.text,
    required this.tone,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String text;
  final VfTone tone;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final (fg, bg) = tone.colors(t);
    return VouchFlowCard(
      radius: VfSize.radiusXl,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      color: bg,
      borderColor: fg.withValues(alpha: t.isDark ? .35 : .18),
      onTap: onTap,
      child: Row(
        children: [
          DashIconTile(
            icon: icon,
            color: fg,
            background: t.surface.withValues(alpha: t.isDark ? .35 : .8),
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: VfType.bodyStrong.copyWith(color: t.text, fontSize: 14),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Text(
              trailing!,
              style: VfType.small.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(PhosphorIconsBold.caretRight, size: 14, color: fg),
          ],
        ],
      ),
    );
  }
}

/// A round tinted icon with a one-word label under it.
class DashQuickAction extends StatelessWidget {
  const DashQuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VfSize.radiusL),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: t.isDark ? t.primarySoft : t.surface,
                      shape: BoxShape.circle,
                      border: t.isDark
                          ? Border.all(
                              color: t.primary.withValues(alpha: .25),
                            )
                          : null,
                      boxShadow: t.isDark ? null : t.cardShadow,
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, size: 24, color: t.primary),
                  ),
                  if (badge > 0)
                    Positioned(
                      top: -2,
                      right: -4,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 20),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: t.dangerStrong,
                          borderRadius: BorderRadius.circular(
                            VfSize.radiusPill,
                          ),
                          border: Border.all(color: t.background, width: 2),
                        ),
                        child: Text(
                          badge > 99 ? '99+' : '$badge',
                          textAlign: TextAlign.center,
                          style: VfType.meta.copyWith(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: VfType.meta.copyWith(
                  color: t.text2,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact figure: tinted icon, big number, one short label.
class DashStatTile extends StatelessWidget {
  const DashStatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
    this.note,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VfTone tone;

  /// At most a few words ("TZS 26.5M", "↑ 12%").
  final String? note;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final (fg, bg) = tone.colors(t);
    return Semantics(
      label: [label, value, ?note].join(', '),
      button: onTap != null,
      excludeSemantics: true,
      child: VouchFlowCard(
        radius: VfSize.radiusXl,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DashIconTile(
                  icon: icon,
                  color: tone == VfTone.primary ? t.primary : fg,
                  background: bg,
                  size: 34,
                ),
                const Spacer(),
                if (onTap != null)
                  Icon(PhosphorIconsBold.caretRight, size: 13, color: t.faint),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: VfType.figureS.copyWith(
                    color: t.text,
                    fontSize: 22,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: VfType.meta.copyWith(color: t.muted, fontSize: 13),
            ),
            if (note != null) ...[
              const SizedBox(height: 2),
              Text(
                note!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: VfType.meta.copyWith(
                  color: tone == VfTone.primary || tone == VfTone.neutral
                      ? t.text2
                      : fg,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The home's lead card: the one figure that matters for this role, on the
/// brand gradient, with one compact action.
class DashHero extends StatelessWidget {
  const DashHero({
    super.key,
    required this.icon,
    required this.label,
    required this.figure,
    this.note,
    this.actionLabel,
    this.onAction,
    this.semanticLabel,
  });

  final IconData icon;
  final String label;
  final String figure;
  final String? note;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    const white = Colors.white;
    final soft = white.withValues(alpha: .78);
    Widget bloom(double size, double alpha) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            white.withValues(alpha: alpha),
            white.withValues(alpha: 0),
          ],
        ),
      ),
    );

    return Semantics(
      liveRegion: true,
      container: true,
      label: semanticLabel,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [t.palette.hoverDark, t.palette.primaryLight],
          ),
          boxShadow: [
            BoxShadow(
              color: t.palette.primaryLight.withValues(
                alpha: t.isDark ? .30 : .28,
              ),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(top: -70, right: -50, child: bloom(200, .22)),
            Positioned(bottom: -90, left: -40, child: bloom(180, .12)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: white.withValues(alpha: .18),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Icon(icon, size: 17, color: white),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: VfType.small.copyWith(
                            color: soft,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        figure,
                        maxLines: 1,
                        style: VfType.figure.copyWith(
                          color: white,
                          fontSize: 40,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  if (note != null || onAction != null) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: note == null
                              ? const SizedBox.shrink()
                              : Text(
                                  note!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: VfType.bodyStrong.copyWith(
                                    color: soft,
                                    fontSize: 14,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                        ),
                        if (onAction != null && actionLabel != null) ...[
                          const SizedBox(width: 10),
                          _HeroButton(label: actionLabel!, onTap: onAction!),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroButton extends StatelessWidget {
  const _HeroButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(VfSize.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VfSize.radiusPill),
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: VfType.small.copyWith(
                  color: t.palette.primaryLight,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                PhosphorIconsBold.arrowRight,
                size: 14,
                color: t.palette.primaryLight,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
