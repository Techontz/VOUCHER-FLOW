import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart';
import '../../data/models/finance_models.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/procurement_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart' show showToast;
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate, dashDateTime;
import '../erp/erp_widgets.dart';
import '../finance/fin_widgets.dart';
import '../inventory/inventory_widgets.dart' show ErpFact;
import 'procurement_widgets.dart';

/// One purchase order: supplier, lines with what has arrived, the amounts,
/// the invoices against it and its approvals, with Approve and Reject for
/// an approver who did not raise it (the web's /erp/procurement/orders/[id]).
class PurchaseOrderPage extends StatelessWidget {
  const PurchaseOrderPage({super.key, this.orderId});

  final int? orderId;

  @override
  Widget build(BuildContext context) {
    final id = orderId ?? finArgId();
    return FinDetail<PurchaseOrder>(
      load: () => ProcurementRepository.to.order(id),
      title: (o) => o?.number ?? 'prc.order'.tr,
      children: (context, o, reload) => _body(context, o),
      actions: (context, o, reload) => _actions(context, o, reload),
    );
  }

  List<Widget> _actions(BuildContext context, PurchaseOrder o, Future<void> Function() reload) {
    final erp = ErpService.to;
    final repo = ProcurementRepository.to;
    if (o.status != 'submitted' || !erp.can('procurement.approve') || o.createdBy == finMe()) return const [];
    final summary = [
      VfSummaryRow('prc.supplier'.tr, o.supplier?.name ?? '-'),
      VfSummaryRow('fin.total'.tr, finMoney(o.total)),
    ];
    Future<void> decide(Future<String?> pending) async {
      final message = await pending;
      if (message == null) return;
      showToast(message.isEmpty ? 'fin.done'.tr : message);
      await reload();
    }

    return [
      VouchFlowButton(
        label: 'prc.reject'.tr,
        variant: VfButtonVariant.secondary,
        onPressed: () => decide(
          finConfirm(
            context,
            title: 'prc.rejectQ'.trParams({'number': o.number}),
            subtitle: 'prc.rejectOrderSub'.tr,
            icon: PhosphorIconsRegular.xCircle,
            tone: VfTone.warn,
            summary: summary,
            comment: FinComment.required,
            danger: true,
            confirmLabel: 'prc.reject'.tr,
            run: (c) => repo.rejectOrder(o.id, c),
          ),
        ),
      ),
      VouchFlowButton(
        label: 'prc.approve'.tr,
        icon: PhosphorIconsRegular.sealCheck,
        onPressed: () => decide(
          finConfirm(
            context,
            title: 'prc.approveQ'.trParams({'number': o.number}),
            subtitle: 'prc.approveOrderSub'.tr,
            icon: PhosphorIconsRegular.sealCheck,
            summary: summary,
            comment: FinComment.optional,
            confirmLabel: 'prc.approve'.tr,
            run: (c) => repo.approveOrder(o.id, c),
          ),
        ),
      ),
    ];
  }

  List<Widget> _body(BuildContext context, PurchaseOrder o) {
    final t = context.vf;
    final ordered = o.lines.fold<double>(0, (s, l) => s + l.quantity);
    final received = o.lines.fold<double>(0, (s, l) => s + (l.receivedQuantity ?? 0));
    final share = ordered <= 0 ? 0.0 : (received / ordered).clamp(0.0, 1.0);
    final receiving = ['sent', 'partially_received', 'received', 'closed', 'approved'].contains(o.status);
    return [
      FinHead(
        icon: PhosphorIconsRegular.shoppingCart,
        kicker: 'prc.order'.tr,
        title: o.number,
        subtitle: [?o.supplier?.name, if (o.orderDate != null) dashDate(o.orderDate)].join(' · '),
        amount: finMoney(o.total),
        badges: [FinStatusBadge(o.status, large: true)],
      ),
      if (o.status == 'cancelled' && o.cancelReason != null) ...[
        VouchFlowAlert(tone: VfTone.neutral, icon: PhosphorIconsRegular.xCircle, title: 'fin.status.cancelled'.tr, message: o.cancelReason!),
        erpGap,
      ],
      if (receiving && ordered > 0) ...[
        VouchFlowPanel(
          title: 'prc.receiving'.tr,
          trailing: Text(
            '${(share * 100).round()}%',
            style: VfType.small.copyWith(color: t.muted, fontWeight: FontWeight.w600),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14, top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FinProgress(value: share, color: share >= 1 ? t.successStrong : t.primary),
                const SizedBox(height: 8),
                Text(
                  'prc.receivedOf'.trParams({'n': ErpFmt.qty(received), 'of': ErpFmt.qty(ordered)}),
                  style: VfType.small.copyWith(color: t.text2),
                ),
              ],
            ),
          ),
        ),
        erpGap,
      ],
      VouchFlowPanel(
        title: 'prc.lines'.tr,
        trailing: Text('${o.lines.length}', style: VfType.small.copyWith(color: t.muted, fontWeight: FontWeight.w600)),
        padded: false,
        child: Column(
          children: [
            for (var i = 0; i < o.lines.length; i++) ProcLineRow(line: o.lines[i], divider: i > 0, showReceived: true),
            FinAmountRow(label: 'prc.subtotal'.tr, amount: finMoney(o.subtotal, cents: true)),
            FinAmountRow(label: 'prc.vat'.tr, amount: finMoney(o.vatAmount, cents: true)),
            FinAmountRow(label: 'fin.total'.tr, amount: finMoney(o.total, cents: true), weight: FinRowWeight.total),
          ],
        ),
      ),
      erpGap,
      VouchFlowPanel(
        title: 'inv.details'.tr,
        child: Column(
          children: [
            ErpFact('prc.supplier'.tr, o.supplier?.name ?? '-'),
            if (o.warehouse != null) ErpFact('prc.deliverTo'.tr, o.warehouse!.name),
            if (o.expectedDate != null) ErpFact('prc.expected'.tr, dashDate(o.expectedDate)),
            if (o.paymentTerms != null) ErpFact('prc.terms'.tr, o.paymentTerms!),
            if (o.creator != null) ErpFact('inv.prepared'.tr, o.creator!.name),
            if (o.requisition != null)
              ErpFact(
                'prc.requisition'.tr,
                o.requisition!.name,
                onTap: () => Get.toNamed(Routes.prcRequisition, arguments: o.requisition!.id, preventDuplicates: false),
              ),
            for (final inv in o.invoices)
              ErpFact('prc.invoice'.tr, inv.name, onTap: () => Get.toNamed(Routes.prcInvoice, arguments: inv.id, preventDuplicates: false)),
            if (o.notes != null) ErpFact('prc.notes'.tr, o.notes!),
          ],
        ),
      ),
      erpGap,
      VouchFlowPanel(title: 'prc.approvals'.tr, padded: false, child: ApprovalTrail(approvals: o.approvals)),
      if (o.approvals.isNotEmpty && o.approvals.last.at != null) ...[
        const SizedBox(height: 6),
        Text(
          'prc.lastDecision'.trParams({'when': dashDateTime(o.approvals.last.at)}),
          textAlign: TextAlign.center,
          style: VfType.meta.copyWith(color: t.muted),
        ),
      ],
    ];
  }
}
