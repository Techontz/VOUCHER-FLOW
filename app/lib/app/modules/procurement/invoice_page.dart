import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
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

/// A supplier invoice with the payment voucher raised for it, if any.
class _InvoiceView {
  const _InvoiceView(this.invoice, this.voucher);

  final SupplierInvoice invoice;
  final VoucherLink? voucher;
}

/// One supplier invoice: the three-way match line by line, the amounts,
/// what has been paid against it and, for a posted invoice still owed,
/// "Raise payment voucher", which sends the debt through the company's own
/// VouchFlow approval route (the web's /erp/procurement/invoices/[id]).
class SupplierInvoicePage extends StatelessWidget {
  const SupplierInvoicePage({super.key, this.invoiceId});

  final int? invoiceId;

  Future<_InvoiceView> _load(int id) async {
    final repo = ProcurementRepository.to;
    final results = await Future.wait<Object?>([
      repo.invoice(id),
      // The link is a convenience: an invoice still opens without it.
      repo.voucherFor(id).then<VoucherLink?>((v) => v, onError: (_) => null),
    ]);
    return _InvoiceView(results[0]! as SupplierInvoice, results[1] as VoucherLink?);
  }

  @override
  Widget build(BuildContext context) {
    final id = invoiceId ?? finArgId();
    return FinDetail<_InvoiceView>(
      load: () => _load(id),
      title: (v) => v?.invoice.number ?? 'prc.invoice'.tr,
      children: (context, v, reload) => _body(context, v, reload),
      actions: (context, v, reload) => _actions(context, v, reload),
    );
  }

  /// Raises the voucher and opens it, as the web does.
  Future<void> _raise(BuildContext context, SupplierInvoice i, Future<void> Function() reload) async {
    final number = await finConfirm(
      context,
      title: 'prc.raiseVoucherQ'.trParams({'amount': finMoney(i.outstanding)}),
      subtitle: 'prc.raiseVoucherSub'.tr,
      icon: PhosphorIconsRegular.receipt,
      summary: [
        VfSummaryRow('prc.supplier'.tr, i.supplier?.name ?? '-'),
        VfSummaryRow('prc.invoice'.tr, i.supplierInvoiceNumber ?? i.number),
        VfSummaryRow('prc.outstanding'.tr, finMoney(i.outstanding)),
      ],
      confirmLabel: 'prc.raiseVoucher'.tr,
      run: (_) async {
        final v = await ProcurementRepository.to.raiseVoucher(i.id);
        return '${v.id}|${v.number}';
      },
    );
    if (number == null) return;
    final parts = number.split('|');
    showToast('prc.voucherRaised'.tr, body: 'prc.voucherRaisedBody'.trParams({'number': parts.last}));
    await Get.toNamed(Routes.voucher, arguments: int.tryParse(parts.first));
    await reload();
  }

  List<Widget> _actions(BuildContext context, _InvoiceView v, Future<void> Function() reload) {
    final erp = ErpService.to;
    final i = v.invoice;
    return [
      if (i.status == 'awaiting_approval' && erp.can('procurement.approve') && i.createdBy != finMe())
        VouchFlowButton(
          label: 'prc.approveVariance'.tr,
          icon: PhosphorIconsRegular.sealCheck,
          onPressed: () async {
            final message = await finConfirm(
              context,
              title: 'prc.approveVarianceQ'.trParams({'number': i.number}),
              subtitle: 'prc.approveVarianceSub'.tr,
              icon: PhosphorIconsRegular.sealCheck,
              tone: VfTone.warn,
              summary: [
                VfSummaryRow('prc.supplier'.tr, i.supplier?.name ?? '-'),
                VfSummaryRow('prc.priceVariance'.tr, finMoney(i.priceVariance, cents: true)),
              ],
              comment: FinComment.optional,
              confirmLabel: 'prc.approve'.tr,
              run: (c) => ProcurementRepository.to.approveInvoice(i.id, c),
            );
            if (message == null) return;
            showToast(message.isEmpty ? 'fin.done'.tr : message);
            await reload();
          },
        ),
      if (i.isPosted && i.outstanding > 0 && erp.can('procurement.pay') && v.voucher == null)
        VouchFlowButton(
          label: 'prc.raiseVoucher'.tr,
          icon: PhosphorIconsRegular.receipt,
          onPressed: () => _raise(context, i, reload),
        ),
    ];
  }

