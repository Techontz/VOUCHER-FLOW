import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/finance_models.dart';
import '../../data/services/assets_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;
import '../erp/erp_widgets.dart';
import '../finance/fin_widgets.dart';
import '../inventory/inventory_widgets.dart' show ErpFact;

/*
 * The Assets screens: the overview, the register, an asset's page with its
 * history (custodians and moves) and depreciation schedule, and the
 * monthly depreciation runs.
 */

AssetsRepository get _repo => AssetsRepository.to;

/// One asset in a list: tag, name, class and book value.
class AssetRow extends StatelessWidget {
  const AssetRow({
    super.key,
    required this.asset,
    required this.onTap,
    this.divider = true,
  });

  final FixedAsset asset;
  final VoidCallback onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final a = asset;
    final t = context.vf;
    return VouchFlowListRow(
      divider: divider,
      icon: PhosphorIconsRegular.buildings,
      iconColor: a.status == 'active' ? const Color(0xFFAC8E68) : t.muted,
      title: a.name,
      subtitle: [a.tag, ?a.assetClass?.name, ?a.custodian?.name].join(' · '),
      trailing: FinTrailing(
        amount: finCompact(a.status == 'disposed' ? 0 : a.netBookValue),
        badge: a.status == 'active' ? null : FinStatusBadge(a.status),
      ),
      onTap: onTap,
    );
  }
}

Future<void> _openAsset(int id, VoidCallback reload) async {
  await Get.toNamed(Routes.astAsset, arguments: id);
  reload();
}

