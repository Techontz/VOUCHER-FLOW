import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart';
import '../../data/models/ops_models.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/production_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../erp/erp_widgets.dart';
import '../erp/ops_kit.dart';
import 'production_app.dart';
import 'production_widgets.dart';

/// The Production home (the web's /erp/production): what the floor made
/// today, what waits for quality control, the month's yield, the last two
/// weeks of output and the orders on the floor and coming up.
class ProductionOverviewPage extends StatelessWidget {
  const ProductionOverviewPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'production',
    permission: 'production.view',
    builder: (_) => const _Overview(),
  );
}

class _Overview extends StatefulWidget {
  const _Overview();

  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  final _repo = ProductionRepository.to;
  final _erp = ErpService.to;
  ProductionOverview? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _repo.overview();
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = opsError(e));
    }
  }

  Future<void> _open(int id) async {
    await Get.toNamed(Routes.prdOrder, arguments: id);
    _load();
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
    final actions = productionCreateActions
        .where((a) => a.permission == null || _erp.can(a.permission!))
        .toList();
    final floor = d.recent
        .where((o) => o.onFloor || o.status == PrdStatus.planned)
        .toList();

    final figures = [
      VouchFlowFigureGrid(
        children: [
          VouchFlowFigureCard(
            label: 'prd.releasedToday'.tr,
            value: ErpFmt.qty(d.todayReleased),
            hint: 'prd.producedToday'.trParams({
              'n': ErpFmt.qty(d.todayProduced),
            }),
            icon: PhosphorIconsRegular.package,
            tone: VfTone.ok,
          ),
          VouchFlowFigureCard(
            label: 'prd.qcPending'.tr,
            value: '${d.qcPending}',
            hint: d.qcPending > 0 ? 'prd.qcPendingHint'.tr : 'prd.qcClear'.tr,
            icon: PhosphorIconsRegular.sealCheck,
            tone: d.qcPending > 0 ? VfTone.warn : VfTone.neutral,
            onTap: () => erpGo('/erp/production/qc'),
          ),
          VouchFlowFigureCard(
            label: 'prd.openOrders'.tr,
            value: '${d.openOrders}',
            hint: 'prd.openOrdersHint'.trParams({
              'n': '${d.byStatus[PrdStatus.inProgress] ?? 0}',
              'r': '${d.byStatus[PrdStatus.released] ?? 0}',
            }),
            icon: PhosphorIconsRegular.factory,
            tone: VfTone.info,
            onTap: () => erpGo('/erp/production/orders'),
          ),
          VouchFlowFigureCard(
            label: 'prd.yield30'.tr,
            value: opsPercent(d.yieldPercent),
            hint: 'prd.yieldHint'.trParams({
              'released': ErpFmt.qty(d.periodReleased),
              'produced': ErpFmt.qty(d.periodProduced),
            }),
            icon: PhosphorIconsRegular.chartLineUp,
            tone: VfTone.primary,
          ),
        ],
      ),
    ];

    return ErpPageBody(
      onRefresh: _load,
      children: [
        ErpPageTitle('area.production'.tr, subtitle: 'prd.overviewSub'.tr),
        for (final f in figures) ...[f, const SizedBox(height: 12)],
        const SizedBox(height: 2),
        if (actions.isNotEmpty) ...[
          VouchFlowPanel(
            title: 'inv.quickActions'.tr,
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
          title: 'prd.upcoming'.tr,
          padded: false,
          actionLabel: 'erp.viewAll'.tr,
          onAction: () => erpGo('/erp/production/orders'),
          child: floor.isEmpty
              ? OpsPanelEmpty('prd.noOpenOrders'.tr)
              : Column(
                  children: [
                    for (var i = 0; i < floor.length; i++)
                      PrdOrderRow(
                        order: floor[i],
                        divider: i > 0,
                        onTap: () => _open(floor[i].id),
                      ),
                  ],
                ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'prd.outputTrend'.tr,
          subtitle: 'prd.outputTrendSub'.tr,
          child: _TrendBars(d.trend),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'prd.byProduct'.tr,
          padded: false,
          child: d.byProduct.isEmpty
              ? OpsPanelEmpty('prd.noOutput'.tr)
              : Column(
                  children: [
                    for (var i = 0; i < d.byProduct.length; i++)
                      VouchFlowListRow(
                        divider: i > 0,
                        icon: PhosphorIconsRegular.package,
                        title: d.byProduct[i].name,
                        subtitle: 'prd.yieldHint'.trParams({
                          'released': ErpFmt.qty(d.byProduct[i].released),
                          'produced': ErpFmt.qty(d.byProduct[i].produced),
                        }),
                        trailing: Text(
                          opsPercent(d.byProduct[i].yieldPercent),
                          style: VfType.bodyStrong.copyWith(
                            color: t.text,
                            fontSize: 14.5,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'prd.period'.tr,
          child: OpsFigureGrid(
            items: [
              ('prd.produced'.tr, ErpFmt.qty(d.periodProduced)),
              ('prd.rejected'.tr, ErpFmt.qty(d.periodRejected)),
              (
                'prd.wastage'.tr,
                '${ErpFmt.qty(d.periodWastage)} · ${opsPercent(d.wastagePercent)}',
              ),
              (
                'prd.materialsIssued'.tr,
                ErpFmt.compactMoney(d.materialsIssued, currency),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Fourteen columns of output ending today, today in the accent colour.
class _TrendBars extends StatelessWidget {
  const _TrendBars(this.days);

  final List<({DateTime? date, double produced, double released})> days;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final values = [for (final d in days) d.produced];
    final peak = values.fold<double>(1, (a, b) => a > b ? a : b);
    return Semantics(
      label: [
        for (final d in days)
          '${d.date == null ? '' : opsDay(d.date!)}: ${ErpFmt.qty(d.produced)}',
      ].join(', '),
      child: ExcludeSemantics(
        child: SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < days.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: values[i] == 0
                                  ? .04
                                  : (values[i] / peak).clamp(.08, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: i == days.length - 1
                                      ? t.primary
                                      : t.primary.withValues(
                                          alpha: t.isDark ? .35 : .22,
                                        ),
                                  borderRadius: BorderRadius.circular(
                                    VfSize.radiusXs,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${days[i].date?.day ?? ''}',
                          style: VfType.meta.copyWith(
                            fontSize: 10.5,
                            color: i == days.length - 1 ? t.text : t.muted,
                            fontWeight: i == days.length - 1
                                ? FontWeight.w600
                                : FontWeight.w400,
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
    );
  }
}
