import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/finance_models.dart';
import '../../data/services/procurement_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate, dashDateTime;
import '../erp/erp_widgets.dart';
import '../finance/fin_widgets.dart';
import '../inventory/inventory_widgets.dart' show ErpFact;

/// One supplier payment: from which account, how, and the invoices it
/// settled (the web's /erp/procurement/payments/[id]).
class SupplierPaymentPage extends StatelessWidget {
  const SupplierPaymentPage({super.key, this.paymentId});

  final int? paymentId;

  @override
  Widget build(BuildContext context) {
    final id = paymentId ?? finArgId();
    return FinDetail<SupplierPayment>(
      load: () => ProcurementRepository.to.payment(id),
      title: (p) => p?.number ?? 'prc.payment'.tr,
      children: (context, p, reload) {
        final t = context.vf;
        return [
          FinHead(
            icon: PhosphorIconsRegular.handCoins,
            tint: t.successStrong,
            kicker: 'prc.payment'.tr,
            title: p.number,
            subtitle: [?p.supplier?.name, if (p.paymentDate != null) dashDate(p.paymentDate)].join(' · '),
            amount: finMoney(p.amount, cents: true),
            badges: [FinStatusBadge(p.status, large: true)],
          ),
          VouchFlowPanel(
            title: 'prc.settles'.tr,
            padded: false,
            child: p.allocations.isEmpty
                ? FinPanelEmpty('prc.noAllocations'.tr)
                : Column(
                    children: [
                      for (var n = 0; n < p.allocations.length; n++)
                        if (p.allocations[n].invoice case final i?)
                          VouchFlowListRow(
                            divider: n > 0,
                            icon: PhosphorIconsRegular.receipt,
                            iconColor: t.warningStrong,
                            title: i.supplierInvoiceNumber ?? i.number,
                            subtitle: [
                              i.number,
                              if (i.outstanding > 0) 'prc.stillOwed'.trParams({'amount': finMoney(i.outstanding)}),
                            ].join(' · '),
                            trailing: FinTrailing(
                              amount: finMoney(p.allocations[n].amount),
                              badge: i.paymentStatus == null ? null : FinStatusBadge(i.paymentStatus!),
                            ),
                            onTap: () => Get.toNamed(Routes.prcInvoice, arguments: i.id, preventDuplicates: false),
                          ),
                    ],
                  ),
          ),
          erpGap,
          VouchFlowPanel(
            title: 'inv.details'.tr,
            child: Column(
              children: [
                ErpFact('prc.supplier'.tr, p.supplier?.name ?? '-'),
                if (p.account != null) ErpFact('prc.paidFrom'.tr, accountLabel(p.account)),
                if (p.method != null) ErpFact('prc.method'.tr, 'fin.method.${p.method}'.tr),
                if (p.reference != null) ErpFact('inv.reference'.tr, p.reference!),
                if (p.creator != null) ErpFact('inv.prepared'.tr, p.creator!.name),
                if (p.poster != null)
                  ErpFact('inv.postedBy'.tr, [p.poster!.name, if (p.postedAt != null) dashDateTime(p.postedAt)].join(' · ')),
                if (p.journal != null) ErpFact('fin.journal'.tr, p.journal!.name, onTap: finJournalTap(p.journal!.id)),
                if (p.notes != null) ErpFact('prc.notes'.tr, p.notes!),
              ],
            ),
          ),
        ];
      },
    );
  }
}
