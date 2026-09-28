import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/dashboard_models.dart';
import '../../data/models/models.dart';
import '../../widgets/vf/vf.dart';
import 'dash_bits.dart';

/// The one next step on a voucher, as a list shows it — never a one-tap
/// approve: every CTA opens the voucher (the web's `primaryAction`).
({String label, IconData icon, bool strong})? queueAction(Voucher v) {
  final a = v.actions;
  if (a.pay) {
    return (
      label: 'dashboard.cta.recordPayment'.tr,
      icon: PhosphorIconsRegular.wallet,
      strong: true,
    );
  }
  if (a.approve) {
    return (
      label: 'dashboard.cta.reviewApprove'.tr,
      icon: PhosphorIconsRegular.sealCheck,
      strong: true,
    );
  }
  if (a.sign) {
    return (
      label: 'dashboard.cta.reviewSign'.tr,
      icon: PhosphorIconsRegular.signature,
      strong: true,
    );
  }
  if (a.submitSigned) {
    return (
      label: 'dashboard.cta.submitSigned'.tr,
      icon: PhosphorIconsRegular.paperPlaneTilt,
      strong: true,
    );
  }
  if (a.edit && v.status == 'changes_requested') {
    return (
      label: 'dashboard.cta.reviseVoucher'.tr,
      icon: PhosphorIconsRegular.pencilSimple,
      strong: true,
    );
  }
  if (a.edit) {
    return (
      label: 'dashboard.cta.continueDraft'.tr,
      icon: PhosphorIconsRegular.pencilSimple,
      strong: false,
    );
  }
  return null;
}

/// A voucher in the dashboard queue: the web's `VoucherRow` — number, kind
/// and status; the purpose; who, where and when; its route; the amount and
/// the one next step.
class QueueRow extends StatelessWidget {
  const QueueRow({
    super.key,
    required this.voucher,
    required this.progress,
    required this.onOpen,
    this.last = false,
  });

  final Voucher voucher;
  final List<QueueProgressStep> progress;
  final VoidCallback onOpen;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final v = voucher;
    final cta = queueAction(v);
    final meta = [
      v.payee,
      ?v.requesterName,
      ?v.departmentName,
      if (v.voucherDate != null) dashDate(v.voucherDate),
    ].where((s) => s.isNotEmpty && s != 'null').join(' · ');

    return DashRow(
      onTap: onOpen,
      last: last,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
                  color: t.text,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              _KindChip(isCash: v.isCash),
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: VfType.small.copyWith(color: t.muted),
            ),
          ],
          if (progress.isNotEmpty) ...[
            const SizedBox(height: 10),
            QueueProgress(progress),
          ],
          const SizedBox(height: 12),
          // Amount left, the next step right; the button drops below the
          // amount rather than truncating when both do not fit.
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.amountText,
                      style: VfType.bodyStrong.copyWith(
                        fontSize: 17,
                        color: t.text,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (v.isPartiallyPaid && v.balanceText != null)
                      Text(
                        v.balanceText!,
                        style: VfType.meta.copyWith(
                          color: t.warningStrong,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
                if (cta != null)
                  VouchFlowButton(
                    label: cta.label,
                    icon: cta.icon,
                    compact: true,
                    variant: cta.strong
                        ? VfButtonVariant.primary
                        : VfButtonVariant.secondary,
                    onPressed: onOpen,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The web's `.vf-kind`: bank or cash, with its mark.
class _KindChip extends StatelessWidget {
  const _KindChip({required this.isCash});
  final bool isCash;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
          const SizedBox(width: 4),
          Text(
            isCash ? 'dashboard.cash'.tr : 'dashboard.bank'.tr,
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

/// The web's `ProgressSteps`: Prepared — HOD — CEO — Cashier, each marked
/// done, current, pending or rejected.
class QueueProgress extends StatelessWidget {
  const QueueProgress(this.steps, {super.key});
  final List<QueueProgressStep> steps;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < steps.length; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (i > 0) ...[
                Container(width: 12, height: 1, color: t.borderStrong),
                const SizedBox(width: 6),
              ],
              _Mark(steps[i].state),
              const SizedBox(width: 6),
              Text(
                steps[i].label,
                style: VfType.meta.copyWith(
                  fontSize: 13,
                  color: switch (steps[i].state) {
                    QueueStepState.done => t.text2,
                    QueueStepState.current => t.text,
                    _ => t.muted,
                  },
                  fontWeight: steps[i].state == QueueStepState.current
                      ? FontWeight.w500
                      : FontWeight.w400,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark(this.state);
  final QueueStepState state;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final (Color fill, Color edge) = switch (state) {
      QueueStepState.done => (t.successStrong, t.successStrong),
      QueueStepState.rejected => (t.dangerStrong, t.dangerStrong),
      QueueStepState.current => (t.surface, t.primary),
      QueueStepState.pending => (t.surface, t.borderStrong),
    };
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: edge, width: 1.5),
      ),
      alignment: Alignment.center,
      child: switch (state) {
        QueueStepState.done => const Icon(
          PhosphorIconsBold.check,
          size: 9,
          color: Colors.white,
        ),
        QueueStepState.rejected => const Icon(
          PhosphorIconsBold.x,
          size: 9,
          color: Colors.white,
        ),
        QueueStepState.current => Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: t.primary, shape: BoxShape.circle),
        ),
        QueueStepState.pending => null,
      },
    );
  }
}
