import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/platform_models.dart';
import '../../data/services/platform_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/vf/vf.dart';
import 'platform_widgets.dart';

/*
 * The tabs of the platform's company view (web: platform/companies/[id]/
 * sections.tsx). Every number and row comes from the platform API for this
 * one company — nothing is invented. Tables become cards on a phone.
 */

typedef OpenTab = void Function(String tab, [Map<String, String>? filter]);

String _usageLine(UsageMetric? m) {
  if (m == null) return '';
  final used = NumberFormat.decimalPattern('en_US').format(m.used);
  if (m.unlimited) {
    return 'platform.usage.unlimited'
        .trParams({'used': used, 'unit': m.unit})
        .replaceAll('  ', ' ');
  }
  final limit = NumberFormat.decimalPattern('en_US').format(m.limit ?? 0);
  return 'platform.usage.of'.trParams({
    'used': used,
    'limit': limit,
    'unit': m.unit,
  }).trim();
}

const _swMonths = [
  'Jan',
  'Feb',
  'Mac',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Ago',
  'Sep',
  'Okt',
  'Nov',
  'Des',
];

/// The short month name, as the web prints it for the locale.
String _monthShort(MonthlyPoint m) {
  final d = m.date;
  if (d == null) return m.month;
  return Get.locale?.languageCode == 'sw'
      ? _swMonths[d.month - 1]
      : DateFormat('MMM').format(d);
}

Color _toneColor(VfTokens t, String tone) => switch (tone) {
  'info' => t.infoStrong,
  'ok' => t.successStrong,
  'warn' => t.warningStrong,
  'bad' => t.dangerStrong,
  _ => t.neutralStrong,
};

/* ───────────────────────────────────────────────────────────── overview ── */

class OverviewTab extends StatelessWidget {
  const OverviewTab({
    super.key,
    required this.detail,
    required this.overview,
    required this.onOpen,
  });

  final CompanyDetail detail;
  final CompanyOverview overview;
  final OpenTab onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final c = detail.company;
    final o = overview;
    final cur = o.currency;
    final pipeline = <(String, int, String)>[
      ('platform.vs.draft'.tr, o.v('draft'), 'neutral'),
      ('platform.vs.in_review'.tr, o.v('in_review'), 'info'),
      ('platform.vs.changes_requested'.tr, o.v('changes_requested'), 'warn'),
      ('platform.vs.awaiting_payment'.tr, o.v('approved'), 'ok'),
      ('platform.vs.paid'.tr, o.v('paid'), 'ok'),
      ('platform.vs.rejected'.tr, o.v('rejected'), 'bad'),
      ('platform.vs.cancelled'.tr, o.v('cancelled'), 'neutral'),
    ];
    final total = o.v('total');

