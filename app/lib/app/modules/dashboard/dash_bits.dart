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

/// The web's `.vf-panel` with a head — title, optional count pill and
/// subtitle, and a trailing action — and a body that runs to the edges.
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
  final String? subtitle;
  final Widget? trailing;

  /// A line under the head's title row (a total and an action).
  final Widget? below;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(VfSize.radiusL),
        border: Border.all(color: t.border),
        boxShadow: t.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  title,
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
                            ],
                          ),
                          if (subtitle != null && subtitle!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              style: VfType.small.copyWith(color: t.muted),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: trailing!,
                        ),
                      ),
                    ],
                  ],
                ),
                ?below,
              ],
            ),
          ),
          child,
          ?footer,
        ],
      ),
    );
  }
}

/// The web's `.vf-count`: a small grey pill with a number.
class DashCount extends StatelessWidget {
  const DashCount(this.count, {super.key});
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: t.surface3,
        borderRadius: BorderRadius.circular(VfSize.radiusPill),
      ),
      child: Text(
        '$count',
        style: VfType.meta.copyWith(
          color: t.text2,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// A ghost link in a panel head: "View reports →".
class DashLink extends StatelessWidget {
  const DashLink({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => VouchFlowButton(
    label: label,
    onPressed: onTap,
    variant: VfButtonVariant.ghost,
    compact: true,
    trailingIcon: PhosphorIconsRegular.arrowRight,
  );
}

/// A quiet line inside a panel ("No activity yet.").
class DashEmpty extends StatelessWidget {
  const DashEmpty(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(text, style: VfType.small.copyWith(color: context.vf.muted)),
  );
}

/// The web's `.app-dash-facts`: label left, value right, hairlines between.
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              border: i == rows.length - 1
                  ? null
                  : Border(bottom: BorderSide(color: t.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Text(
                    rows[i].$1,
                    style: VfType.small.copyWith(
                      color: t.muted,
                      fontWeight: FontWeight.w500,
                    ),
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

/// The web's `.app-bars`: name, count and value over a meter.
class DashBars extends StatelessWidget {
  const DashBars(this.rows, {super.key});

  /// (name, count, value, share 0–1)
  final List<(String, int, String, double)> rows;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final figures = const [FontFeature.tabularFigures()];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    rows[i].$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VfType.small.copyWith(color: t.text2),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${rows[i].$2}',
                  style: VfType.meta.copyWith(
                    color: t.muted,
                    fontFeatures: figures,
                  ),
                ),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 72),
                  child: Text(
                    rows[i].$3,
                    textAlign: TextAlign.right,
                    style: VfType.small.copyWith(
                      color: t.text,
                      fontWeight: FontWeight.w600,
                      fontFeatures: figures,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(VfSize.radiusPill),
              child: SizedBox(
                height: 8,
                child: Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: t.surface3)),
                    FractionallySizedBox(
                      widthFactor: rows[i].$4,
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: t.primary,
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
        ],
      ),
    );
  }
}

/// A tappable row in a panel list (`.app-mini-list li`, `.vf-row`).
class DashRow extends StatelessWidget {
  const DashRow({
    super.key,
    required this.child,
    this.onTap,
    this.last = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool last;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final body = Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: padding,
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: t.border)),
      ),
      child: child,
    );
    return onTap == null
        ? body
        : Material(
            type: MaterialType.transparency,
            child: InkWell(onTap: onTap, child: body),
          );
  }
}
