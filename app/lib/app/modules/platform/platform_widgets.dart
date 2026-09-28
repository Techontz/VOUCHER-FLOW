import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/platform_models.dart';
import '../../widgets/common.dart';
import '../../widgets/vf/vf.dart';

/*
 * Pieces the platform screens share: the web's status tags and palettes,
 * the toolbar select, pagination, fact lists, person rows and the usage
 * meter — each the phone form of the web component of the same job.
 */

/// The interface palettes a company can choose, as the web's PALETTES paints
/// them (sections.tsx) — used for the swatches, the preview and the header.
class PlatformPalette {
  const PlatformPalette(
    this.key,
    this.primary,
    this.hover,
    this.soft,
    this.text,
  );

  final String key;
  final Color primary, hover, soft, text;

  String get label => 'platform.palette.$key'.tr;

  static const all = [
    PlatformPalette(
      'blue',
      Color(0xFF2563EB),
      Color(0xFF1D4ED8),
      Color(0xFFDBEAFE),
      Color(0xFF1D4ED8),
    ),
    PlatformPalette(
      'emerald',
      Color(0xFF047857),
      Color(0xFF065F46),
      Color(0xFFD1FAE5),
      Color(0xFF047857),
    ),
    PlatformPalette(
      'violet',
      Color(0xFF6D28D9),
      Color(0xFF5B21B6),
      Color(0xFFEDE9FE),
      Color(0xFF6D28D9),
    ),
    PlatformPalette(
      'rose',
      Color(0xFFBE123C),
      Color(0xFF9F1239),
      Color(0xFFFFE4E6),
      Color(0xFFBE123C),
    ),
  ];

  static PlatformPalette of(String? key) =>
      all.firstWhere((p) => p.key == key, orElse: () => all.first);
}

/// "#1D4ED8" → Color, or null when it is not a six-digit hex colour.
Color? parseHex(String? value) {
  if (value == null) return null;
  final m = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(value.trim());
  return m == null ? null : Color(int.parse('FF${m.group(1)}', radix: 16));
}

String toHex(Color c) {
  String h(double v) =>
      (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${h(c.r)}${h(c.g)}${h(c.b)}'.toUpperCase();
}

/// The web's STATUS_TAG for a company.
String companyStatusTag(String status) => switch (status) {
  'active' => 'tag-accent',
  'trial' => 'tag-outline',
  'past_due' || 'suspended' => 'tag-accent-2',
  _ => 'tag-neutral',
};

/// A status word, translated when we know it, else the server's own word.
String statusLabel(String status) {
  final key = 'platform.st.$status';
  final t = key.tr;
  return t == key ? status : t;
}

String roleLabel(String? role) {
  if (role == null || role.isEmpty) return '';
  final key = 'platform.role.$role';
  final t = key.tr;
  return t == key ? role : t;
}

String money(double amount, String currency) => Fmt.money(amount, currency);

/// The web's compactMoney: 1.5M, 250K.
String compactMoney(double amount, [String currency = '']) {
  final prefix = currency.isEmpty ? '' : '$currency ';
  if (amount.abs() >= 1000000) {
    return '$prefix${(amount / 1000000).toStringAsFixed(1)}M';
  }
  if (amount.abs() >= 1000) {
    return '$prefix${(amount / 1000).toStringAsFixed(0)}K';
  }
  return currency.isEmpty ? Fmt.plain(amount) : Fmt.money(amount, currency);
}

/// "3 h ago" — the web's relativeTime, in the app's language.
String relativeTime(DateTime? value) {
  if (value == null) return '—';
  final d = DateTime.now().difference(value);
  if (d.inMinutes < 1) return 'platform.time.now'.tr;
  if (d.inMinutes < 60) {
    return 'platform.time.minutes'.trParams({'n': '${d.inMinutes}'});
  }
  if (d.inHours < 24) {
    return 'platform.time.hours'.trParams({'n': '${d.inHours}'});
  }
  if (d.inDays == 1) return 'platform.time.yesterday'.tr;
  if (d.inDays < 7) return 'platform.time.days'.trParams({'n': '${d.inDays}'});
  if (d.inDays < 30) {
    return 'platform.time.weeks'.trParams({'n': '${d.inDays ~/ 7}'});
  }
  return Fmt.date(value);
}

String errorText(Object error) => '$error';

/// A label-less select in the web's toolbar `.input` style.
class PlatformSelect<T> extends StatelessWidget {
  const PlatformSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.semanticLabel,
  });

  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Semantics(
      label: semanticLabel,
      child: DropdownButtonFormField<T>(
        key: ValueKey('select-$value'),
        initialValue: items.any((e) => e.$1 == value) ? value : null,
        isExpanded: true,
        onChanged: (v) {
          if (v != null || null is T) onChanged(v as T);
        },
        icon: Icon(PhosphorIconsRegular.caretDown, size: 16, color: t.muted),
        dropdownColor: t.surface,
        borderRadius: BorderRadius.circular(VfSize.radiusL),
        style: VfType.body.copyWith(color: t.text),
        decoration: InputDecoration(filled: true, fillColor: t.inputBg),
        items: [
          for (final item in items)
            DropdownMenuItem<T>(
              value: item.$1,
              child: Text(
                item.$2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

/// The web's Pagination: "Showing 65 · Page 1 of 4" with Back / Next.
class PlatformPager extends StatelessWidget {
  const PlatformPager({
    super.key,
    required this.page,
    required this.lastPage,
    required this.total,
    required this.onChanged,
  });

  final int page, lastPage, total;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (lastPage <= 1) return const SizedBox.shrink();
    final t = context.vf;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          Text(
            '${'platform.showing'.tr} $total · ${'platform.page'.tr} $page ${'platform.of'.tr} $lastPage',
            style: VfType.small.copyWith(color: t.muted),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              VouchFlowButton(
                label: 'platform.back'.tr,
                icon: PhosphorIconsRegular.caretLeft,
                variant: VfButtonVariant.secondary,
                compact: true,
                onPressed: page <= 1 ? null : () => onChanged(page - 1),
              ),
              const SizedBox(width: 8),
              VouchFlowButton(
                label: 'platform.next'.tr,
                trailingIcon: PhosphorIconsRegular.caretRight,
                variant: VfButtonVariant.secondary,
                compact: true,
                onPressed: page >= lastPage ? null : () => onChanged(page + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A `.vf-panel` with no head, holding rows separated by hairlines.
class PlatformRowsPanel extends StatelessWidget {
  const PlatformRowsPanel({
    super.key,
    required this.children,
    this.header,
    this.footer,
  });

  final List<Widget> children;
  final Widget? header;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return VouchFlowCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null)
            Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: t.border)),
              ),
              child: header,
            ),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: t.border),
            children[i],
          ],
          if (footer != null)
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: t.border)),
              ),
              child: footer,
            ),
        ],
      ),
    );
  }
}

