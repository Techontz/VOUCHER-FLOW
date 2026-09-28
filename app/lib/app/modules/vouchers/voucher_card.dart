import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/models/vouchers_models.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart' show Fmt;
import '../../widgets/vf/vf.dart';

/// The web's `KindChip`: a bank or cash mark beside the voucher number.
class VoucherKindTag extends StatelessWidget {
  const VoucherKindTag({super.key, required this.isCash});

  final bool isCash;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: t.surface3,
        borderRadius: BorderRadius.circular(VfSize.radiusS),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isCash ? PhosphorIconsRegular.money : PhosphorIconsRegular.bank,
            size: 14,
            color: t.text2,
          ),
          const SizedBox(width: 5),
          Text(
            isCash ? 'vouchers.cash'.tr : 'vouchers.bank'.tr,
            style: VfType.meta.copyWith(
              color: t.text2,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// What this person can do with the voucher, as one call to action (the
/// web's `primaryAction`). Every path leads to the voucher, never straight
/// to a decision.
({String label, IconData icon, bool strong})? voucherPrimaryAction(Voucher v) {
  final a = v.actions;
  if (a.pay) {
    return (
      label: 'vouchers.recordPayment',
      icon: PhosphorIconsRegular.wallet,
      strong: true,
    );
  }
  if (a.approve) {
    return (
      label: 'vouchers.reviewApprove',
      icon: PhosphorIconsRegular.sealCheck,
      strong: true,
    );
  }
  if (a.sign) {
    return (
      label: 'vouchers.reviewSign',
      icon: PhosphorIconsRegular.signature,
      strong: true,
    );
  }
  if (a.submitSigned) {
    return (
      label: 'vouchers.submitSigned',
      icon: PhosphorIconsRegular.paperPlaneTilt,
      strong: true,
    );
  }
  if (a.edit && v.status == 'changes_requested') {
    return (
      label: 'vouchers.reviseVoucher',
      icon: PhosphorIconsRegular.pencilSimple,
      strong: true,
    );
  }
  if (a.edit) {
    return (
      label: 'vouchers.continueDraft',
      icon: PhosphorIconsRegular.pencilSimple,
      strong: false,
    );
  }
  return null;
}

const _roleKeys = {'hod', 'ceo', 'manager', 'director', 'finance', 'cashier'};

/// Where the voucher is now, or how it ended, in one plain phrase — the web's
/// `voucherStage`: "With HOD for signature", "Paid 14 Sep 2026" …
String voucherStage(
  Voucher v, {
  String? stepRole,
  String? decidedBy,
  DateTime? paymentDate,
}) {
  final step = v.currentStepName;
  final role = stepRole != null && _roleKeys.contains(stepRole)
      ? 'vouchers.role.$stepRole'.tr
      : (step ?? '');
  switch (v.statusKey) {
    case 'draft':
      return 'vouchers.draftNotSubmitted'.tr;
    case 'awaiting_signature':
      return step != null
          ? 'vouchers.stageWithSign'.trParams({'role': role})
          : v.statusLabel;
    case 'signed_pending_submit':
      return 'vouchers.signedNotSubmitted'.tr;
    case 'awaiting_approval':
      return step != null
          ? 'vouchers.stageWithApproval'.trParams({'role': role})
          : v.statusLabel;
    case 'awaiting_review':
      return step != null
          ? 'vouchers.stageWith'.trParams({'step': step})
          : v.statusLabel;
    case 'awaiting_payment':
      return 'vouchers.awaitingPayment'.tr;
    case 'partially_paid':
      return v.balanceText != null
          ? 'vouchers.stagePartlyPaid'.trParams({'amount': v.balanceText!})
          : v.statusLabel;
    case 'paid':
      final on = paymentDate ?? v.paidAt;
      return on != null
          ? 'vouchers.stagePaidOn'.trParams({'date': Fmt.date(on)})
          : 'vouchers.paid'.tr;
    case 'rejected':
      return decidedBy != null
          ? 'vouchers.stageRejectedBy'.trParams({'name': decidedBy})
          : 'vouchers.rejected'.tr;
    case 'changes_requested':
      return decidedBy != null
          ? 'vouchers.stageReturnedBy'.trParams({'name': decidedBy})
          : 'vouchers.stageReturned'.tr;
    case 'cancelled':
      return 'vouchers.stageCancelled'.tr;
    default:
      return v.statusLabel;
  }
}

/// One voucher as the web's `VoucherRow`: number, bank/cash mark and status;
/// the purpose as the title; payee · requester · department · date; with
/// [history], where it stands and when it was submitted and last updated;
/// the amount (and the balance when part-paid); and the call to action.
class VoucherRow extends StatelessWidget {
  const VoucherRow({
    super.key,
    required this.voucher,
    this.row,
    this.history = false,
    this.showCta = true,
    this.onReturn,
  });

  final Voucher voucher;

  /// The register's extra fields, when the row came from the register.
  final RegisterRow? row;
  final bool history;
  final bool showCta;
  final VoidCallback? onReturn;

  Future<void> _open() async {
    await Get.toNamed(Routes.voucher, arguments: voucher.id);
    onReturn?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final v = voucher;
    final cta = showCta ? voucherPrimaryAction(v) : null;
    final meta = [
      v.payee,
      v.requesterName,
      v.departmentName,
      if (v.voucherDate != null) Fmt.date(v.voucherDate),
    ].whereType<String>().where((s) => s.isNotEmpty && s != 'null').join(' · ');
    const tabular = [FontFeature.tabularFigures()];

    return InkWell(
      onTap: _open,
      child: Padding(
        padding: const EdgeInsets.all(VfSize.cardPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  v.number,
                  style: VfType.small.copyWith(
                    color: t.text2,
                    fontWeight: FontWeight.w600,
                    fontFeatures: tabular,
                  ),
                ),
                VoucherKindTag(isCash: v.isCash),
                VouchFlowStatusBadge(label: v.statusLabel, tag: v.displayTag),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              v.purpose,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: VfType.cardTitle.copyWith(color: t.text),
            ),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: VfType.small.copyWith(color: t.muted),
              ),
            ],
            if (history) ...[
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: voucherStage(
                        v,
                        stepRole: row?.stepRole,
                        decidedBy: row?.decidedBy,
                        paymentDate: row?.paymentDate,
                      ),
                      style: TextStyle(
                        color: t.text2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (v.submittedAt != null)
                      TextSpan(
                        text:
                            ' · ${'vouchers.submittedOn'.tr} ${Fmt.date(v.submittedAt)}',
                      ),
                    if (row?.updatedAt != null)
                      TextSpan(
                        text:
                            ' · ${'vouchers.lastUpdated'.tr} ${Fmt.date(row!.updatedAt)}',
                      ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: VfType.small.copyWith(color: t.muted),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              v.amountText,
              style: VfType.bodyStrong.copyWith(
                fontSize: 17,
                color: t.text,
                fontFeatures: tabular,
              ),
            ),
            if (v.isPartiallyPaid && v.balanceText != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'vouchers.balanceAmount'.trParams({'amount': v.balanceText!}),
                  style: VfType.meta.copyWith(
                    color: t.warningStrong,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            if (cta != null) ...[
              const SizedBox(height: 12),
              VouchFlowButton(
                label: cta.label.tr,
                icon: cta.icon,
                compact: true,
                variant: cta.strong
                    ? VfButtonVariant.primary
                    : VfButtonVariant.secondary,
                onPressed: _open,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One voucher in its own card (dashboard lists): a [VoucherRow] in a panel.
class VoucherCard extends StatelessWidget {
  const VoucherCard({
    super.key,
    required this.voucher,
    this.onReturn,
    this.showCta = true,
  });

  final Voucher voucher;
  final VoidCallback? onReturn;
  final bool showCta;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: VouchFlowCard(
      padding: EdgeInsets.zero,
      child: VoucherRow(voucher: voucher, onReturn: onReturn, showCta: showCta),
    ),
  );
}
