import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/dashboard_models.dart';
import '../../data/models/models.dart';
import '../../widgets/vf/vf.dart';
import '../vouchers/voucher_card.dart' show voucherShortStatus;
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

/// A voucher in the home queue, as an app list row: a tile for the next
/// step, the purpose, its number and payee, the amount and status — and a
/// slim bar for where it is in its route. Tapping opens the voucher.
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
    final b = Theme.of(context).brightness;
    final tint = cta != null && cta.strong
        ? t.primary
        : VfStatus.foreground(v.displayTag, b);
    final meta = [
      v.number,
      if (v.payee.isNotEmpty && v.payee != 'null') v.payee,
    ].join(' · ');

    return Semantics(
      button: true,
      hint: cta?.label,
      child: DashRow(
        onTap: onOpen,
        last: last,
        inset: 68,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DashIconTile(
              icon:
                  cta?.icon ??
                  (v.isCash
                      ? PhosphorIconsRegular.money
                      : PhosphorIconsRegular.bank),
              color: tint,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          v.purpose,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: VfType.bodyStrong.copyWith(
                            color: t.text,
                            fontSize: 14.5,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Scales down rather than squeezing the purpose out.
                      Flexible(
                        flex: 2,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            v.amountText,
                            style: VfType.small.copyWith(
                              color: t.text,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: VfType.meta.copyWith(
                            color: t.muted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: VouchFlowStatusBadge(
                          label: voucherShortStatus(v),
                          tag: v.displayTag,
                        ),
                      ),
                    ],
                  ),
                  if (v.isPartiallyPaid && v.balanceText != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      v.balanceText!,
                      style: VfType.meta.copyWith(
                        color: t.warningStrong,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (progress.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    QueueProgress(progress),
                  ],
                  // The next step, spelled out: "Review & sign", "Review &
                  // approve", "Record payment" — it opens the voucher.
                  if (cta != null) ...[
                    const SizedBox(height: 12),
                    _QueueCta(
                      label: cta.label,
                      icon: cta.icon,
                      strong: cta.strong,
                      onTap: onOpen,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueCta extends StatelessWidget {
  const _QueueCta({
    required this.label,
    required this.icon,
    required this.strong,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool strong;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final fg = strong ? Colors.white : t.primaryText;
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: strong ? t.primary : t.primarySoft,
        borderRadius: BorderRadius.circular(VfSize.radiusPill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VfType.label.copyWith(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(PhosphorIconsBold.caretRight, size: 12, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Where a voucher is in its route (Prepared — HOD — CEO — Cashier) as a
/// slim segmented bar: done, current, pending or rejected.
class QueueProgress extends StatelessWidget {
  const QueueProgress(this.steps, {super.key});
  final List<QueueProgressStep> steps;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final current = steps
        .where((s) => s.state == QueueStepState.current)
        .firstOrNull;
    return Semantics(
      label: steps.map((s) => '${s.label}: ${s.state.name}').join(', '),
      child: ExcludeSemantics(
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  for (var i = 0; i < steps.length; i++) ...[
                    if (i > 0) const SizedBox(width: 3),
                    Expanded(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: switch (steps[i].state) {
                            QueueStepState.done => t.successStrong,
                            QueueStepState.current => t.primary,
                            QueueStepState.rejected => t.dangerStrong,
                            QueueStepState.pending => t.surface3,
                          },
                          borderRadius: BorderRadius.circular(
                            VfSize.radiusPill,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (current != null) ...[
              const SizedBox(width: 8),
              Text(
                current.label,
                style: VfType.meta.copyWith(
                  color: t.primaryText,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