/// The Assets home: cost, depreciation so far, book value, next month's
/// charge, value by class and the last run (the web's /erp/assets).
class AssetsOverviewPage extends StatelessWidget {
  const AssetsOverviewPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'assets',
    permission: 'assets.view',
    builder: (_) => FinAsync<AssetsOverview>(
      load: _repo.overview,
      builder: (context, d, reload) {
        final t = context.vf;
        final run = d.latestRun;
        return [
          ErpPageTitle('area.assets'.tr, subtitle: 'ast.overviewSub'.tr),
          FinFigures(
            children: [
              VouchFlowFigureGrid(
                children: [
                  VouchFlowFigureCard(
                    label: 'ast.bookValue'.tr,
                    value: finCompact(d.bookValue),
                    hint: 'ast.ofCost'.trParams({'amount': finCompact(d.cost)}),
                    icon: PhosphorIconsRegular.buildings,
                    onTap: () => erpGo('/erp/assets/register'),
                  ),
                  VouchFlowFigureCard(
                    label: 'ast.activeAssets'.tr,
                    value: '${d.active}',
                    hint: 'ast.draftDisposed'.trParams({
                      'draft': '${d.counts['draft'] ?? 0}',
                      'disposed': '${d.counts['disposed'] ?? 0}',
                    }),
                    icon: PhosphorIconsRegular.stack,
                    tone: VfTone.neutral,
                    onTap: () => erpGo('/erp/assets/register'),
                  ),
                  VouchFlowFigureCard(
                    label: 'ast.accumulated'.tr,
                    value: finCompact(d.accumulated),
                    hint: d.cost <= 0
                        ? null
                        : 'ast.writtenOff'.trParams({
                            'n': '${(d.accumulated / d.cost * 100).round()}',
                          }),
                    icon: PhosphorIconsRegular.trendDown,
                    tone: VfTone.info,
                  ),
                  VouchFlowFigureCard(
                    label: 'ast.nextCharge'.tr,
                    value: finCompact(d.nextDue),
                    hint: d.nextPeriod == null
                        ? null
                        : 'ast.forPeriod'.trParams({
                            'period': finPeriod(d.nextPeriod!),
                          }),
                    icon: PhosphorIconsRegular.calendarCheck,
                    tone: VfTone.warn,
                    onTap: () => erpGo('/erp/assets/depreciation'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 2),
          VouchFlowPanel(
            title: 'ast.byClass'.tr,
            padded: false,
            child: Column(
              children: [
                for (final (i, c)
                    in d.byClass.where((c) => c.count > 0).indexed)
                  Container(
                    decoration: BoxDecoration(
                      border: i > 0
                          ? Border(
                              top: BorderSide(
                                color: t.border.withValues(alpha: .7),
                                width: .6,
                              ),
                            )
                          : null,
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 11, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                c.name,
                                style: VfType.small.copyWith(
                                  color: t.text,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Text(
                              finMoney(c.bookValue),
                              style: VfType.small.copyWith(
                                color: t.text,
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        FinProgress(
                          value: c.cost <= 0 ? 0 : c.bookValue / c.cost,
                          color: const Color(0xFFAC8E68),
                          height: 5,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'ast.classLine'.trParams({
                            'n': '${c.count}',
                            'cost': finCompact(c.cost),
                          }),
                          style: VfType.meta.copyWith(color: t.muted),
                        ),
                      ],
                    ),
                  ),
                if (d.byClass.every((c) => c.count == 0))
                  FinPanelEmpty('ast.noAssets'.tr),
              ],
            ),
          ),
          if (run != null) ...[
            erpGap,
            VouchFlowPanel(
              title: 'ast.lastRun'.tr,
              padded: false,
              actionLabel: 'erp.viewAll'.tr,
              onAction: () => erpGo('/erp/assets/depreciation'),
              child: _RunRow(run: run, divider: false, reload: reload),
            ),
          ],
          if (d.disposedThisYear.isNotEmpty) ...[
            erpGap,
            VouchFlowPanel(
              title: 'ast.disposedThisYear'.tr,
              padded: false,
              child: Column(
                children: [
                  for (var i = 0; i < d.disposedThisYear.length; i++)
                    VouchFlowListRow(
                      divider: i > 0,
                      icon: PhosphorIconsRegular.archive,
                      iconColor: t.muted,
                      title: d.disposedThisYear[i].name,
                      subtitle: [
                        d.disposedThisYear[i].tag,
                        if (d.disposedThisYear[i].disposalDate != null)
                          dashDate(d.disposedThisYear[i].disposalDate),
                      ].join(' · '),
                      trailing: FinTrailing(
                        amount: finMoney(
                          d.disposedThisYear[i].disposalGainLoss ?? 0,
                        ),
                        tone: (d.disposedThisYear[i].disposalGainLoss ?? 0) < 0
                            ? t.dangerStrong
                            : t.successStrong,
                      ),
                      onTap: () => _openAsset(d.disposedThisYear[i].id, reload),
                    ),
                ],
              ),
            ),
          ],
        ];
      },
    ),
  );
}

/// The fixed asset register.
class AssetRegisterPage extends StatelessWidget {
  const AssetRegisterPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'assets',
    permission: 'assets.view',
    builder: (_) => FinPagedList<FixedAsset>(
      title: 'ast.nav.register'.tr,
      searchPlaceholder: 'ast.search'.tr,
      filters: [
        FinFilter('inv.all'.tr, null),
        for (final s in ['active', 'draft', 'disposed'])
          FinFilter('fin.status.$s'.tr, s),
      ],
      load: (page, status, q) =>
          _repo.register(status: status, q: q.isEmpty ? null : q, page: page),
      emptyIcon: PhosphorIconsRegular.buildings,
      emptyTitle: 'ast.noAssets'.tr,
      row: (context, a, divider, reload) => AssetRow(
        asset: a,
        divider: divider,
        onTap: () => _openAsset(a.id, reload),
      ),
    ),
  );
}

class _RunRow extends StatelessWidget {
  const _RunRow({
    required this.run,
    required this.divider,
    required this.reload,
  });

  final DepreciationRun run;
  final bool divider;
  final VoidCallback reload;

  @override
  Widget build(BuildContext context) => VouchFlowListRow(
    divider: divider,
    icon: PhosphorIconsRegular.trendDown,
    iconColor: context.vf.infoStrong,
    title: finPeriod(run.period),
    subtitle: [
      run.number,
      'ast.assetsN'.trParams({'n': '${run.assetsCount}'}),
    ].join(' · '),
    trailing: FinTrailing(amount: finCompact(run.total)),
    onTap: () async {
      await Get.toNamed(Routes.astRun, arguments: run.id);
      reload();
    },
  );
}

/// The monthly depreciation runs, newest first.
class DepreciationRunsPage extends StatelessWidget {
  const DepreciationRunsPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'assets',
    permission: 'assets.view',
    builder: (_) => FinPagedList<DepreciationRun>(
      title: 'ast.nav.depreciation'.tr,
      subtitle: 'ast.runsSub'.tr,
      load: (page, _, _) => _repo.runs(page: page),
      emptyIcon: PhosphorIconsRegular.trendDown,
      emptyTitle: 'ast.noRuns'.tr,
      row: (context, r, divider, reload) =>
          _RunRow(run: r, divider: divider, reload: reload),
    ),
  );
}

/// One depreciation run: the charge per asset and the journal it posted.
class DepreciationRunPage extends StatelessWidget {
  const DepreciationRunPage({super.key, this.runId});

  final int? runId;

  @override
  Widget build(BuildContext context) {
    final id = runId ?? finArgId();
    return FinDetail<DepreciationRun>(
      load: () => _repo.run(id),
      title: (r) => r?.number ?? 'ast.run'.tr,
      children: (context, r, reload) => [
        FinHead(
          icon: PhosphorIconsRegular.trendDown,
          tint: context.vf.infoStrong,
          kicker: 'ast.run'.tr,
          title: finPeriod(r.period),
          subtitle: [
            r.number,
            if (r.runDate != null) dashDate(r.runDate),
          ].join(' · '),
          amount: finMoney(r.total, cents: true),
        ),
        VouchFlowPanel(
          title: 'ast.charges'.tr,
          trailing: Text(
            '${r.lines.length}',
            style: VfType.small.copyWith(
              color: context.vf.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          padded: false,
          child: Column(
            children: [
              for (var i = 0; i < r.lines.length; i++)
                FinAmountRow(
                  divider: i > 0,
                  label: r.lines[i].asset?.name ?? '-',
                  code: [
                    ?r.lines[i].asset?.code,
                    'ast.closingValue'.trParams({
                      'amount': finCompact(r.lines[i].closing),
                    }),
                  ].join(' · '),
                  amount: finMoney(r.lines[i].amount, cents: true),
                  onTap: r.lines[i].asset == null
                      ? null
                      : () => Get.toNamed(
                          Routes.astAsset,
                          arguments: r.lines[i].asset!.id,
                          preventDuplicates: false,
                        ),
                ),
              FinAmountRow(
                label: 'fin.total'.tr,
                amount: finMoney(r.total, cents: true),
                weight: FinRowWeight.total,
              ),
            ],
          ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'inv.details'.tr,
          child: Column(
            children: [
              if (r.creator != null) ErpFact('ast.runBy'.tr, r.creator!.name),
              if (r.journal != null)
                ErpFact(
                  'fin.journal'.tr,
                  r.journal!.name.isEmpty
                      ? '#${r.journal!.id}'
                      : r.journal!.name,
                  onTap: finJournalTap(r.journal!.id),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One asset: what it is, where and with whom, its value now, how it
/// depreciates, what has happened to it, and the months ahead (the web's
/// /erp/assets/register/[id]).
class AssetPage extends StatelessWidget {
  const AssetPage({super.key, this.assetId});

  final int? assetId;

  @override
  Widget build(BuildContext context) {
    final id = assetId ?? finArgId();
    return FinDetail<FixedAsset>(
      load: () => _repo.asset(id),
      title: (a) => a?.tag ?? 'ast.asset'.tr,
      children: (context, a, reload) {
        final t = context.vf;
        final upcoming = a.schedule.where((s) => !s.posted).take(12).toList();
        final posted = a.schedule.where((s) => s.posted).toList();
        return [
          FinHead(
            icon: PhosphorIconsRegular.buildings,
            tint: const Color(0xFFAC8E68),
            kicker: [a.tag, ?a.assetClass?.name].join(' · '),
            title: a.name,
            subtitle: [?a.location, ?a.custodian?.name].join(' · '),
            amount: a.status == 'disposed' ? null : finMoney(a.netBookValue),
            badges: [FinStatusBadge(a.status, large: true)],
          ),
          VouchFlowPanel(
            title: 'ast.value'.tr,
            padded: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FinAmountRow(
                  label: 'ast.cost'.tr,
                  amount: finMoney(a.cost, cents: true),
                  divider: false,
                ),
                FinAmountRow(
                  label: 'ast.accumulated'.tr,
                  amount: '-${finMoney(a.accumulated, cents: true)}',
                ),
                if (a.residualValue > 0)
                  FinAmountRow(
                    label: 'ast.residual'.tr,
                    amount: finMoney(a.residualValue, cents: true),
                  ),
                FinAmountRow(
                  label: 'ast.bookValue'.tr,
                  amount: finMoney(a.netBookValue, cents: true),
                  weight: FinRowWeight.total,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FinProgress(
                        value: a.depreciatedShare,
                        color: const Color(0xFFAC8E68),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'ast.writtenOff'.trParams({
                          'n': '${(a.depreciatedShare * 100).round()}',
                        }),
                        style: VfType.meta.copyWith(color: t.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (a.status == 'disposed') ...[
            erpGap,
            VouchFlowPanel(
              title: 'ast.disposal'.tr,
              child: Column(
                children: [
                  if (a.disposalDate != null)
                    ErpFact('inv.date'.tr, dashDate(a.disposalDate)),
                  if (a.disposalProceeds != null)
                    ErpFact('ast.proceeds'.tr, finMoney(a.disposalProceeds)),
                  if (a.disposalGainLoss != null)
                    ErpFact('ast.gainLoss'.tr, finMoney(a.disposalGainLoss)),
                  if (a.disposalReason != null)
                    ErpFact('inv.reason'.tr, a.disposalReason!),
                ],
              ),
            ),
          ],
          erpGap,
          VouchFlowPanel(
            title: 'ast.assignment'.tr,
            child: Column(
              children: [
                ErpFact('ast.custodian'.tr, a.custodian?.name ?? '-'),
                ErpFact('ast.location'.tr, a.location ?? '-'),
                if (a.serialNumber != null)
                  ErpFact('ast.serial'.tr, a.serialNumber!),
                if (a.supplier != null)
                  ErpFact('prc.supplier'.tr, a.supplier!.name),
                if (a.acquisitionDate != null)
                  ErpFact('ast.acquired'.tr, dashDate(a.acquisitionDate)),
                if (a.funding != null)
                  ErpFact('ast.funding'.tr, 'ast.funding.${a.funding}'.tr),
              ],
            ),
          ),
          erpGap,
          VouchFlowPanel(
            title: 'ast.depreciation'.tr,
            child: Column(
              children: [
                if (a.method != null)
                  ErpFact('ast.method'.tr, 'ast.method.${a.method}'.tr),
                if (a.rate != null && a.method == 'reducing_balance')
                  ErpFact(
                    'ast.rate'.tr,
                    'ast.ratePerYear'.trParams({'n': ErpFmtPct.of(a.rate!)}),
                  ),
                if (a.usefulLifeMonths != null)
                  ErpFact(
                    'ast.life'.tr,
                    'ast.lifeYears'.trParams({
                      'n': ErpFmtPct.of(a.usefulLifeMonths! / 12),
                    }),
                  ),
                ErpFact('ast.monthsPosted'.tr, '${posted.length}'),
              ],
            ),
          ),
          if (upcoming.isNotEmpty) ...[
            erpGap,
            VouchFlowPanel(
              title: 'ast.schedule'.tr,
              subtitle: 'ast.scheduleSub'.tr,
              padded: false,
              child: Column(
                children: [
                  for (var i = 0; i < upcoming.length; i++)
                    FinAmountRow(
                      divider: i > 0,
                      label: finPeriod(upcoming[i].period),
                      amount: finMoney(upcoming[i].amount),
                      secondary: 'ast.closingValue'.trParams({
                        'amount': finCompact(upcoming[i].closing),
                      }),
                    ),
                ],
              ),
            ),
          ],
          if (a.depreciation.isNotEmpty) ...[
            erpGap,
            VouchFlowPanel(
              title: 'ast.posted'.tr,
              padded: false,
              child: Column(
                children: [
                  for (var i = 0; i < a.depreciation.length; i++)
                    FinAmountRow(
                      divider: i > 0,
                      label: finPeriod(a.depreciation[i].period),
                      code: a.depreciation[i].run?.name,
                      amount: finMoney(a.depreciation[i].amount),
                      secondary: 'ast.closingValue'.trParams({
                        'amount': finCompact(a.depreciation[i].closing),
                      }),
                      onTap: a.depreciation[i].run == null
                          ? null
                          : () => Get.toNamed(
                              Routes.astRun,
                              arguments: a.depreciation[i].run!.id,
                              preventDuplicates: false,
                            ),
                    ),
                ],
              ),
            ),
          ],
          if (a.events.isNotEmpty) ...[
            erpGap,
            VouchFlowPanel(
              title: 'ast.history'.tr,
              padded: false,
              child: Column(
                children: [
                  for (var i = 0; i < a.events.length; i++)
                    _EventRow(event: a.events[i], divider: i > 0),
                ],
              ),
            ),
          ],
        ];
      },
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.divider});

  final AssetEvent event;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final e = event;
    final moves = [
      if (e.toLocation != null)
        e.fromLocation == null
            ? e.toLocation!
            : '${e.fromLocation} > ${e.toLocation}',
      if (e.toCustodian != null)
        e.fromCustodian == null
            ? e.toCustodian!.name
            : '${e.fromCustodian!.name} > ${e.toCustodian!.name}',
    ];
    return VouchFlowListRow(
      divider: divider,
      icon: switch (e.type) {
        'transferred' => PhosphorIconsRegular.arrowsLeftRight,
        'capitalised' => PhosphorIconsRegular.sealCheck,
        'disposed' => PhosphorIconsRegular.archive,
        _ => PhosphorIconsRegular.plusCircle,
      },
      iconColor: e.type == 'disposed' ? t.muted : t.primary,
      title: 'ast.event.${e.type}'.tr,
      titleMaxLines: 2,
      subtitle: [
        if (e.date != null) dashDate(e.date),
        ...moves,
        ?e.user?.name,
        ?e.notes,
      ].join(' · '),
      trailing: e.amount == null
          ? null
          : FinTrailing(amount: finCompact(e.amount!)),
    );
  }
}

/// "12.5", "10": a rate or a count of years without trailing zeros.
abstract class ErpFmtPct {
  static String of(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}
