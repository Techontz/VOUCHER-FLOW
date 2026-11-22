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

/// One purchase requisition: why, what, the approvals so far and the
/// orders raised from it, with Approve and Reject for an approver who did
/// not raise it, and Submit for a draft (the web's
/// /erp/procurement/requisitions/[id]). Opened with the id.
class RequisitionPage extends StatelessWidget {
  const RequisitionPage({super.key, this.requisitionId});

  final int? requisitionId;

  @override
  Widget build(BuildContext context) {
    final repo = ProcurementRepository.to;
    final id = requisitionId ?? finArgId();
    return FinDetail<PurchaseRequisition>(
      load: () => repo.requisition(id),
      title: (r) => r?.number ?? 'prc.requisition'.tr,
      children: (context, r, reload) => _body(context, r),
      actions: (context, r, reload) => _actions(context, r, reload),
    );
  }

  List<Widget> _actions(BuildContext context, PurchaseRequisition r, Future<void> Function() reload) {
    final erp = ErpService.to;
    final repo = ProcurementRepository.to;
    final summary = [
      VfSummaryRow('prc.requestedBy'.tr, r.requester?.name ?? '-'),
      VfSummaryRow('fin.total'.tr, finMoney(r.total)),
    ];
    Future<void> decide(Future<String?> pending) async {
      final message = await pending;
      if (message == null) return;
      showToast(message.isEmpty ? 'fin.done'.tr : message);
      await reload();
    }

    final mine = r.requestedBy != null && r.requestedBy == finMe();
    return [
      if (r.status == 'submitted' && erp.can('procurement.approve') && !mine) ...[
        VouchFlowButton(
          label: 'prc.reject'.tr,
          variant: VfButtonVariant.secondary,
          onPressed: () => decide(
            finConfirm(
              context,
              title: 'prc.rejectQ'.trParams({'number': r.number}),
              subtitle: 'prc.rejectSub'.tr,
              icon: PhosphorIconsRegular.xCircle,
              tone: VfTone.warn,
              summary: summary,
              comment: FinComment.required,
              danger: true,
              confirmLabel: 'prc.reject'.tr,
              run: (c) => repo.rejectRequisition(r.id, c),
            ),
          ),
        ),
        VouchFlowButton(
          label: 'prc.approve'.tr,
          icon: PhosphorIconsRegular.sealCheck,
          onPressed: () => decide(
            finConfirm(
              context,
              title: 'prc.approveQ'.trParams({'number': r.number}),
              subtitle: r.approvalsRequired > 1 ? 'prc.approveTwoSub'.tr : 'prc.approveSub'.tr,
              icon: PhosphorIconsRegular.sealCheck,
              summary: summary,
              comment: FinComment.optional,
              confirmLabel: 'prc.approve'.tr,
              run: (c) => repo.approveRequisition(r.id, c),
            ),
          ),
        ),
      ],
      if (r.status == 'draft' && erp.can('procurement.request'))
        VouchFlowButton(
          label: 'prc.submit'.tr,
          icon: PhosphorIconsRegular.paperPlaneTilt,
          onPressed: () => decide(
            finConfirm(
              context,
              title: 'prc.submitQ'.trParams({'number': r.number}),
              subtitle: 'prc.submitSub'.tr,
              icon: PhosphorIconsRegular.paperPlaneTilt,
              summary: summary,
              confirmLabel: 'prc.submit'.tr,
              run: (_) => repo.submitRequisition(r.id),
            ),
          ),
        ),
    ];
  }

  List<Widget> _body(BuildContext context, PurchaseRequisition r) {
    final t = context.vf;
    final waiting = r.status == 'submitted';
    final approved = r.approvals.where((a) => a.decision == 'approved').length;
    return [
      FinHead(
        icon: PhosphorIconsRegular.clipboardText,
        tint: t.infoStrong,
        kicker: 'prc.requisition'.tr,
        title: r.number,
        subtitle: [?r.requester?.name, if (r.neededBy != null) 'prc.neededBy'.trParams({'date': dashDate(r.neededBy)})].join(' · '),
        amount: finMoney(r.total),
        badges: [FinStatusBadge(r.status, large: true)],
      ),
      if (waiting) ...[
        VouchFlowAlert(
          tone: VfTone.warn,
          icon: PhosphorIconsRegular.hourglassMedium,
          title: 'prc.awaitingTitle'.tr,
          message: 'prc.approvalsOf'.trParams({'n': '$approved', 'of': '${r.approvalsRequired}'}),
        ),
        erpGap,
      ],
      VouchFlowPanel(
        title: 'prc.justification'.tr,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(r.justification, style: VfType.body.copyWith(color: t.text)),
        ),
      ),
      erpGap,
      VouchFlowPanel(
        title: 'prc.lines'.tr,
        trailing: Text('${r.lines.length}', style: VfType.small.copyWith(color: t.muted, fontWeight: FontWeight.w600)),
        padded: false,
        child: Column(
          children: [
            for (var i = 0; i < r.lines.length; i++) ProcLineRow(line: r.lines[i], divider: i > 0),
            FinAmountRow(label: 'prc.estimatedTotal'.tr, amount: finMoney(r.total), weight: FinRowWeight.total),
          ],
        ),
      ),
      erpGap,
      VouchFlowPanel(
        title: 'inv.details'.tr,
        child: Column(
          children: [
            ErpFact('prc.requestedBy'.tr, [r.requester?.name ?? '-', if (r.createdAt != null) dashDateTime(r.createdAt)].join(' · ')),
            if (r.department != null) ErpFact('prc.department'.tr, r.department!.name),
            if (r.submittedAt != null) ErpFact('prc.submitted'.tr, dashDateTime(r.submittedAt)),
            ErpFact('prc.approvalsNeeded'.tr, '${r.approvalsRequired}'),
            for (final o in r.orders)
              ErpFact('prc.order'.tr, o.name, onTap: () => Get.toNamed(Routes.prcOrder, arguments: o.id, preventDuplicates: false)),
          ],
        ),
      ),
      erpGap,
      VouchFlowPanel(title: 'prc.approvals'.tr, padded: false, child: ApprovalTrail(approvals: r.approvals)),
    ];
  }
}
