import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/finance_models.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/finance_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../erp/erp_widgets.dart';
import 'fin_widgets.dart';
import 'finance_app.dart';
import 'finance_widgets.dart';

/// The Finance home: cash and bank in hand, what customers owe and what is
/// owed to suppliers, the month's profit against last month, each cash
/// account's balance, what is waiting to be posted, and the latest
/// cashbook entries (the web's /erp/finance).
class FinanceOverviewPage extends StatelessWidget {
  const FinanceOverviewPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'accounting',
    permission: 'finance.view',
    builder: (_) => FinAsync<FinanceOverview>(
      load: FinanceRepository.to.overview,
      builder: (context, d, reload) => _children(context, d, reload),
    ),
  );

  List<Widget> _children(
    BuildContext context,
    FinanceOverview d,
    Future<void> Function() reload,
  ) {
    final t = context.vf;
    final erp = ErpService.to;
    final actions = financeCreateActions
        .where((a) => a.permission == null || erp.can(a.permission!))
        .toList();
    final net = d.month.netProfit;
    final drafts = d.draftCashbook + d.draftTransfers;

    return [
      ErpPageTitle(
        'area.finance'.tr,
        subtitle: d.currentPeriod == null
            ? null
            : 'fin.periodLine'.trParams({
                'period': finPeriod(d.currentPeriod!),
                'state': d.currentClosed ? 'fin.closed'.tr : 'fin.open'.tr,
              }),
      ),
      FinFigures(
        children: [
          VouchFlowFigureGrid(
            children: [
              VouchFlowFigureCard(
                label: 'fin.cashAndBank'.tr,
                value: finCompact(d.cashTotal),
                hint: finMoney(d.cashTotal),
                icon: PhosphorIconsRegular.wallet,
                onTap: () => erpGo('/erp/finance/banks'),
              ),
              VouchFlowFigureCard(
                label: 'fin.receivables'.tr,
                value: finCompact(d.receivables),
                hint: 'fin.receivablesHint'.tr,
                icon: PhosphorIconsRegular.arrowCircleDown,
                tone: VfTone.info,
              ),
              VouchFlowFigureCard(
                label: 'fin.payables'.tr,
                value: finCompact(d.payables),
                hint: 'fin.payablesHint'.tr,
                icon: PhosphorIconsRegular.arrowCircleUp,
                tone: VfTone.warn,
                onTap: erp.has('procurement') && erp.can('procurement.view')
                    ? () => erpGo('/erp/procurement/ageing')
                    : null,
              ),
              VouchFlowFigureCard(
                label: 'fin.netThisMonth'.tr,
                value: finCompact(net),
                hint: 'fin.lastMonthAmount'.trParams({
                  'amount': finCompact(d.priorMonth.netProfit),
                }),
                icon: net >= 0
                    ? PhosphorIconsRegular.trendUp
                    : PhosphorIconsRegular.trendDown,
                tone: net >= 0 ? VfTone.ok : VfTone.bad,
                onTap: erp.can('finance.statements')
                    ? () => erpGo('/erp/finance/reports')
                    : null,
              ),
            ],
          ),
        ],
      ),
      const SizedBox(height: 2),
      VouchFlowPanel(
        title: 'fin.thisMonth'.tr,
        subtitle: 'fin.vsLastMonth'.tr,
        padded: false,
        child: Column(
          children: [
            FinAmountRow(
              label: 'fin.pl.income'.tr,
              amount: finMoney(d.month.income),
              secondary: finMoney(d.priorMonth.income),
              divider: false,
            ),
            FinAmountRow(
              label: 'fin.pl.cost_of_sales'.tr,
              amount: finMoney(d.month.costOfSales),
              secondary: finMoney(d.priorMonth.costOfSales),
            ),
            FinAmountRow(
              label: 'fin.pl.gross_profit'.tr,
              amount: finMoney(d.month.grossProfit),
              secondary: finMoney(d.priorMonth.grossProfit),
              weight: FinRowWeight.subtotal,
            ),
            FinAmountRow(
              label: 'fin.pl.operating_expenses'.tr,
              amount: finMoney(d.month.operatingExpenses),
              secondary: finMoney(d.priorMonth.operatingExpenses),
            ),
            FinAmountRow(
              label: 'fin.pl.net_profit'.tr,
              amount: finMoney(net),
              secondary: finMoney(d.priorMonth.netProfit),
              weight: FinRowWeight.total,
              tone: net < 0 ? t.dangerStrong : t.successStrong,
            ),
          ],
        ),
      ),
      erpGap,
      VouchFlowPanel(
        title: 'fin.cashPosition'.tr,
        padded: false,
        actionLabel: 'erp.viewAll'.tr,
        onAction: () => erpGo('/erp/finance/banks'),
        child: d.cash.isEmpty
            ? FinPanelEmpty('fin.noAccounts'.tr)
            : Column(
                children: [
                  for (var i = 0; i < d.cash.length; i++)
                    VouchFlowListRow(
                      divider: i > 0,
                      icon: cashTypeIcon(d.cash[i].type),
                      iconColor: cashTypeTint(t, d.cash[i].type),
                      title: d.cash[i].name,
                      subtitle:
                          '${d.cash[i].code} · ${'fin.type.${d.cash[i].type}'.tr}',
                      trailing: FinTrailing(
                        amount: finMoney(d.cash[i].balance),
                        tone: d.cash[i].balance < 0 ? t.dangerStrong : null,
                      ),
                      onTap: d.cash[i].bankAccountId == null
                          ? null
                          : () async {
                              await Get.toNamed(
                                Routes.finBank,
                                arguments: d.cash[i].bankAccountId,
                              );
                              await reload();
                            },
                    ),
                ],
              ),
      ),
      if (actions.isNotEmpty ||
          drafts > 0 ||
          d.openReconciliations.isNotEmpty) ...[
        erpGap,
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
                  trailing: finCaret(context),
                  onTap: () async {
                    await erpCreate(actions[i]);
                    await reload();
                  },
                ),
              if (d.draftCashbook > 0)
                VouchFlowListRow(
                  divider: actions.isNotEmpty,
                  icon: PhosphorIconsRegular.fileDashed,
                  iconColor: t.infoStrong,
                  title: 'fin.draftsToPost'.trParams({
                    'n': '${d.draftCashbook}',
                  }),
                  subtitle: 'fin.draftsToPostHint'.tr,
                  trailing: finCaret(context),
                  onTap: () => erpGo('/erp/finance/cashbook'),
                ),
              for (final r in d.openReconciliations)
                VouchFlowListRow(
                  icon: PhosphorIconsRegular.checks,
                  iconColor: t.warningStrong,
                  title: 'fin.reconciliationOpen'.trParams({'bank': r.name}),
                  subtitle: '${r.code ?? ''} · ${'fin.finishOnWeb'.tr}',
                ),
            ],
          ),
        ),
      ],
      erpGap,
      VouchFlowPanel(
        title: 'fin.recentCashbook'.tr,
        padded: false,
        actionLabel: 'erp.viewAll'.tr,
        onAction: () => erpGo('/erp/finance/cashbook'),
        child: d.recent.isEmpty
            ? FinPanelEmpty('fin.noCashbook'.tr)
            : Column(
                children: [
                  for (var i = 0; i < d.recent.length; i++)
                    CashbookRow(
                      entry: d.recent[i],
                      divider: i > 0,
                      onTap: () async {
                        await Get.toNamed(
                          Routes.finCashbookEntry,
                          arguments: d.recent[i].id,
                        );
                        await reload();
                      },
                    ),
                ],
              ),
      ),
    ];
  }
}
