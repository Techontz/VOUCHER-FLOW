import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart';
import '../../data/models/finance_models.dart';
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate, dashDateTime;
import '../finance/fin_widgets.dart';

/*
 * Pieces the Procurement screens share: each kind of record as one list
 * row, and the approval trail a requisition, an order or an invoice
 * carries.
 */

/// A requisition: its number and purpose, who asked, when it is needed.
class RequisitionRow extends StatelessWidget {
  const RequisitionRow({super.key, required this.requisition, required this.onTap, this.divider = true});

  final PurchaseRequisition requisition;
  final VoidCallback onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final r = requisition;
    return VouchFlowListRow(
      divider: divider,
      icon: PhosphorIconsRegular.clipboardText,
      iconColor: context.vf.infoStrong,
      title: r.justification.isEmpty ? r.number : r.justification,
      subtitle: [
        r.number,
        ?r.requester?.name,
        if (r.neededBy != null) 'prc.neededBy'.trParams({'date': dashDate(r.neededBy)}),
      ].join(' · '),
      trailing: FinTrailing(amount: finCompact(r.total), badge: FinStatusBadge(r.status)),
      onTap: onTap,
    );
  }
}

/// An order: number, supplier, date, total and state.
class OrderRow extends StatelessWidget {
  const OrderRow({super.key, required this.order, required this.onTap, this.divider = true});

  final PurchaseOrder order;
  final VoidCallback onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final o = order;
    return VouchFlowListRow(
      divider: divider,
      icon: PhosphorIconsRegular.shoppingCart,
      iconColor: context.vf.primary,
      title: o.supplier?.name ?? o.number,
      subtitle: [o.number, if (o.orderDate != null) dashDate(o.orderDate)].join(' · '),
      trailing: FinTrailing(amount: finCompact(o.total), badge: FinStatusBadge(o.status)),
      onTap: onTap,
    );
  }
}

/// A supplier invoice: the supplier's own number, ours, when it is due,
/// the total and whether it is matched, posted or paid.
class InvoiceRow extends StatelessWidget {
  const InvoiceRow({super.key, required this.invoice, required this.onTap, this.divider = true});

  final SupplierInvoice invoice;
  final VoidCallback onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final i = invoice;
    final t = context.vf;
    final state = i.isPosted ? (i.isOverdue ? 'overdue' : (i.paymentStatus ?? 'posted')) : i.status;
    return VouchFlowListRow(
      divider: divider,
      icon: PhosphorIconsRegular.receipt,
      iconColor: i.isOverdue ? t.dangerStrong : t.warningStrong,
      title: i.supplier?.name ?? i.number,
      subtitle: [
        i.supplierInvoiceNumber ?? i.number,
        if (i.dueDate != null) 'prc.dueOn'.trParams({'date': dashDate(i.dueDate)}),
      ].join(' · '),
      trailing: FinTrailing(
        amount: finCompact(i.isPosted && i.outstanding > 0 ? i.outstanding : i.total),
        badge: FinStatusBadge(state),
      ),
      onTap: onTap,
    );
  }
}

/// A supplier payment: number, supplier, date, method, amount.
class PaymentRow extends StatelessWidget {
  const PaymentRow({super.key, required this.payment, required this.onTap, this.divider = true});

  final SupplierPayment payment;
  final VoidCallback onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final p = payment;
    return VouchFlowListRow(
      divider: divider,
      icon: PhosphorIconsRegular.handCoins,
      iconColor: context.vf.successStrong,
      title: p.supplier?.name ?? p.number,
      subtitle: [
        p.number,
        if (p.paymentDate != null) dashDate(p.paymentDate),
        if (p.method != null) 'fin.method.${p.method}'.tr,
      ].join(' · '),
      trailing: FinTrailing(amount: finCompact(p.amount), badge: FinStatusBadge(p.status)),
      onTap: onTap,
    );
  }
}

/// Who decided what, level by level (the web's ApprovalTrail).
class ApprovalTrail extends StatelessWidget {
  const ApprovalTrail({super.key, required this.approvals, this.required});

  final List<ProcApproval> approvals;

  /// How many approvals the document needs; shown when some are missing.
  final int? required;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    if (approvals.isEmpty) return FinPanelEmpty('prc.noApprovals'.tr);
    return Column(
      children: [
        for (var i = 0; i < approvals.length; i++)
          VouchFlowListRow(
            divider: i > 0,
            icon: approvals[i].decision == 'approved' ? PhosphorIconsRegular.sealCheck : PhosphorIconsRegular.xCircle,
            iconColor: approvals[i].decision == 'approved' ? t.successStrong : t.dangerStrong,
            title: [
              approvals[i].user?.name ?? '-',
              'prc.levelN'.trParams({'n': '${approvals[i].level}'}),
            ].join(' · '),
            titleMaxLines: 2,
            subtitle: [
              if (approvals[i].comment != null) '"${approvals[i].comment}"',
              if (approvals[i].at != null) dashDateTime(approvals[i].at),
            ].join(' · '),
            trailing: FinStatusBadge(approvals[i].decision),
          ),
      ],
    );
  }
}

/// A line of a requisition, an order or an invoice: what, how many at what
/// price, the amount, and for an order how much has arrived.
class ProcLineRow extends StatelessWidget {
  const ProcLineRow({super.key, required this.line, this.divider = true, this.showReceived = false, this.showMatch = false});

  final ProcLine line;
  final bool divider, showReceived, showMatch;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final l = line;
    final unit = l.unitCode == null ? '' : ' ${l.unitCode}';
    final sub = [
      '${_qty(l.quantity)}$unit @ ${_amount(l.unitPrice)}',
      if (showReceived && l.receivedQuantity != null) 'prc.receivedQty'.trParams({'n': _qty(l.receivedQuantity!)}),
      if (showMatch && l.orderUnitPrice != null && l.orderUnitPrice != l.unitPrice)
        'prc.orderPriceWas'.trParams({'price': _amount(l.orderUnitPrice!)}),
      if (l.expenseAccount != null) accountLabel(l.expenseAccount),
    ].join(' · ');
    return VouchFlowListRow(
      divider: divider,
      icon: l.lineType == 'service' ? PhosphorIconsRegular.wrench : PhosphorIconsRegular.package,
      iconColor: l.flagged ? t.dangerStrong : t.muted,
      title: l.description,
      titleMaxLines: 2,
      subtitle: sub,
      trailing: FinTrailing(
        amount: finMoney(l.amount, cents: true),
        badge: showMatch
            ? FinStatusBadge(l.flagged ? 'variance' : 'matched')
            : null,
      ),
    );
  }
}

String _qty(double v) => ErpFmt.qty(v);

String _amount(double v) => ErpFmt.amount(v);