    final pipelineCard = VouchFlowCard(
      title: 'platform.ov.pipeline'.tr,
      subtitle: 'platform.ov.pipelineSub'.tr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (label, count, tone) in pipeline)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: VfType.small.copyWith(color: t.text2),
                        ),
                      ),
                      Text(
                        '$count',
                        style: VfType.small.copyWith(
                          color: t.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(VfSize.radiusPill),
                    child: Container(
                      height: 8,
                      color: t.surface3,
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: total == 0
                            ? 0
                            : math
                                  .max(count > 0 ? .03 : 0, count / total)
                                  .clamp(0, 1)
                                  .toDouble(),
                        child: Container(color: _toneColor(t, tone)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (o.stages.isNotEmpty) ...[
            const SizedBox(height: 6),
            VouchFlowEyebrow('platform.ov.byStep'.tr),
            const SizedBox(height: 8),
            for (final s in o.stages)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: t.primarySoftStrong,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        s.position > 0 ? '${s.position}' : '—',
                        style: VfType.meta.copyWith(
                          color: t.primaryText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.name,
                            style: VfType.small.copyWith(
                              color: t.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (s.role != null)
                            Text(
                              roleLabel(s.role),
                              style: VfType.meta.copyWith(color: t.muted),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${s.count} · ${money(s.value, cur)}',
                        textAlign: TextAlign.right,
                        style: VfType.small.copyWith(
                          color: t.text,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: VouchFlowButton(
              label: 'platform.ov.openVouchers'.tr,
              trailingIcon: PhosphorIconsRegular.arrowRight,
              variant: VfButtonVariant.ghost,
              compact: true,
              onPressed: () => onOpen('vouchers'),
            ),
          ),
        ],
      ),
    );

    final maxMonth = o.monthly.fold<double>(1, (m, x) => math.max(m, x.value));
    final monthlyCard = VouchFlowCard(
      title: 'platform.ov.monthly'.tr,
      subtitle: 'platform.ov.monthlySub'.tr,
      child: SizedBox(
        height: 180,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final m in o.monthly)
              Expanded(
                child: Tooltip(
                  message: '${m.count} · ${money(m.value, cur)}',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            m.value > 0 ? compactMoney(m.value) : '',
                            style: VfType.meta.copyWith(
                              color: t.text2,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Flexible(
                          child: FractionallySizedBox(
                            heightFactor: math.max(
                              m.value > 0 ? .04 : .01,
                              m.value / maxMonth,
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: t.primary,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _monthShort(m),
                          style: VfType.meta.copyWith(
                            color: t.muted,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    final info = VouchFlowCard(
      title: 'platform.ov.info'.tr,
      child: PlatformFacts(
        rows: [
          ('platform.f.legalName'.tr, c.legalName),
          ('platform.f.tradingName'.tr, c.tradingName),
          ('platform.f.email'.tr, c.email),
          ('platform.f.phone'.tr, c.phone),
          ('platform.f.altPhone'.tr, c.alternativePhone),
          ('platform.f.website'.tr, c.website),
          ('platform.f.address'.tr, c.address),
          ('platform.f.postal'.tr, c.postalAddress),
          ('platform.f.city'.tr, c.city),
          ('platform.f.region'.tr, c.region),
          ('platform.f.country'.tr, c.country),
          ('platform.f.tin'.tr, c.tin),
          ('platform.f.regNo'.tr, c.registrationNumber),
          ('platform.f.licence'.tr, c.businessLicenseNumber),
          (
            'platform.f.contact'.tr,
            [
              c.contactPerson,
              c.contactEmail,
              c.contactPhone,
            ].whereType<String>().join(' · '),
          ),
          (
            'platform.f.locale'.tr,
            [
              c.currency,
              c.locale?.toUpperCase(),
              c.timezone,
            ].whereType<String>().join(' · '),
          ),
          ('platform.f.joinedPlatform'.tr, Fmt.date(c.createdAt)),
        ],
      ),
    );

    final roles = o.byRole.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VouchFlowCard(
          title: 'platform.ov.owners'.tr,
          subtitle: 'platform.ov.ownersSub'.tr,
          padding: EdgeInsets.zero,
          child: detail.admins.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'platform.ov.noAdmin'.tr,
                    style: VfType.small.copyWith(color: t.muted),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < detail.admins.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: t.border),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: PlatformPerson(
                                name: detail.admins[i].name,
                                sub: detail.admins[i].email,
                                initials: detail.admins[i].initials,
                              ),
                            ),
                            const SizedBox(width: 8),
                            VouchFlowStatusBadge(
                              label: statusLabel(detail.admins[i].status),
                              tag: detail.admins[i].status == 'active'
                                  ? 'tag-accent'
                                  : 'tag-neutral',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: VfSize.gap),
        VouchFlowCard(
          title: 'platform.ov.byRole'.tr,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < roles.length; i++) ...[
                if (i > 0) Divider(height: 1, color: t.border),
                InkWell(
                  onTap: () => onOpen('users', {'role': roles[i].key}),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              roleLabel(roles[i].key),
                              style: VfType.body.copyWith(
                                color: t.primaryText,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Text(
                            '${roles[i].value}',
                            style: VfType.bodyStrong.copyWith(color: t.text),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            PhosphorIconsRegular.caretRight,
                            size: 14,
                            color: t.faint,
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
        const SizedBox(height: VfSize.gap),
        VouchFlowCard(
          title: 'platform.ov.bank'.tr,
          child: PlatformFacts(
            rows: [
              ('platform.f.bank'.tr, c.bankName),
              ('platform.f.branch'.tr, c.bankBranch),
              ('platform.f.accountName'.tr, c.bankAccountName),
              ('platform.f.accountNumber'.tr, c.bankAccountNumber),
              ('platform.f.swift'.tr, c.swiftCode),
            ],
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlatformKpiGrid(
          children: [
            VouchFlowStatCard(
              label: 'platform.ov.people'.tr,
              value: '${o.peopleTotal}',
              sub: 'platform.ov.peopleSub'.trParams({
                'active': '${o.peopleActive}',
                'usage': _usageLine(detail.metric('users')),
              }),
              icon: PhosphorIconsRegular.usersThree,
              tone: VfTone.info,
            ),
            VouchFlowStatCard(
              label: 'platform.ov.departments'.tr,
              value: '${o.departments}',
              sub: _usageLine(detail.metric('departments')),
              icon: PhosphorIconsRegular.treeStructure,
              tone: VfTone.info,
            ),
            VouchFlowStatCard(
              label: 'platform.ov.vouchers'.tr,
              value: '$total',
              sub: 'platform.ov.vouchersSub'.trParams({
                'review': '${o.v('in_review')}',
                'paid': '${o.v('paid')}',
              }),
              icon: PhosphorIconsRegular.receipt,
              tone: VfTone.info,
            ),
            VouchFlowStatCard(
              label: 'platform.ov.totalValue'.tr,
              value: money(o.value('total'), cur),
              sub: 'platform.ov.totalValueSub'.tr,
              icon: PhosphorIconsRegular.coins,
              tone: VfTone.info,
            ),
            VouchFlowStatCard(
              label: 'platform.ov.approvedValue'.tr,
              value: money(o.value('approved_including_paid'), cur),
              sub: 'platform.ov.approvedValueSub'.trParams({
                'n': '${o.v('approved') + o.v('paid')}',
              }),
              icon: PhosphorIconsRegular.sealCheck,
              tone: VfTone.ok,
            ),
            VouchFlowStatCard(
              label: 'platform.ov.paidOut'.tr,
              value: money(o.value('paid'), cur),
              sub: 'platform.ov.paidOutSub'.trParams({'n': '${o.v('paid')}'}),
              icon: PhosphorIconsRegular.handCoins,
              tone: VfTone.ok,
            ),
            VouchFlowStatCard(
              label: 'platform.ov.pendingPayment'.tr,
              value: money(o.pendingValue, cur),
              sub: 'platform.ov.pendingPaymentSub'.trParams({
                'n': '${o.pendingCount}',
              }),
              icon: PhosphorIconsRegular.hourglass,
              tone: VfTone.warn,
            ),
            VouchFlowStatCard(
              label: 'platform.ov.inReview'.tr,
              value: money(o.value('in_review'), cur),
              sub: 'platform.ov.inReviewSub'.trParams({
                'n': '${o.v('in_review')}',
              }),
              icon: PhosphorIconsRegular.clockCountdown,
              tone: VfTone.info,
            ),
          ],
        ),
        const SizedBox(height: VfSize.gap),
        PlatformTwoUp(left: pipelineCard, right: monthlyCard),
        const SizedBox(height: VfSize.gap),
        PlatformTwoUp(left: info, right: side),
      ],
    );
  }
}

/* ───────────────────────────────────────────────────── branding & palette ── */

class BrandingTab extends StatelessWidget {
  const BrandingTab({
    super.key,
    required this.company,
    required this.onEdit,
    this.voucherDesign,
  });

  final PlatformCompany company;
  final VoidCallback onEdit;
  final Widget? voucherDesign;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final c = company;
    final palette = PlatformPalette.of(c.colorTheme);
    final customPalette = c.colorTheme != 'blue';
    final hasDocBranding =
        c.logoUrl != null ||
        c.logoMarkUrl != null ||
        c.voucherHeaderText != null ||
        c.secondaryColor != null ||
        c.accentColor != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VouchFlowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VouchFlowEyebrow('platform.br.selected'.tr),
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    palette.label,
                    style: VfType.sectionTitle.copyWith(color: t.text),
                  ),
                  if (!customPalette)
                    VouchFlowStatusBadge(label: 'platform.br.default'.tr),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'platform.br.intro'.trParams({'name': c.name}),
                style: VfType.small.copyWith(color: t.text2),
              ),
              if (!customPalette && !hasDocBranding) ...[
                const SizedBox(height: 12),
                VouchFlowAlert(message: 'platform.br.noCustom'.tr),
              ],
              const SizedBox(height: 14),
              VouchFlowButton(
                label: 'platform.co.editBranding'.tr,
                icon: PhosphorIconsRegular.paintBrush,
                variant: VfButtonVariant.secondary,
                onPressed: onEdit,
              ),
            ],
          ),
        ),
        if (voucherDesign != null) ...[
          const SizedBox(height: VfSize.gap),
          voucherDesign!,
        ],
        const SizedBox(height: VfSize.gap),
        VouchFlowCard(
          title: 'platform.br.preview'.tr,
          subtitle: 'platform.br.previewSub'.trParams({
            'name': c.name,
            'theme': c.theme == 'dark'
                ? 'platform.br.dark'.tr.toLowerCase()
                : 'platform.br.light'.tr.toLowerCase(),
          }),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InterfacePreview(company: c),
              const SizedBox(height: 10),
              Text(
                'platform.br.caption'.tr,
                style: VfType.meta.copyWith(color: t.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: VfSize.gap),
        VouchFlowCard(
          title: 'platform.br.saved'.tr,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, box) {
                  final cols = box.maxWidth >= 520 ? 2 : 1;
                  final w = (box.maxWidth - 12 * (cols - 1)) / cols;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: w,
                        child: _Swatch(
                          label: 'platform.co.interfacePalette'.tr,
                          colour: palette.primary,
                          code:
                              '${c.colorTheme} · ${toHex(palette.primary).toLowerCase()}',
                        ),
                      ),
                      SizedBox(
                        width: w,
                        child: _Swatch(
                          label: 'platform.br.primaryDocs'.tr,
                          colour: parseHex(c.primaryColor),
                          code: c.primaryColor,
                        ),
                      ),
                      SizedBox(
                        width: w,
                        child: _Swatch(
                          label: 'platform.co.secondaryColour'.tr,
                          colour: parseHex(c.secondaryColor),
                          code: c.secondaryColor,
                        ),
                      ),
                      SizedBox(
                        width: w,
                        child: _Swatch(
                          label: 'platform.co.accentColour'.tr,
                          colour: parseHex(c.accentColor),
                          code: c.accentColor,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              PlatformFacts(
                rows: [
                  (
                    'platform.br.appearance'.tr,
                    c.theme == 'dark'
                        ? 'platform.br.dark'.tr
                        : 'platform.br.light'.tr,
                  ),
                  ('platform.br.nameUi'.tr, c.name),
                  ('platform.br.nameDocs'.tr, c.legalName ?? c.name),
                  ('platform.co.headerText'.tr, c.voucherHeaderText),
                  ('platform.co.footerText'.tr, c.voucherFooterText),
                  (
                    'platform.br.fullLogo'.tr,
                    c.logoUrl == null
                        ? null
                        : _Logo(url: c.logoUrl!, height: 56),
                  ),
                  (
                    'platform.br.logoMark'.tr,
                    c.logoMarkUrl == null
                        ? null
                        : _Logo(url: c.logoMarkUrl!, height: 48, width: 48),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.url, required this.height, this.width});

  final String url;
  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      height: height,
      width: width,
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(VfSize.radiusM),
        border: Border.all(color: t.border),
      ),
      child: Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            Icon(PhosphorIconsRegular.imageBroken, color: t.faint),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.label,
    required this.colour,
    required this.code,
  });

  final String label;
  final Color? colour;
  final String? code;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colour ?? Colors.transparent,
            borderRadius: BorderRadius.circular(VfSize.radiusM),
            border: Border.all(
              color: colour == null ? t.borderStrong : Colors.transparent,
            ),
          ),
          child: colour == null
              ? Icon(PhosphorIconsRegular.minus, size: 14, color: t.faint)
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: VfType.small.copyWith(
                  color: t.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                code ?? 'platform.notSet'.tr,
                style: VfType.meta.copyWith(
                  color: t.muted,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A schematic of the company's workspace in its palette and appearance
/// (the web's `.app-co-preview`).
class InterfacePreview extends StatelessWidget {
  const InterfacePreview({super.key, required this.company});

  final PlatformCompany company;

  @override
  Widget build(BuildContext context) {
    final c = company;
    final accent = VfAccentPalette.of(c.colorTheme);
    final p = c.theme == 'dark'
        ? VfTokens.dark(accent)
        : VfTokens.light(accent);
    final nav = [
      (PhosphorIconsRegular.squaresFour, 'platform.br.dashboard'.tr, true),
      (PhosphorIconsRegular.receipt, 'platform.br.vouchers'.tr, false),
      (PhosphorIconsRegular.listChecks, 'platform.br.approvals'.tr, false),
      (PhosphorIconsRegular.chartLine, 'platform.br.reports'.tr, false),
    ];
    Widget badge(String label, String tag) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: VfStatus.background(tag, p.brightness),
        borderRadius: BorderRadius.circular(VfSize.radiusPill),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: VfType.meta.copyWith(
          fontSize: 11.5,
          color: VfStatus.foreground(tag, p.brightness),
        ),
      ),
    );
    Widget row(String number, String label, String tag) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Flexible(
            flex: 4,
            child: Text(
              number,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: VfType.meta.copyWith(
                fontSize: 11.5,
                color: p.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Spacer(),
          Flexible(
            flex: 3,
            child: Align(
              alignment: Alignment.centerRight,
              child: badge(label, tag),
            ),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, box) {
        final sideW = box.maxWidth < 360 ? 104.0 : 132.0;
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(VfSize.radiusL),
            border: Border.all(color: p.borderStrong),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: sideW,
                  color: p.drawer,
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: c.logoMarkUrl != null
                                  ? Colors.white
                                  : p.primary,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            padding: c.logoMarkUrl != null
                                ? const EdgeInsets.all(2)
                                : null,
                            child: c.logoMarkUrl != null
                                ? Image.network(
                                    c.logoMarkUrl!,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, _, _) =>
                                        const SizedBox.shrink(),
                                  )
                                : Text(
                                    c.displayInitials,
                                    style: VfType.meta.copyWith(
                                      fontSize: 11.5,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: VfType.meta.copyWith(
                                fontSize: 11.5,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      for (final (icon, label, active) in nav)
                        Container(
                          margin: const EdgeInsets.only(bottom: 3),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: active ? p.primary : Colors.transparent,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                icon,
                                size: 12,
                                color: active ? Colors.white : p.chromeText,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: VfType.meta.copyWith(
                                    fontSize: 11.5,
                                    color: active ? Colors.white : p.chromeText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    color: p.background,
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'platform.br.register'.tr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: VfType.meta.copyWith(
                                  fontSize: 12,
                                  color: p.text,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: p.primary,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      PhosphorIconsRegular.plus,
                                      size: 10,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 2),
                                    Flexible(
                                      child: Text(
                                        'platform.br.newVoucher'.tr,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: VfType.meta.copyWith(
                                          fontSize: 11.5,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final (label, active) in [
                              ('platform.br.all'.tr, true),
                              ('platform.br.pending'.tr, false),
                              ('platform.br.paid'.tr, false),
                            ])
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: active ? p.primary : p.surface,
                                  borderRadius: BorderRadius.circular(
                                    VfSize.radiusPill,
                                  ),
                                  border: Border.all(
                                    color: active ? p.primary : p.border,
                                  ),
                                ),
                                child: Text(
                                  label,
                                  style: VfType.meta.copyWith(
                                    fontSize: 11.5,
                                    color: active ? Colors.white : p.text2,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: p.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: p.border),
                          ),
                          child: Column(
                            children: [
                              row(
                                'PV-000142',
                                'platform.br.inReview'.tr,
                                'tag-info',
                              ),
                              row(
                                'PV-000141',
                                'platform.br.paid'.tr,
                                'tag-accent',
                              ),
                              row(
                                'PC-000087',
                                'platform.br.changes'.tr,
                                'tag-warn',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'platform.br.viewAll'.tr,
                          style: VfType.meta.copyWith(
                            fontSize: 11.5,
                            color: p.primaryText,
                            fontWeight: FontWeight.w600,
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
      },
    );
  }
}

/* ─────────────────────────────────────────────────────────────── users ── */

class UsersTab extends StatefulWidget {
  const UsersTab({
    super.key,
    required this.companyId,
    required this.departments,
    required this.roles,
    this.initial,
  });

  final int companyId;
  final List<DepartmentRow> departments;
  final List<String> roles;
  final Map<String, String>? initial;

  @override
  State<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<UsersTab> {
  late final Map<String, String> _f = {
    'q': '',
    'role': '',
    'status': '',
    'department_id': '',
    ...?widget.initial,
  };
  late final _qCtrl = TextEditingController(text: _f['q']);
  int _page = 1;
  PlatformPage<PlatformUser>? _result;
  String? _error;
  Timer? _debounce;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _qCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() => _error = null);
    try {
      final r = await PlatformRepository.to.companyUsers(
        widget.companyId,
        _f,
        page: _page,
      );
      if (mounted && seq == _seq) setState(() => _result = r);
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _error = errorText(e));
    }
  }

  void _set(String k, String v) {
    setState(() {
      _f[k] = v;
      _page = 1;
    });
    if (k == 'q') {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 250), _load);
    } else {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final r = _result;
    final rows = r?.items ?? const <PlatformUser>[];
    return VouchFlowCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                VouchFlowSearchField(
                  placeholder: 'platform.u.search'.tr,
                  controller: _qCtrl,
                  onChanged: (v) => _set('q', v),
                ),
                const SizedBox(height: 10),
                PlatformSelect<String>(
                  value: _f['role']!,
                  items: [
                    ('', 'platform.allRoles'.tr),
                    for (final r in widget.roles) (r, roleLabel(r)),
                  ],
                  onChanged: (v) => _set('role', v),
                ),
                const SizedBox(height: 10),
                PlatformSelect<String>(
                  value: _f['status']!,
                  items: [
                    ('', 'platform.allStatuses'.tr),
                    for (final s in const ['active', 'invited', 'suspended'])
                      (s, statusLabel(s)),
                  ],
                  onChanged: (v) => _set('status', v),
                ),
                const SizedBox(height: 10),
                PlatformSelect<String>(
                  value: _f['department_id']!,
                  items: [
                    ('', 'platform.allDepartments'.tr),
                    for (final d in widget.departments) ('${d.id}', d.name),
                  ],
                  onChanged: (v) => _set('department_id', v),
                ),
                const SizedBox(height: 10),
                PlatformCount(
                  'platform.u.count'.trParams({'n': '${r?.total ?? 0}'}),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: t.border),
          if (_error != null || r == null)
            platformPanelState(
              loading: r == null,
              error: _error,
              onRetry: _load,
            )
          else if (rows.isEmpty)
            VouchFlowEmptyState(
              icon: PhosphorIconsRegular.usersThree,
              title: 'platform.u.empty'.tr,
            )
          else ...[
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, color: t.border),
              _row(t, rows[i]),
            ],
            if (r.lastPage > 1) Divider(height: 1, color: t.border),
            PlatformPager(
              page: r.page,
              lastPage: r.lastPage,
              total: r.total,
              onChanged: (p) {
                setState(() => _page = p);
                _load();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(VfTokens t, PlatformUser u) {
    final tag = u.status == 'active'
        ? 'tag-accent'
        : (u.status == 'suspended' ? 'tag-accent-2' : 'tag-neutral');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: PlatformPerson(
                  name: u.name,
                  sub: u.email,
                  initials: u.displayInitials,
                ),
              ),
              const SizedBox(width: 8),
              VouchFlowStatusBadge(label: statusLabel(u.status), tag: tag),
            ],
          ),
          const SizedBox(height: 8),
          PlatformMetaLine(
            label: 'platform.users.role'.tr,
            value: [
              u.roleLabel,
              if (u.jobTitle != null) u.jobTitle!,
            ].join(' · '),
          ),
          PlatformMetaLine(
            label: 'platform.u.department'.tr,
            value: u.departmentName ?? '—',
          ),
          PlatformMetaLine(label: 'platform.u.phone'.tr, value: u.phone ?? '—'),
          PlatformMetaLine(
            label: 'platform.vouchers'.tr,
            value: '${u.voucherCount}',
          ),
          PlatformMetaLine(
            label: 'platform.u.lastSignIn'.tr,
            value: u.lastLoginAt == null
                ? 'platform.never'.tr
                : relativeTime(u.lastLoginAt),
          ),
          PlatformMetaLine(
            label: 'platform.joined'.tr,
            value: Fmt.date(u.joinedAt),
          ),
        ],
      ),
    );
  }
}

/* ───────────────────────────────────────────────────────── departments ── */

class DepartmentsTab extends StatelessWidget {
  const DepartmentsTab({
    super.key,
    required this.departments,
    required this.currency,
    required this.onOpen,
  });

  final List<DepartmentRow>? departments;
  final String currency;
  final OpenTab onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final list = departments;
    if (list == null) {
      return const VouchFlowLoadingState(rows: 4, rowHeight: 140);
    }
    if (list.isEmpty) {
      return VouchFlowCard(
        child: VouchFlowEmptyState(
          icon: PhosphorIconsRegular.treeStructure,
          title: 'platform.d.empty'.tr,
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final cols = box.maxWidth >= 720 ? 2 : 1;
        final w = (box.maxWidth - VfSize.gap * (cols - 1)) / cols;
        return Wrap(
          spacing: VfSize.gap,
          runSpacing: VfSize.gap,
          children: [
            for (final d in list)
              SizedBox(
                width: w,
                child: VouchFlowCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d.name,
                                  style: VfType.cardTitle.copyWith(
                                    color: t.text,
                                  ),
                                ),
                                Text(
                                  [
                                        d.code,
                                        d.costCentre,
                                      ].whereType<String>().join(' · ').isEmpty
                                      ? '—'
                                      : [
                                          d.code,
                                          d.costCentre,
                                        ].whereType<String>().join(' · '),
                                  style: VfType.meta.copyWith(color: t.muted),
                                ),
                              ],
                            ),
                          ),
                          VouchFlowStatusBadge(
                            label: d.isActive
                                ? 'platform.st.active'.tr
                                : 'platform.st.inactive'.tr,
                            tag: d.isActive ? 'tag-accent' : 'tag-neutral',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'platform.d.hod'.tr,
                        style: VfType.meta.copyWith(
                          color: t.muted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (d.hod != null)
                        PlatformPerson(
                          name: d.hod!.name,
                          sub: d.hod!.email,
                          size: 32,
                        )
                      else
                        Align(
                          alignment: Alignment.centerLeft,
                          child: VouchFlowStatusBadge(
                            label: 'platform.d.noHod'.tr,
                            tag: 'tag-accent-2',
                          ),
                        ),
                      const SizedBox(height: 10),
                      PlatformMetaLine(
                        label: 'platform.d.manager'.tr,
                        value: d.manager?.name ?? '—',
                      ),
                      PlatformMetaLine(
                        label: 'platform.d.people'.tr,
                        value: '${d.usersCount}',
                      ),
                      PlatformMetaLine(
                        label: 'platform.d.vouchers'.tr,
                        value: '${d.vouchersCount}',
                      ),
                      PlatformMetaLine(
                        label: 'platform.d.approvedValue'.tr,
                        value: money(d.approvedValue, currency),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: VouchFlowButton(
                              label: 'platform.d.people'.tr,
                              icon: PhosphorIconsRegular.usersThree,
                              variant: VfButtonVariant.secondary,
                              compact: true,
                              onPressed: () =>
                                  onOpen('users', {'department_id': '${d.id}'}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: VouchFlowButton(
                              label: 'platform.d.vouchers'.tr,
                              icon: PhosphorIconsRegular.receipt,
                              variant: VfButtonVariant.secondary,
                              compact: true,
                              onPressed: () => onOpen('vouchers', {
                                'department_id': '${d.id}',
                              }),
                            ),
                          ),
                        ],
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

/* ───────────────────────────────────────────────────────────── workflow ── */

class WorkflowTab extends StatefulWidget {
  const WorkflowTab({super.key, required this.companyId});

  final int companyId;

  @override
  State<WorkflowTab> createState() => _WorkflowTabState();
}

class _WorkflowTabState extends State<WorkflowTab> {
  CompanyWorkflows? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await PlatformRepository.to.workflows(widget.companyId);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  String _assignee(WorkflowStepInfo s) {
    if (s.isRequestStep) return 'platform.w.requester'.tr;
    if (s.assignedUserName != null) {
      return 'platform.w.named'.trParams({'name': s.assignedUserName!});
    }
    if (s.role == 'hod') return 'platform.w.eachHod'.tr;
    if (s.role == 'manager') return 'platform.w.eachManager'.tr;
    return 'platform.w.everyone'.trParams({'role': s.roleLabel});
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    if (_error != null) {
      return VouchFlowErrorState(
        message: _error!,
        onRetry: _load,
        retryLabel: 'action.retry'.tr,
      );
    }
    final d = _data;
    if (d == null) return const VouchFlowLoadingState(rows: 3, rowHeight: 160);
    if (d.workflows.isEmpty) {
      return VouchFlowCard(
        child: VouchFlowEmptyState(
          icon: PhosphorIconsRegular.flowArrow,
          title: 'platform.w.empty'.tr,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final wf in d.workflows) ...[
          VouchFlowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      wf.name,
                      style: VfType.cardTitle.copyWith(color: t.text),
                    ),
                    if (wf.isDefault)
                      VouchFlowStatusBadge(
                        label: 'platform.w.default'.tr,
                        tag: 'tag-info',
                      ),
                    VouchFlowStatusBadge(
                      label: wf.isActive
                          ? 'platform.st.active'.tr
                          : 'platform.st.inactive'.tr,
                      tag: wf.isActive ? 'tag-accent' : 'tag-neutral',
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'platform.w.meta'.trParams({
                    'applies': wf.voucherTypeName != null
                        ? 'platform.w.appliesTo'.trParams({
                            'name': wf.voucherTypeName!,
                          })
                        : 'platform.w.appliesAll'.tr,
                    'v': '${wf.version}',
                    'n': '${wf.vouchersCount}',
                  }),
                  style: VfType.small.copyWith(color: t.text2),
                ),
                if (wf.description != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    wf.description!,
                    style: VfType.small.copyWith(color: t.muted),
                  ),
                ],
                const SizedBox(height: 12),
                for (var i = 0; i < wf.steps.length; i++)
                  _step(t, wf.steps[i], last: i == wf.steps.length - 1),
              ],
            ),
          ),
          const SizedBox(height: VfSize.gap),
        ],
        if (d.hasRouting) _routing(t, d),
      ],
    );
  }

  Widget _step(VfTokens t, WorkflowStepInfo s, {required bool last}) {
    final caps = [
      if (s.canSign) 'platform.w.sign'.tr,
      if (s.canApprove) 'platform.w.approve'.tr,
      if (s.canReject) 'platform.w.reject'.tr,
      if (s.canRequestChanges) 'platform.w.requestChanges'.tr,
      if (s.canPay) 'platform.w.pay'.tr,
    ];
    final range = [
      if (s.minAmount != null)
        'platform.w.from'.trParams({'v': compactMoney(s.minAmount!)}),
      if (s.maxAmount != null)
        'platform.w.upTo'.trParams({'v': compactMoney(s.maxAmount!)}),
    ].join(' ');
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${s.position}',
                  style: VfType.meta.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!last) Expanded(child: Container(width: 2, color: t.border)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 14, top: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.label ?? s.name,
                    style: VfType.bodyStrong.copyWith(color: t.text),
                  ),
                  Text(
                    _assignee(s),
                    style: VfType.small.copyWith(color: t.text2),
                  ),
                  if (caps.isNotEmpty ||
                      s.requiresSignature ||
                      range.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final c in caps) VouchFlowStatusBadge(label: c),
                        if (s.requiresSignature)
                          VouchFlowStatusBadge(
                            label: 'platform.w.sigRequired'.tr,
                            tag: 'tag-info',
                          ),
                        if (range.isNotEmpty)
                          VouchFlowStatusBadge(
                            label: range,
                            tag: 'tag-outline',
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _routing(VfTokens t, CompanyWorkflows d) {
    final steps = d.routingSteps.where((s) => !s.isRequestStep).toList();
    return VouchFlowCard(
      title: 'platform.w.who'.tr,
      subtitle: d.gaps > 0
          ? 'platform.w.gaps'.trParams({'n': '${d.gaps}'})
          : 'platform.w.noGaps'.tr,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < d.routingDepartments.length; i++) ...[
            if (i > 0) Divider(height: 1, color: t.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    d.routingDepartments[i].name,
                    style: VfType.bodyStrong.copyWith(color: t.text),
                  ),
                  const SizedBox(height: 6),
                  for (final s in steps) _cell(t, s, d.routingDepartments[i]),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cell(VfTokens t, RoutingStep s, RoutingDepartment dep) {
    final cell = dep.cells.firstWhereOrNull((c) => c.stepId == s.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              '${s.position}. ${s.name}',
              style: VfType.small.copyWith(color: t.muted),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: cell == null || cell.people.isEmpty
                  ? VouchFlowStatusBadge(
                      label: 'platform.w.nobody'.trParams({
                        'gap': (cell?.gap ?? '').replaceAll('_', ' '),
                      }),
                      tag: 'tag-accent-2',
                    )
                  : Text(
                      cell.people.map((p) => p.name).join('\n'),
                      textAlign: TextAlign.right,
                      style: VfType.small.copyWith(color: t.text),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/* ───────────────────────────────────────────────────────────── vouchers ── */

class VouchersTab extends StatefulWidget {
  const VouchersTab({
    super.key,
    required this.companyId,
    required this.departments,
    required this.currency,
    this.initial,
  });

  final int companyId;
  final List<DepartmentRow> departments;
  final String currency;
  final Map<String, String>? initial;

  @override
  State<VouchersTab> createState() => _VouchersTabState();
}

class _VouchersTabState extends State<VouchersTab> {
  static const _blank = {
    'q': '',
    'status': '',
    'department_id': '',
    'requester_id': '',
    'from': '',
    'to': '',
    'min_amount': '',
    'max_amount': '',
  };
  static const _statuses = [
    'draft',
    'in_review',
    'changes_requested',
    'awaiting_payment',
    'paid',
    'rejected',
    'cancelled',
  ];

  late Map<String, String> _f = {..._blank, ...?widget.initial};
  late final _qCtrl = TextEditingController(text: _f['q']);
  int _page = 1;
  PlatformPage<PlatformVoucherRow>? _result;
  String? _error;
  List<PlatformUser> _people = const [];
  Timer? _debounce;
  int _seq = 0;
  int _formKey = 0;

  @override
  void initState() {
    super.initState();
    _load();
    PlatformRepository.to
        .companyUsers(widget.companyId, const {}, perPage: 100)
        .then((r) {
          if (mounted) setState(() => _people = r.items);
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _qCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() => _error = null);
    try {
      final r = await PlatformRepository.to.companyVouchers(
        widget.companyId,
        _f,
        page: _page,
      );
      if (mounted && seq == _seq) setState(() => _result = r);
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _error = errorText(e));
    }
  }

  void _set(String k, String v, {bool debounce = false}) {
    setState(() {
      _f[k] = v;
      _page = 1;
    });
    _debounce?.cancel();
    if (debounce) {
      _debounce = Timer(const Duration(milliseconds: 300), _load);
    } else {
      _load();
    }
  }

  void _clear() {
    _qCtrl.clear();
    setState(() {
      _f = {..._blank};
      _page = 1;
      _formKey++;
    });
    _load();
  }

  Future<void> _pickDate(String k) async {
    final current = DateTime.tryParse(_f[k] ?? '');
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (picked != null) _set(k, DateFormat('yyyy-MM-dd').format(picked));
  }

  Widget _dateField(String k, String label) {
    final t = context.vf;
    final v = _f[k] ?? '';
    return VouchFlowField(
      label: label,
      child: InkWell(
        onTap: () => _pickDate(k),
        borderRadius: BorderRadius.circular(VfSize.radiusL),
        child: Container(
          height: VfSize.inputH,
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            color: t.inputBg,
            borderRadius: BorderRadius.circular(VfSize.radiusL),
            border: Border.all(color: t.inputBorder),
          ),
          child: Row(
            children: [
              Icon(
                PhosphorIconsRegular.calendarBlank,
                size: 16,
                color: t.muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  v.isEmpty
                      ? 'platform.v.anyDate'.tr
                      : Fmt.date(DateTime.tryParse(v)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VfType.body.copyWith(
                    color: v.isEmpty ? t.placeholder : t.text,
                    fontSize: 14,
                  ),
                ),
              ),
              if (v.isNotEmpty)
                IconButton(
                  tooltip: 'platform.v.clear'.tr,
                  icon: Icon(PhosphorIconsRegular.x, size: 14, color: t.muted),
                  onPressed: () => _set(k, ''),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pair(Widget a, Widget b) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: a),
      const SizedBox(width: 10),
      Expanded(child: b),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final r = _result;
    final rows = r?.items ?? const <PlatformVoucherRow>[];
    final active = _f.values.any((v) => v.isNotEmpty);
    final sw = Get.locale?.languageCode == 'sw';

    final filters = VouchFlowCard(
      key: ValueKey('filters-$_formKey'),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VouchFlowSearchField(
            placeholder: 'platform.v.search'.tr,
            controller: _qCtrl,
            onChanged: (v) => _set('q', v, debounce: true),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text:
                          '${'platform.v.count'.trParams({'n': '${r?.total ?? 0}'})} · ',
                    ),
                    TextSpan(
                      text: money(
                        r?.metaNum('total_amount') ?? 0,
                        widget.currency,
                      ),
                      style: TextStyle(
                        color: t.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                style: VfType.small.copyWith(
                  color: t.muted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (active)
                VouchFlowButton(
                  label: 'platform.v.clear'.tr,
                  icon: PhosphorIconsRegular.x,
                  variant: VfButtonVariant.ghost,
                  compact: true,
                  onPressed: _clear,
                ),
            ],
          ),
          const SizedBox(height: 8),
          _labelled(
            'platform.status'.tr,
            PlatformSelect<String>(
              value: _f['status']!,
              items: [
                ('', 'platform.allStatuses'.tr),
                for (final s in _statuses) (s, 'platform.vs.$s'.tr),
              ],
              onChanged: (v) => _set('status', v),
            ),
          ),
          const SizedBox(height: 10),
          _labelled(
            'platform.v.department'.tr,
            PlatformSelect<String>(
              value: _f['department_id']!,
              items: [
                ('', 'platform.allDepartments'.tr),
                for (final d in widget.departments) ('${d.id}', d.name),
              ],
              onChanged: (v) => _set('department_id', v),
            ),
          ),
          const SizedBox(height: 10),
          _labelled(
            'platform.v.employee'.tr,
            PlatformSelect<String>(
              value: _f['requester_id']!,
              items: [
                ('', 'platform.v.everyone'.tr),
                for (final u in _people) ('${u.id}', u.name),
              ],
              onChanged: (v) => _set('requester_id', v),
            ),
          ),
          const SizedBox(height: 10),
          _pair(
            _dateField('from', 'platform.v.from'.tr),
            _dateField('to', 'platform.v.to'.tr),
          ),
          const SizedBox(height: 10),
          _pair(
            VouchFlowTextField(
              label: 'platform.v.minAmount'.tr,
              initialValue: _f['min_amount'],
              placeholder: '0',
              keyboardType: TextInputType.number,
              onChanged: (v) => _set('min_amount', v.trim(), debounce: true),
            ),
            VouchFlowTextField(
              label: 'platform.v.maxAmount'.tr,
              initialValue: _f['max_amount'],
              placeholder: 'platform.v.any'.tr,
              keyboardType: TextInputType.number,
              onChanged: (v) => _set('max_amount', v.trim(), debounce: true),
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        filters,
        const SizedBox(height: VfSize.gap),
        VouchFlowCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null || r == null)
                platformPanelState(
                  loading: r == null,
                  error: _error,
                  onRetry: _load,
                  rows: 5,
                )
              else if (rows.isEmpty)
                VouchFlowEmptyState(
                  icon: PhosphorIconsRegular.receipt,
                  title: active
                      ? 'platform.v.emptyFiltered'.tr
                      : 'platform.v.empty'.tr,
                )
              else ...[
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: t.border),
                  _row(t, rows[i], sw),
                ],
                if (r.lastPage > 1) Divider(height: 1, color: t.border),
                PlatformPager(
                  page: r.page,
                  lastPage: r.lastPage,
                  total: r.total,
                  onChanged: (p) {
                    setState(() => _page = p);
                    _load();
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _labelled(String label, Widget child) =>
      VouchFlowField(label: label, child: child);

  Widget _row(VfTokens t, PlatformVoucherRow v, bool sw) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      v.number,
                      style: VfType.bodyStrong.copyWith(
                        color: t.text,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: t.surface3,
                        borderRadius: BorderRadius.circular(VfSize.radiusS),
                      ),
                      child: Text(
                        v.typeLabel,
                        style: VfType.meta.copyWith(
                          color: t.text2,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: VouchFlowStatusBadge(
                  label: sw ? v.statusLabelSw : v.statusLabelEn,
                  tag: v.statusTag,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            v.purpose,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: VfType.body.copyWith(
              color: t.text,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            v.payee,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: VfType.small.copyWith(color: t.muted),
          ),
          const SizedBox(height: 6),
          Text(
            v.amountText ?? money(v.amount, v.currency),
            style: VfType.bodyStrong.copyWith(
              color: t.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          PlatformMetaLine(
            label: 'platform.v.employee'.tr,
            value: v.requester ?? '—',
          ),
          PlatformMetaLine(
            label: 'platform.v.department'.tr,
            value: v.department ?? '—',
          ),
          if (v.status == 'in_review')
            PlatformMetaLine(
              label: 'platform.v.stage'.tr,
              value:
                  v.currentStepName ??
                  'platform.v.step'.trParams({
                    'n': '${v.currentStepPosition ?? '—'}',
                  }),
            ),
          PlatformMetaLine(
            label: 'platform.v.created'.tr,
            value:
                '${Fmt.date(v.createdAt)} · ${'platform.v.updated'.trParams({'date': Fmt.date(v.updatedAt)})}',
          ),
        ],
      ),
    );
  }
}

/* ───────────────────────────────────────────────────────────── payments ── */

class PaymentsTab extends StatelessWidget {
  const PaymentsTab({super.key, required this.overview});

  final CompanyOverview overview;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final o = overview;
    final cur = o.currency;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlatformKpiGrid(
          children: [
            VouchFlowStatCard(
              label: 'platform.p.totalPaid'.tr,
              value: money(o.paidValue, cur),
              sub: 'platform.p.totalPaidSub'.trParams({'n': '${o.paidCount}'}),
              icon: PhosphorIconsRegular.handCoins,
              tone: VfTone.ok,
            ),
            VouchFlowStatCard(
              label: 'platform.ov.pendingPayment'.tr,
              value: money(o.pendingValue, cur),
              sub: 'platform.p.pendingSub'.trParams({'n': '${o.pendingCount}'}),
              icon: PhosphorIconsRegular.hourglass,
              tone: VfTone.warn,
            ),
            VouchFlowStatCard(
              label: 'platform.p.made'.tr,
              value: '${o.paidCount}',
              sub: 'platform.p.madeSub'.tr,
              icon: PhosphorIconsRegular.receipt,
              tone: VfTone.info,
            ),
          ],
        ),
        const SizedBox(height: VfSize.gap),
        VouchFlowCard(
          title: 'platform.p.recent'.tr,
          subtitle: 'platform.p.recentSub'.tr,
          padding: EdgeInsets.zero,
          child: o.recentPayments.isEmpty
              ? VouchFlowEmptyState(
                  icon: PhosphorIconsRegular.handCoins,
                  title: 'platform.p.empty'.tr,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < o.recentPayments.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: t.border),
                      _row(t, o.recentPayments[i], cur),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _row(VfTokens t, RecentPayment r, String cur) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.number,
                      style: VfType.bodyStrong.copyWith(
                        color: t.text,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      r.kind == 'cash'
                          ? 'platform.p.cash'.tr
                          : 'platform.p.bank'.tr,
                      style: VfType.meta.copyWith(color: t.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                money(r.amount, r.currency ?? cur),
                style: VfType.bodyStrong.copyWith(
                  color: t.text,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            r.payee,
            style: VfType.small.copyWith(
              color: t.text,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            r.purpose,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: VfType.meta.copyWith(color: t.muted),
          ),
          const SizedBox(height: 6),
          PlatformMetaLine(
            label: 'platform.v.department'.tr,
            value: r.department ?? '—',
          ),
          PlatformMetaLine(
            label: 'platform.p.method'.tr,
            value: r.paymentMethod ?? '—',
          ),
          PlatformMetaLine(
            label: 'platform.p.reference'.tr,
            value: r.paymentReference ?? '—',
          ),
          PlatformMetaLine(
            label: 'platform.p.paidBy'.tr,
            value: r.paidBy ?? '—',
          ),
          PlatformMetaLine(
            label: 'platform.pay.date'.tr,
            value: Fmt.date(r.paymentDate ?? r.paidAt),
          ),
        ],
      ),
    );
  }
}

/* ───────────────────────────────────────────────────────── subscription ── */

class SubscriptionTab extends StatelessWidget {
  const SubscriptionTab({
    super.key,
    required this.detail,
    required this.onChangePlan,
  });

  final CompanyDetail detail;
  final VoidCallback onChangePlan;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final c = detail.company;
    final s = detail.subscription;
    final plan = c.plan;
    final metrics = [
      detail.metric('users'),
      detail.metric('vouchers_this_month'),
      detail.metric('departments'),
      detail.metric('storage'),
    ].whereType<UsageMetric>().toList();
    String? price;
    if (plan != null) {
      price = plan.price > 0
          ? (plan.billingCycle == 'annual'
                    ? 'platform.s.perYear'
                    : 'platform.s.perMonth')
                .trParams({'price': money(plan.price, plan.currency)})
          : 'platform.custom'.tr;
    }
    final cycle = s?.billingCycle ?? plan?.billingCycle;
    final limit = detail.approvalLevelsLimit;

    final planCard = VouchFlowCard(
      title: plan?.name ?? 'platform.noPlan'.tr,
      subtitle: plan?.blurb,
      actions: [
        VouchFlowButton(
          label: 'platform.changePlan'.tr,
          variant: VfButtonVariant.secondary,
          compact: true,
          onPressed: onChangePlan,
        ),
      ],
      child: PlatformFacts(
        rows: [
          (
            'platform.s.companyStatus'.tr,
            Align(
              alignment: Alignment.centerLeft,
              child: VouchFlowStatusBadge(label: statusLabel(c.status)),
            ),
          ),
          (
            'platform.s.subStatus'.tr,
            s != null ? statusLabel(s.status) : 'platform.s.noSub'.tr,
          ),
          ('platform.s.price'.tr, price),
          (
            'platform.s.cycle'.tr,
            cycle == null
                ? null
                : (cycle == 'annual'
                      ? 'platform.plans.annual'.tr
                      : 'platform.plans.monthly'.tr),
          ),
          (
            'platform.s.started'.tr,
            Fmt.date(s?.startsAt ?? c.currentPeriodStart),
          ),
          (
            c.status == 'trial'
                ? 'platform.s.trialEnds'.tr
                : 'platform.s.renews'.tr,
            Fmt.date(c.renewsAt),
          ),
          ('platform.s.daysRemaining'.tr, c.daysRemaining?.toString()),
          (
            'platform.s.autoRenew'.tr,
            c.autoRenew ? 'platform.s.on'.tr : 'platform.s.off'.tr,
          ),
          (
            'platform.s.levels'.tr,
            limit == null ? 'platform.unlimited'.tr : '$limit',
          ),
        ],
      ),
    );

    final usageCard = VouchFlowCard(
      title: 'platform.s.usage'.tr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final m in metrics)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          m.label,
                          style: VfType.small.copyWith(color: t.text2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _usageLine(m),
                          textAlign: TextAlign.right,
                          style: VfType.small.copyWith(
                            color: t.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!m.unlimited) ...[
                    const SizedBox(height: 6),
                    PlatformMeter(percent: m.percent, exceeded: m.exceeded),
                  ],
                ],
              ),
            ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlatformTwoUp(left: planCard, right: usageCard),
        const SizedBox(height: VfSize.gap),
        VouchFlowCard(
          title: 'platform.s.history'.tr,
          padding: EdgeInsets.zero,
          child: detail.invoices.isEmpty
              ? VouchFlowEmptyState(
                  icon: PhosphorIconsRegular.fileText,
                  title: 'platform.s.noInvoices'.tr,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < detail.invoices.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: t.border),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    detail.invoices[i].number,
                                    style: VfType.bodyStrong.copyWith(
                                      color: t.text,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    detail.invoices[i].description,
                                    style: VfType.small.copyWith(
                                      color: t.text2,
                                    ),
                                  ),
                                  Text(
                                    Fmt.date(
                                      detail.invoices[i].paidAt ??
                                          detail.invoices[i].issuedAt,
                                    ),
                                    style: VfType.meta.copyWith(color: t.muted),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  detail.invoices[i].amountText,
                                  style: VfType.bodyStrong.copyWith(
                                    color: t.text,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                VouchFlowStatusBadge(
                                  label: statusLabel(detail.invoices[i].status),
                                  tag: detail.invoices[i].statusTag,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

/* ───────────────────────────────────────────────────────────── activity ── */

const _activityIcons = <(String, IconData)>[
  ('company', PhosphorIconsRegular.buildings),
  ('user', PhosphorIconsRegular.userPlus),
  ('employee', PhosphorIconsRegular.userPlus),
  ('voucher.paid', PhosphorIconsRegular.handCoins),
  ('voucher.approved', PhosphorIconsRegular.sealCheck),
  ('voucher.rejected', PhosphorIconsRegular.xCircle),
  ('voucher', PhosphorIconsRegular.receipt),
  ('subscription', PhosphorIconsRegular.crownSimple),
  ('billing', PhosphorIconsRegular.crownSimple),
  ('branding', PhosphorIconsRegular.palette),
  ('workflow', PhosphorIconsRegular.flowArrow),
  ('department', PhosphorIconsRegular.treeStructure),
  ('auth', PhosphorIconsRegular.signIn),
  ('platform', PhosphorIconsRegular.shieldCheck),
];

class ActivityTab extends StatefulWidget {
  const ActivityTab({super.key, required this.companyId});

  final int companyId;

  @override
  State<ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<ActivityTab> {
  String _q = '';
  int _page = 1;
  PlatformPage<AuditEntry>? _result;
  String? _error;
  Timer? _debounce;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() => _error = null);
    try {
      final r = await PlatformRepository.to.activity(
        widget.companyId,
        q: _q,
        page: _page,
      );
      if (mounted && seq == _seq) setState(() => _result = r);
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _error = errorText(e));
    }
  }

  IconData _icon(String action) =>
      _activityIcons.firstWhereOrNull((e) => action.startsWith(e.$1))?.$2 ??
      PhosphorIconsRegular.clockCounterClockwise;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final r = _result;
    final rows = r?.items ?? const <AuditEntry>[];
    return VouchFlowCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                VouchFlowSearchField(
                  placeholder: 'platform.a.search'.tr,
                  onChanged: (v) {
                    _q = v;
                    _page = 1;
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 250), _load);
                  },
                ),
                const SizedBox(height: 10),
                PlatformCount(
                  'platform.a.count'.trParams({'n': '${r?.total ?? 0}'}),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: t.border),
          if (_error != null || r == null)
            platformPanelState(
              loading: r == null,
              error: _error,
              onRetry: _load,
              rows: 6,
            )
          else if (rows.isEmpty)
            VouchFlowEmptyState(
              icon: PhosphorIconsRegular.clockCounterClockwise,
              title: 'platform.a.empty'.tr,
            )
          else ...[
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, color: t.border),
              _row(t, rows[i]),
            ],
            if (r.lastPage > 1) Divider(height: 1, color: t.border),
            PlatformPager(
              page: r.page,
              lastPage: r.lastPage,
              total: r.total,
              onChanged: (p) {
                setState(() => _page = p);
                _load();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(VfTokens t, AuditEntry a) {
    final meta = [
      a.actorName + (a.actorRole != null ? ' · ${roleLabel(a.actorRole)}' : ''),
      a.action,
      if (a.entityType != null)
        '${a.entityType!.split('\\').last} #${a.entityId ?? ''}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: t.primarySoftStrong,
              shape: BoxShape.circle,
            ),
            child: Icon(_icon(a.action), size: 16, color: t.primaryText),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.description,
                  style: VfType.small.copyWith(
                    color: t.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (a.changeSummary != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    a.changeSummary!,
                    style: VfType.meta.copyWith(color: t.text2),
                  ),
                ],
                const SizedBox(height: 2),
                Text(meta, style: VfType.meta.copyWith(color: t.muted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: Fmt.dateTime(a.createdAt),
            child: Text(
              relativeTime(a.createdAt),
              style: VfType.meta.copyWith(color: t.muted),
            ),
          ),
        ],
      ),
    );
  }
}
