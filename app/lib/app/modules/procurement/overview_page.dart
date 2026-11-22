import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/models/finance_models.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/procurement_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../erp/erp_widgets.dart';
import '../finance/fin_widgets.dart';
import 'procurement_app.dart';
import 'procurement_widgets.dart';

/// The Procurement home: what is waiting (requisitions and orders to
/// approve, invoices to match), what is owed and overdue, what you can
/// prepare, and the latest orders (the web's /erp/procurement).
class ProcurementOverviewPage extends StatelessWidget {
  const ProcurementOverviewPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'procurement',
    permission: 'procurement.view',
    builder: (_) => FinAsync<ProcurementOverview>(
      load: ProcurementRepository.to.overview,
      builder: (context, data, reload) => _children(context, data, reload),
    ),
  );

  List<Widget> _children(
    BuildContext context,
    ProcurementOverview d,
    Future<void> Function() reload,
  ) {
    final erp = ErpService.to;
    final actions = procurementCreateActions
        .where((a) => a.permission == null || erp.can(a.permission!))
        .toList();

    Future<void> open(int id) async {
      await Get.toNamed(Routes.prcOrder, arguments: id);
      await reload();
    }

    return [
      ErpPageTitle('area.procurement'.tr, subtitle: 'prc.overviewSub'.tr),
      FinFigures(
        children: [
          VouchFlowFigureGrid(
            children: [
              VouchFlowFigureCard(
                label: 'prc.openRequisitions'.tr,
                value: '${d.openRequisitions}',
                hint: 'prc.awaitingApprovalN'.trParams({
                  'n': '${d.requisitionsAwaiting}',
                }),
                icon: PhosphorIconsRegular.clipboardText,
                tone: d.requisitionsAwaiting > 0 ? VfTone.warn : VfTone.neutral,
                onTap: () => erpGo('/erp/procurement/requisitions'),
              ),
              VouchFlowFigureCard(
                label: 'prc.ordersAwaiting'.tr,
                value: '${d.ordersAwaiting}',
                hint: 'prc.toReceiveN'.trParams({'n': '${d.ordersToReceive}'}),
                icon: PhosphorIconsRegular.sealCheck,
                tone: d.ordersAwaiting > 0 ? VfTone.warn : VfTone.ok,
                onTap: () => erpGo('/erp/procurement/orders'),
              ),
              VouchFlowFigureCard(
                label: 'prc.invoicesToMatch'.tr,
                value: '${d.invoicesToMatch}',
                hint: 'prc.withVarianceN'.trParams({
                  'n': '${d.invoicesWithVariance}',
                }),
                icon: PhosphorIconsRegular.scales,
                tone: d.invoicesWithVariance > 0 ? VfTone.bad : VfTone.neutral,
                onTap: () => erpGo('/erp/procurement/invoices'),
              ),
              VouchFlowFigureCard(
                label: 'prc.payables'.tr,
                value: finCompact(d.payablesOutstanding),
                hint: 'prc.overdueAmount'.trParams({
                  'amount': finCompact(d.payablesOverdue),
                }),
                icon: PhosphorIconsRegular.wallet,
                tone: d.payablesOverdue > 0 ? VfTone.bad : VfTone.ok,
                onTap: () => erpGo('/erp/procurement/ageing'),
              ),
            ],
          ),
        ],
      ),
      const SizedBox(height: 2),
      VouchFlowPanel(
        title: 'prc.thisPeriod'.tr,
        padded: false,
        child: Column(
          children: [
            FinAmountRow(
              label: 'prc.dueThisWeek'.tr,
              amount: finMoney(d.payablesDue7Days),
              divider: false,
            ),
            FinAmountRow(
              label: 'prc.orderedThisMonth'.tr,
              amount: finMoney(d.orderedThisMonth),
            ),
          ],
        ),
      ),
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
            VouchFlowListRow(
              divider: actions.isNotEmpty,
              icon: PhosphorIconsRegular.hourglassMedium,
              title: 'prc.nav.ageing'.tr,
              subtitle: 'prc.ageingHint'.tr,
              trailing: finCaret(context),
              onTap: () => erpGo('/erp/procurement/ageing'),
            ),
            if (erp.can('suppliers.view'))
              VouchFlowListRow(
                icon: PhosphorIconsRegular.fileText,
                title: 'prc.statements'.tr,
                subtitle: 'prc.statementsHint'.tr,
                trailing: finCaret(context),
                onTap: () => erpGo('/erp/suppliers'),
              ),
          ],
        ),
      ),
      erpGap,
      VouchFlowPanel(
        title: 'prc.recentOrders'.tr,
        padded: false,
        actionLabel: 'erp.viewAll'.tr,
        onAction: () => erpGo('/erp/procurement/orders'),
        child: d.recentOrders.isEmpty
            ? FinPanelEmpty('prc.noOrders'.tr)
            : Column(
                children: [
                  for (var i = 0; i < d.recentOrders.length; i++)
                    OrderRow(
                      order: d.recentOrders[i],
                      divider: i > 0,
                      onTap: () => open(d.recentOrders[i].id),
                    ),
                ],
              ),
      ),
    ];
  }
}