/// The web's Facts list (`.app-co-facts`): label over value, "Not set" when blank.
class PlatformFacts extends StatelessWidget {
  const PlatformFacts({super.key, required this.rows});

  final List<(String, Object?)> rows;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return LayoutBuilder(
      builder: (context, c) {
        final two = c.maxWidth >= 520;
        final w = two ? (c.maxWidth - 16) / 2 : c.maxWidth;
        return Wrap(
          spacing: 16,
          children: [
            for (final (label, value) in rows)
              SizedBox(
                width: w,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: VfType.meta.copyWith(
                          color: t.muted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (value is Widget)
                        value
                      else if (value == null || '$value'.isEmpty)
                        Text(
                          'platform.notSet'.tr,
                          style: VfType.body.copyWith(color: t.faint),
                        )
                      else
                        Text(
                          '$value',
                          style: VfType.body.copyWith(color: t.text),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The web's PersonCell: initials avatar, name and a quieter line.
class PlatformPerson extends StatelessWidget {
  const PlatformPerson({
    super.key,
    required this.name,
    this.sub,
    this.initials,
    this.size = 36,
  });

  final String name;
  final String? sub;
  final String? initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Row(
      children: [
        VouchFlowAvatar(initials: initials ?? initialsOf(name), size: size),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: VfType.bodyStrong.copyWith(
                  color: t.text,
                  fontSize: 14.5,
                ),
              ),
              if (sub != null && sub!.isNotEmpty)
                Text(
                  sub!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VfType.meta.copyWith(color: t.muted),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The web's Meter (`.vf-meter`): a thin bar, red once the limit is exceeded.
class PlatformMeter extends StatelessWidget {
  const PlatformMeter({
    super.key,
    required this.percent,
    this.exceeded = false,
  });

  final double? percent;
  final bool exceeded;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final p = ((percent ?? 0).clamp(2, 100)) / 100;
    return Semantics(
      value: '${(percent ?? 0).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(VfSize.radiusPill),
        child: Container(
          height: 8,
          color: t.surface3,
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: p,
            child: Container(color: exceeded ? t.dangerStrong : t.primary),
          ),
        ),
      ),
    );
  }
}

/// KPI tiles two to a row on a phone, four on a tablet (`.vf-kpis`).
class PlatformKpiGrid extends StatelessWidget {
  const PlatformKpiGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 720 ? 4 : (c.maxWidth >= 300 ? 2 : 1);
        const gap = VfSize.gap;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children) SizedBox(width: w, child: child),
          ],
        );
      },
    );
  }
}

/// Two columns on a tablet, stacked on a phone (`.app-co-grid`).
class PlatformTwoUp extends StatelessWidget {
  const PlatformTwoUp({super.key, required this.left, required this.right});

  final Widget left, right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              left,
              const SizedBox(height: VfSize.gap),
              right,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: VfSize.gap),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

/// A caption/value pair laid out on one line inside a list row.
class PlatformMetaLine extends StatelessWidget {
  const PlatformMetaLine({
    super.key,
    required this.label,
    required this.value,
    this.valueStyle,
  });

  final String label;
  final String value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: VfType.meta.copyWith(color: t.muted, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style:
                  valueStyle ??
                  VfType.small.copyWith(
                    color: t.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The count shown at the end of a toolbar ("65 vouchers").
class PlatformCount extends StatelessWidget {
  const PlatformCount(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: VfType.small.copyWith(
      color: context.vf.muted,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}

/// A panel's padded loading / error body.
Widget platformPanelState({
  required bool loading,
  String? error,
  VoidCallback? onRetry,
  int rows = 5,
}) {
  if (error != null) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: VouchFlowErrorState(
        message: error,
        onRetry: onRetry,
        retryLabel: 'action.retry'.tr,
      ),
    );
  }
  return Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
    child: VouchFlowLoadingState(rows: rows, rowHeight: 64),
  );
}
