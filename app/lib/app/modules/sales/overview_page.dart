import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart';
import '../../data/models/sales_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/sales_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../erp/erp_widgets.dart';
import 'registers.dart' show openSalesOrders;
import 'sales_app.dart';
import 'sales_widgets.dart';

/// The Sales home (the web's /erp/sales): the month's money in four
/// figures, what needs someone's attention, the order pipeline, what you
/// can start, and the latest orders.
class SalesOverviewPage extends StatelessWidget {
  const SalesOverviewPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'sales',
    permission: 'sales.view',
    builder: (_) => const _Overview(),
  );
}

class _Overview extends StatefulWidget {
  const _Overview();

  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  final _erp = ErpService.to;
  SalesOverview? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await SalesRepository.to.overview();
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'state.offline'.tr);
    }
  }

  Future<void> _openOrder(int id) async {
    await Get.toNamed(Routes.salesOrder, arguments: id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) {
      return _error == null
          ? const VfLoadingView()
          : ErpPageBody(
              onRefresh: _load,
              children: [
                VouchFlowErrorState(
                  message: _error!,
                  onRetry: _load,
                  retryLabel: 'action.retry'.tr,
                ),
              ],
            );
    }
    final t = context.vf;
    final currency = _erp.currency;
    final actions = salesCreateActions
        .where((a) => a.permission == null || _erp.can(a.permission!))
        .toList();
    final dispatch = _erp.has('dispatch') && _erp.can('dispatch.view');
    final submitted = d.count(SalesStatus.submitted);

    final money = [
      VouchFlowFigureGrid(
        children: [
          VouchFlowFigureCard(
            label: 'sal.salesThisMonth'.tr,
            value: ErpFmt.compactMoney(d.salesThisMonth, currency),
            hint: 'sal.exVat'.tr,
            icon: PhosphorIconsRegular.chartLineUp,
            onTap: () => openSalesOrders(),
          ),
          VouchFlowFigureCard(
            label: 'sal.receivedThisMonth'.tr,
            value: ErpFmt.compactMoney(d.receivedThisMonth, currency),
            hint: '$currency ${ErpFmt.amount(d.receivedThisMonth.round())}',
            icon: PhosphorIconsRegular.handCoins,
            tone: VfTone.ok,
            onTap: () => erpGo('/erp/sales/receipts'),
          ),
          VouchFlowFigureCard(
            label: 'sal.receivables'.tr,
            value: ErpFmt.compactMoney(d.receivables, currency),
            hint: 'sal.receivablesHint'.tr,
            icon: PhosphorIconsRegular.scales,
            tone: VfTone.info,
            onTap: () => erpGo('/erp/sales/invoices'),
          ),
          VouchFlowFigureCard(
            label: 'sal.overdue'.tr,
            value: ErpFmt.compactMoney(d.overdue, currency),
            hint: d.overdue > 0 ? 'sal.overdueHint'.tr : 'sal.overdueNone'.tr,
            icon: PhosphorIconsRegular.warning,
            tone: d.overdue > 0 ? VfTone.bad : VfTone.neutral,
            onTap: () => erpGo('/erp/sales/invoices'),
          ),
        ],
      ),
    ];

    // What waits on someone: a row each, tinted when it is not zero.
    final attention = <(IconData, String, int, VfTone, VoidCallback?)>[
      (
        PhosphorIconsRegular.sealCheck,
        'sal.awaitingApproval'.tr,
        submitted,
        VfTone.warn,
        () => openSalesOrders(SalesStatus.submitted),
      ),
      (
        PhosphorIconsRegular.hourglassMedium,
        'sal.awaitingPayment'.tr,
        d.awaitingPayment,
        VfTone.warn,
        () => openSalesOrders(SalesStatus.awaitingPayment),
      ),
      (
        PhosphorIconsRegular.shieldCheck,
        'sal.awaitingVerification'.tr,
        d.awaitingVerification,
        VfTone.warn,
        () => dispatch && _erp.can('dispatch.verify')
            ? erpGo('/erp/dispatch/verification')
            : erpGo('/erp/sales/receipts'),
      ),
      (
        PhosphorIconsRegular.notePencil,
        'sal.openQuotations'.tr,
        d.openQuotations,
        VfTone.info,
        () => erpGo('/erp/sales/quotations'),
      ),
      if (dispatch)
        (
          PhosphorIconsRegular.warningDiamond,
          'sal.openDiscrepancies'.tr,
          d.openDiscrepancies,
          VfTone.bad,
          () => erpGo('/erp/dispatch'),
        ),
    ];

    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 600;
        return ErpPageBody(
          onRefresh: _load,
          children: [
            ErpPageTitle('area.sales'.tr, subtitle: 'sal.overviewSub'.tr),
            if (wide)
              _Grid(children: money)
            else
              for (final f in money) ...[f, const SizedBox(height: 12)],
            if (wide) erpGap else const SizedBox(height: 2),
            VouchFlowPanel(
              title: 'sal.needsAction'.tr,
              padded: false,
              child: Column(
                children: [
                  for (var i = 0; i < attention.length; i++)
                    VouchFlowListRow(
                      divider: i > 0,
                      icon: attention[i].$1,
                      iconColor: attention[i].$3 > 0
                          ? attention[i].$4.colors(t).$1
                          : t.muted,
                      title: attention[i].$2,
                      trailing: _Count(attention[i].$3, tone: attention[i].$4),
                      onTap: attention[i].$5,
                    ),
                ],
              ),
            ),
            erpGap,
            if (actions.isNotEmpty) ...[
              VouchFlowPanel(
                title: 'sal.quickActions'.tr,
                padded: false,
                child: Column(
                  children: [
                    for (var i = 0; i < actions.length; i++)
                      VouchFlowListRow(
                        divider: i > 0,
                        icon: actions[i].icon,
                        title: actions[i].label.tr,
                        subtitle: actions[i].hint?.tr,
                        trailing: Icon(
                          PhosphorIconsBold.caretRight,
                          size: 14,
                          color: t.faint,
                        ),
                        onTap: () async {
                          await erpCreate(actions[i]);
                          _load();
                        },
                      ),
                  ],
                ),
              ),
              erpGap,
            ],
            VouchFlowPanel(
              title: 'sal.pipeline'.tr,
              subtitle: 'sal.pipelineSub'.tr,
              child: _Pipeline(data: d),
            ),
            erpGap,
            VouchFlowPanel(
              title: 'sal.recentOrders'.tr,
              padded: false,
              actionLabel: 'erp.viewAll'.tr,
              onAction: () => openSalesOrders(),
              child: d.recentOrders.isEmpty
                  ? SalesNote('sal.noOrders'.tr)
                  : Column(
                      children: [
                        for (var i = 0; i < d.recentOrders.length; i++)
                          SalesOrderRow(
                            order: d.recentOrders[i],
                            divider: i > 0,
                            onTap: () => _openOrder(d.recentOrders[i].id),
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

class _Count extends StatelessWidget {
  const _Count(this.n, {required this.tone});

  final int n;
  final VfTone tone;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final (fg, bg) = n > 0 ? tone.colors(t) : (t.muted, t.glassFill);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(minWidth: 30),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(VfSize.radiusPill),
          ),
          child: Text(
            '$n',
            textAlign: TextAlign.center,
            style: VfType.small.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Icon(PhosphorIconsBold.caretRight, size: 14, color: t.faint),
      ],
    );
  }
}

/// The pipeline as horizontal bars, one per stage, each opening the orders
/// at that stage (the web's erp-hbars).
class _Pipeline extends StatelessWidget {
  const _Pipeline({required this.data});

  final SalesOverview data;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final peak = SalesStatus.pipeline.fold<int>(
      1,
      (m, s) => data.count(s) > m ? data.count(s) : m,
    );
    return Column(
      children: [
        for (final s in SalesStatus.pipeline)
          InkWell(
            borderRadius: BorderRadius.circular(VfSize.radiusS),
            onTap: () => openSalesOrders(s),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 112,
                    child: Text(
                      salesStatusLabel(s),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: VfType.small.copyWith(color: t.text2),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(VfSize.radiusPill),
                      child: Container(
                        height: 8,
                        color: t.primary.withValues(
                          alpha: t.isDark ? .14 : .09,
                        ),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: data.count(s) == 0
                              ? 0
                              : (data.count(s) / peak).clamp(.04, 1.0),
                          child: Container(
                            color: s == SalesStatus.delivered
                                ? t.successStrong
                                : t.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '${data.count(s)}',
                      textAlign: TextAlign.right,
                      style: VfType.small.copyWith(
                        color: t.text,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < children.length; i += 2) ...[
        if (i > 0) const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: children[i]),
              const SizedBox(width: 12),
              Expanded(
                child: i + 1 < children.length
                    ? children[i + 1]
                    : const SizedBox(),
              ),
            ],
          ),
        ),
      ],
    ],
  );
}