  List<Widget> _body(BuildContext context, _InvoiceView v, Future<void> Function() reload) {
    final t = context.vf;
    final i = v.invoice;
    final voucher = v.voucher;
    return [
      FinHead(
        icon: PhosphorIconsRegular.receipt,
        tint: i.isOverdue ? t.dangerStrong : t.warningStrong,
        kicker: '${'prc.invoice'.tr} · ${i.number}',
        title: i.supplierInvoiceNumber ?? i.number,
        subtitle: [
          ?i.supplier?.name,
          if (i.invoiceDate != null) dashDate(i.invoiceDate),
          if (i.dueDate != null) 'prc.dueOn'.trParams({'date': dashDate(i.dueDate)}),
        ].join(' · '),
        amount: finMoney(i.total),
        badges: [
          FinStatusBadge(i.status, large: true),
          if (i.isPosted && i.paymentStatus != null) FinStatusBadge(i.paymentStatus!, large: true),
          if (i.isOverdue) FinStatusBadge('overdue', large: true),
        ],
      ),
      if (voucher != null) ...[
        VouchFlowPanel(
          title: 'prc.paymentVoucher'.tr,
          padded: false,
          child: VouchFlowListRow(
            divider: false,
            icon: PhosphorIconsRegular.receipt,
            title: 'prc.voucherOpen'.trParams({'number': voucher.number}),
            subtitle: 'prc.voucherOpenHint'.tr,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (voucher.status != null) ...[
                  ConstrainedBox(constraints: const BoxConstraints(maxWidth: 96), child: FinStatusBadge(voucher.status!)),
                  const SizedBox(width: 8),
                ],
                finCaret(context),
              ],
            ),
            onTap: () async {
              await Get.toNamed(Routes.voucher, arguments: voucher.id);
              await reload();
            },
          ),
        ),
        erpGap,
      ],
      if (i.status == 'awaiting_approval') ...[
        VouchFlowAlert(
          tone: VfTone.warn,
          icon: PhosphorIconsRegular.warning,
          title: 'prc.varianceTitle'.tr,
          message: 'prc.varianceBody'.tr,
        ),
        erpGap,
      ],
      VouchFlowPanel(
        title: 'prc.threeWayMatch'.tr,
        subtitle: 'prc.threeWayMatchSub'.tr,
        padded: false,
        child: Column(
          children: [
            for (var n = 0; n < i.lines.length; n++) ProcLineRow(line: i.lines[n], divider: n > 0, showMatch: true),
          ],
        ),
      ),
      erpGap,
      VouchFlowPanel(
        title: 'prc.amounts'.tr,
        padded: false,
        child: Column(
          children: [
            FinAmountRow(label: 'prc.subtotal'.tr, amount: finMoney(i.subtotal, cents: true), divider: false),
            FinAmountRow(label: 'prc.vat'.tr, amount: finMoney(i.vatAmount, cents: true)),
            FinAmountRow(label: 'fin.total'.tr, amount: finMoney(i.total, cents: true), weight: FinRowWeight.subtotal),
            if (i.priceVariance != 0)
              FinAmountRow(label: 'prc.priceVariance'.tr, amount: finMoney(i.priceVariance, cents: true), tone: t.dangerStrong),
            FinAmountRow(label: 'prc.paid'.tr, amount: finMoney(i.amountPaid, cents: true)),
            if (i.isPosted)
              FinAmountRow(
                label: 'prc.outstanding'.tr,
                amount: finMoney(i.outstanding, cents: true),
                weight: FinRowWeight.total,
                tone: i.isOverdue ? t.dangerStrong : null,
              ),
          ],
        ),
      ),
      erpGap,
      VouchFlowPanel(
        title: 'prc.paymentsMade'.tr,
        padded: false,
        child: i.allocations.isEmpty
            ? FinPanelEmpty('prc.noPaymentsYet'.tr)
            : Column(
                children: [
                  for (var n = 0; n < i.allocations.length; n++)
                    if (i.allocations[n].payment case final p?)
                      VouchFlowListRow(
                        divider: n > 0,
                        icon: PhosphorIconsRegular.handCoins,
                        iconColor: t.successStrong,
                        title: p.number,
                        subtitle: [if (p.paymentDate != null) dashDate(p.paymentDate), finMoney(i.allocations[n].amount)].join(' · '),
                        trailing: FinStatusBadge(p.status),
                        onTap: () => Get.toNamed(Routes.prcPayment, arguments: p.id, preventDuplicates: false),
                      ),
                ],
              ),
      ),
      erpGap,
      VouchFlowPanel(
        title: 'inv.details'.tr,
        child: Column(
          children: [
            if (i.order != null)
              ErpFact('prc.order'.tr, i.order!.name, onTap: () => Get.toNamed(Routes.prcOrder, arguments: i.order!.id, preventDuplicates: false)),
            if (i.creator != null)
              ErpFact('inv.prepared'.tr, [i.creator!.name, if (i.createdAt != null) dashDateTime(i.createdAt)].join(' · ')),
            if (i.varianceApprover != null) ErpFact('prc.varianceApprovedBy'.tr, i.varianceApprover!.name),
            if (i.poster != null) ErpFact('inv.postedBy'.tr, [i.poster!.name, if (i.postedAt != null) dashDateTime(i.postedAt)].join(' · ')),
            if (i.journal != null)
              ErpFact('fin.journal'.tr, i.journal!.name, onTap: finJournalTap(i.journal!.id)),
            if (i.notes != null) ErpFact('prc.notes'.tr, i.notes!),
          ],
        ),
      ),
      if (i.approvals.isNotEmpty) ...[
        erpGap,
        VouchFlowPanel(title: 'prc.approvals'.tr, padded: false, child: ApprovalTrail(approvals: i.approvals)),
      ],
    ];
  }
}
