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

/// The status in a word or two, for a list row's pill ("Pending", "Paid").
/// The voucher page shows the full label.
String voucherShortStatus(Voucher v) {
  final key = 'vouchers.short.${v.statusKey}';
  final out = key.tr;
  return out == key ? v.statusLabel : out;
}

/// The kind tile: a rounded square tinted by bank (primary) or cash (green).
class VoucherKindTile extends StatelessWidget {
  const VoucherKindTile({super.key, required this.isCash, this.size = 44});

  final bool isCash;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isCash ? t.successSoft : t.primarySoft,
        borderRadius: BorderRadius.circular(size * .32),
      ),
      child: Icon(
        isCash ? PhosphorIconsFill.money : PhosphorIconsFill.bank,
        size: size * .48,
        color: isCash ? t.successStrong : t.primaryText,
        semanticLabel: isCash ? 'vouchers.cash'.tr : 'vouchers.bank'.tr,
      ),
    );
  }
}

/// One voucher as an app list row: the kind tile, the purpose, "number ·
/// payee", and on the right the amount over a status pill.
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
      v.number,
      v.payee,
    ].where((s) => s.isNotEmpty && s != 'null').join(' · ');
    const tabular = [FontFeature.tabularFigures()];
    final partial = v.isPartiallyPaid && v.balanceText != null;

    return InkWell(
      onTap: _open,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                VoucherKindTile(isCash: v.isCash),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        v.purpose,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: VfType.bodyStrong.copyWith(
                          color: t.text,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        partial
                            ? 'vouchers.balanceAmount'.trParams({
                                'amount': v.balanceText!,
                              })
                            : meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: VfType.meta.copyWith(
                          fontSize: 13,
                          color: partial ? t.warningStrong : t.muted,
                          fontWeight: partial ? FontWeight.w500 : null,
                          fontFeatures: tabular,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 136),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          v.amountText,
                          maxLines: 1,
                          style: VfType.bodyStrong.copyWith(
                            color: t.text,
                            height: 1.3,
                            fontFeatures: tabular,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      VouchFlowStatusBadge(
                        label: voucherShortStatus(v),
                        tag: v.displayTag,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (cta != null) ...[
              const SizedBox(height: 12),
              VouchFlowButton(
                label: cta.label.tr,
                icon: cta.icon,
                compact: true,
                expand: true,
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

/// One voucher in its own rounded card (dashboard lists).
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
      radius: VfSize.radiusXl,
      child: VoucherRow(voucher: voucher, onReturn: onReturn, showCta: showCta),
    ),
  );
}
