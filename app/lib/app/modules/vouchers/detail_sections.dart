import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/vf/vf.dart';
import 'detail_bits.dart';
import 'detail_controller.dart';
import 'detail_dialogs.dart';

const _tabular = [FontFeature.tabularFigures()];

String? _join(List<String?> parts) {
  final out = parts
      .whereType<String>()
      .where((s) => s.trim().isNotEmpty)
      .join(' · ');
  return out.isEmpty ? null : out;
}

/* ─────────────────────────────────────────────────────── the request ── */

class RequestDetailsPanel extends StatelessWidget {
  const RequestDetailsPanel({super.key, required this.voucher});

  final Voucher voucher;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final v = voucher;
    final hasBank =
        !v.isCash &&
        ((v.payeeBank ?? '').isNotEmpty ||
            (v.payeeAccountNumber ?? '').isNotEmpty);
    return DetailPanel(
      title: dt('requestDetails'),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DlRow(label: dt('payee'), value: v.payee),
          DlRow(label: dt('description'), value: v.description),
          DlRow(
            label: dt('requestedBy'),
            value: _join([v.requesterName, v.requesterJobTitle]),
          ),
          DlRow(
            label: dt('department'),
            value: _join([v.departmentName, v.costCentre]),
          ),
          DlRow(label: dt('voucherType'), value: v.voucherTypeLabel),
          DlRow(label: dt('category'), value: v.category),
          DlRow(
            label: dt('requestedOn'),
            value: v.voucherDate == null ? null : Fmt.date(v.voucherDate),
          ),
          DlRow(label: dt('notes'), value: v.notesToApprover),
          Divider(height: 17, color: t.border),
          DlRow(
            label: dt('voucherFormat'),
            value: v.isCash ? dt('cash') : dt('bank'),
          ),
          DlRow(label: dt('paymentMethod'), value: v.paymentMethod),
          DlRow(label: dt('accountRef'), value: v.accountRef, mono: true),
          if (hasBank) ...[
            DlRow(
              label: dt('bank'),
              value: _join([v.payeeBank, v.payeeBankBranch]),
            ),
            DlRow(label: dt('accountName'), value: v.payeeAccountName),
            DlRow(
              label: dt('accountNumber'),
              value: v.payeeAccountNumber,
              mono: true,
            ),
          ],
          if (v.isCash) DlRow(label: dt('payFrom'), value: v.cashFloat),
          if (v.status == 'paid') ...[
            DlRow(
              label: dt('paidByOn'),
              value: _join([
                v.paidBy,
                v.paidAt == null ? null : Fmt.dateTime(v.paidAt),
              ]),
            ),
            DlRow(
              label: dt('paymentRef'),
              value: v.paymentReference,
              mono: true,
            ),
            DlRow(label: dt('receivedBy'), value: v.receivedBy),
          ],
        ],
      ),
    );
  }
}

/* ────────────────────────────────────────────────────────── payments ── */

/// What was approved, what has left, what is still owed — and one row per
/// release, each with its receiver's signed acknowledgement.
class PaymentsPanel extends StatelessWidget {
  const PaymentsPanel({
    super.key,
    required this.controller,
    required this.voucher,
  });

  final VoucherDetailController controller;
  final Voucher voucher;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final v = voucher;
    final paid = v.amountPaid > 0
        ? v.amountPaid
        : (v.status == 'paid' ? v.amount : 0.0);
    final balance = v.balance ?? (v.status == 'paid' ? 0.0 : v.amount);

    Widget figure(String label, String value, {bool owing = false}) =>
        Container(
          color: owing ? t.warningSoft : null,
          padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
          decoration: null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: VfType.eyebrow.copyWith(
                    fontSize: 11.5,
                    letterSpacing: .5,
                    color: t.muted,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                value,
                textAlign: TextAlign.right,
                style: VfType.bodyStrong.copyWith(
                  color: owing ? t.warning : t.text,
                  fontFeatures: _tabular,
                ),
              ),
            ],
          ),
        );

    return DetailPanel(
      title: dt('payments'),
      count: v.payments.length,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          figure(dt('approvedAmount'), v.amountText),
          Divider(height: 1, color: t.border),
          figure(
            dt('paidSoFar'),
            v.amountPaidText ?? Fmt.money(paid, v.currency),
          ),
          Divider(height: 1, color: t.border),
          figure(
            dt('balanceLabel'),
            v.balanceText ?? Fmt.money(balance, v.currency),
            owing: balance > 0,
          ),
          Divider(height: 1, color: t.border),
          if (v.payments.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: MutedLine(
                icon: PhosphorIconsRegular.wallet,
                text: dt('noPaymentsYet'),
              ),
            )
          else
            for (var i = 0; i < v.payments.length; i++) ...[
              if (i > 0) Divider(height: 1, color: t.border),
              _PaymentRow(
                controller: controller,
                voucher: v,
                payment: v.payments[i],
              ),
            ],
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.controller,
    required this.voucher,
    required this.payment,
  });

  final VoucherDetailController controller;
  final Voucher voucher;
  final VoucherPayment payment;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final p = payment;
    final via = _join([p.paymentMethod, p.paymentReference ?? p.chequeNumber]);
    final receiver = _join([
      p.receivedBy,
      p.receiverIdNumber == null ? null : 'ID ${p.receiverIdNumber}',
    ]);
    final signedCopy = p.acknowledgementAttachmentIds.isEmpty
        ? null
        : p.acknowledgementAttachmentIds.last;
    final signedFile = signedCopy == null
        ? null
        : voucher.attachments.firstWhereOrNull((a) => a.id == signedCopy);

    Widget fact(String label, String value, {bool mono = false}) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: VfType.meta.copyWith(fontSize: 12.5, color: t.muted),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: VfType.small.copyWith(
                color: t.text,
                fontFeatures: mono ? _tabular : null,
              ),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                decoration: BoxDecoration(
                  color: t.primarySoft,
                  borderRadius: BorderRadius.circular(VfSize.radiusPill),
                ),
                child: Text(
                  '#${p.sequence}',
                  style: VfType.meta.copyWith(
                    fontWeight: FontWeight.w600,
                    color: t.primaryText,
                  ),
                ),
              ),
              Text(
                p.amountText,
                style: VfType.bodyStrong.copyWith(
                  color: t.text,
                  fontFeatures: _tabular,
                ),
              ),
              Text(
                Fmt.date(p.paymentDate ?? p.paidAt),
                style: VfType.meta.copyWith(color: t.muted),
              ),
              Text(
                p.reference,
                style: VfType.meta.copyWith(
                  color: t.muted,
                  fontFeatures: _tabular,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (via != null) fact(dt('method'), via),
          if (receiver != null) fact(dt('receivedBy'), receiver),
          if (p.paidBy != null)
            fact(
              dt('paidBy'),
              _join([
                p.paidBy,
                p.paidAt == null ? null : Fmt.dateTime(p.paidAt),
              ])!,
            ),
          fact(dt('balanceAfter'), p.balanceAfterText, mono: true),
          if ((p.note ?? '').trim().isNotEmpty) fact(dt('notes'), p.note!),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: _AckState(
              filed: p.isAcknowledged,
              onOpen: signedFile == null
                  ? null
                  : () => openAttachment(controller, signedFile),
              filedOn: p.acknowledgedAt,
            ),
          ),
          const SizedBox(height: 10),
          Obx(() {
            final working = controller.working.value;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                VouchFlowButton(
                  label: dt('printAcknowledgement'),
                  icon: PhosphorIconsRegular.printer,
                  variant: VfButtonVariant.secondary,
                  compact: true,
                  loading: working == 'ack-print-${p.id}',
                  onPressed: working != null
                      ? null
                      : () => controller.printAcknowledgement(p),
                ),
                if (controller.canFileAcknowledgement(p))
                  VouchFlowButton(
                    label: dt('uploadSignedCopy'),
                    icon: PhosphorIconsRegular.uploadSimple,
                    variant: VfButtonVariant.secondary,
                    compact: true,
                    loading: working == 'ack-upload-${p.id}',
                    onPressed: working != null
                        ? null
                        : () async {
                            final source = await pickDocSource(
                              context,
                              title: dt('uploadSignedCopy'),
                              hint: dt('scanHint'),
                            );
                            if (source != null) {
                              await controller.uploadAcknowledgement(p, source);
                            }
                          },
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _AckState extends StatelessWidget {
  const _AckState({required this.filed, this.onOpen, this.filedOn});

  final bool filed;
  final VoidCallback? onOpen;
  final DateTime? filedOn;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final fg = filed ? t.success : t.warning;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: filed ? t.successSoft : t.warningSoft,
        borderRadius: BorderRadius.circular(VfSize.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            filed
                ? PhosphorIconsRegular.checkCircle
                : PhosphorIconsRegular.hourglassMedium,
            size: 15,
            color: fg,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              filed
                  ? [
                      dt('signedCopyFiled'),
                      if (filedOn != null) Fmt.date(filedOn),
                    ].join(' · ')
                  : dt('awaitingSignedCopy'),
              style: VfType.meta.copyWith(
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
          if (filed && onOpen != null) ...[
            const SizedBox(width: 6),
            Icon(PhosphorIconsRegular.arrowSquareOut, size: 13, color: fg),
          ],
        ],
      ),
    );
    if (!filed || onOpen == null) return pill;
    return Tooltip(
      message: dt('openSignedCopy'),
      child: InkWell(
        borderRadius: BorderRadius.circular(VfSize.radiusPill),
        onTap: onOpen,
        child: pill,
      ),
    );
  }
}

/* ─────────────────────────────────────────────────────── attachments ── */

class AttachmentsPanel extends StatelessWidget {
  const AttachmentsPanel({
    super.key,
    required this.controller,
    required this.voucher,
  });

  final VoucherDetailController controller;
  final Voucher voucher;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final v = voucher;
    final afterDecision = v.status == 'approved' || v.status == 'paid';

    return DetailPanel(
      title: dt('attachments'),
      count: v.attachments.length,
      action: v.actions.attach
          ? Obx(
              () => VouchFlowButton(
                label: afterDecision ? dt('addReceipt') : dt('add'),
                icon: PhosphorIconsRegular.paperclip,
                variant: VfButtonVariant.secondary,
                compact: true,
                loading: controller.working.value == 'attach',
                onPressed: controller.working.value != null
                    ? null
                    : () async {
                        final source = await pickDocSource(
                          context,
                          title: afterDecision
                              ? dt('addReceipt')
                              : dt('attachments'),
                        );
                        if (source != null) await controller.attach(source);
                      },
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Receipts often arrive after the money is released, so an approved
          // or paid voucher still takes documents — its details stay locked.
          if (afterDecision && v.actions.attach) ...[
            MutedLine(
              icon: PhosphorIconsRegular.info,
              text: dt('attachAfterPaymentNote'),
            ),
            const SizedBox(height: 12),
          ],
          if (v.attachments.isEmpty)
            MutedLine(
              icon: PhosphorIconsRegular.paperclip,
              text: dt('noneAttached'),
            )
          else
            for (final file in v.attachments) ...[
              _FileRow(controller: controller, voucher: v, file: file),
              const SizedBox(height: 6),
            ],
          if (v.attachments.isNotEmpty)
            SizedBox(height: 0, child: ColoredBox(color: t.border)),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.controller,
    required this.voucher,
    required this.file,
  });

  final VoucherDetailController controller;
  final Voucher voucher;
  final Attachment file;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final ackFor = file.isAcknowledgement
        ? voucher.payments.firstWhereOrNull(
            (p) => p.id == file.voucherPaymentId,
          )
        : null;
    final meta = _join([
      file.size,
      file.uploadedBy,
      file.createdAt == null ? null : Fmt.date(file.createdAt),
    ]);
    return Material(
      color: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VfSize.radiusM),
        side: BorderSide(color: t.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openAttachment(controller, file),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: t.surface3,
                  borderRadius: BorderRadius.circular(VfSize.radiusS),
                ),
                child: Icon(
                  file.isImage
                      ? PhosphorIconsRegular.image
                      : PhosphorIconsRegular.filePdf,
                  size: 19,
                  color: t.text2,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (file.isAcknowledgement)
                      Row(
                        children: [
                          Icon(
                            PhosphorIconsRegular.sealCheck,
                            size: 12,
                            color: t.success,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              dt('signedAckLabel', {
                                'n': '${ackFor?.sequence ?? '—'}',
                              }),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: VfType.meta.copyWith(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: t.success,
                              ),
                            ),
                          ),
                        ],
                      ),
                    Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: VfType.body.copyWith(color: t.text),
                    ),
                    if (meta != null)
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: VfType.meta.copyWith(
                          fontSize: 12,
                          color: t.muted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Obx(
                () => controller.working.value == 'open-${file.id}'
                    ? SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: t.muted,
                        ),
                      )
                    : Icon(
                        PhosphorIconsRegular.arrowSquareOut,
                        size: 15,
                        color: t.faint,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ────────────────────────────────────────────────────────── comments ── */

class CommentsPanel extends StatelessWidget {
  const CommentsPanel({
    super.key,
    required this.controller,
    required this.voucher,
  });

  final VoucherDetailController controller;
  final Voucher voucher;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return DetailPanel(
      title: dt('comments'),
      count: voucher.comments.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in voucher.comments) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    c.authorInitials,
                    style: VfType.meta.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: t.primaryText,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.authorName,
                        style: VfType.bodyStrong.copyWith(color: t.text),
                      ),
                      Text(
                        _join([
                              c.authorDepartment ?? c.authorRole,
                              Fmt.dateTime(c.createdAt),
                            ]) ??
                            '',
                        style: VfType.meta.copyWith(
                          fontSize: 13,
                          color: t.muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(c.body, style: VfType.body.copyWith(color: t.text)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller.commentField,
                  style: VfType.body.copyWith(color: t.text),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => controller.postComment(),
                  decoration: InputDecoration(
                    hintText: dt('addComment'),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Obx(
                () => VouchFlowButton(
                  label: dt('post'),
                  variant: VfButtonVariant.secondary,
                  onPressed: controller.commentText.value.trim().isEmpty
                      ? null
                      : controller.postComment,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/* ─────────────────────────────────────────────────────── audit trail ── */

class AuditTrail extends StatelessWidget {
  const AuditTrail({super.key, required this.voucher});

  final Voucher voucher;

  @override
  Widget build(BuildContext context) {
    final v = voucher;
    return Disclosure(
      title: dt('auditTrail'),
      icon: PhosphorIconsRegular.scroll,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DlRow(
              label: dt('auditCreated'),
              value: Fmt.dateTime(v.createdAt),
              mono: true,
            ),
            if (v.submittedAt != null)
              DlRow(
                label: dt('auditSubmitted'),
                value: Fmt.dateTime(v.submittedAt),
                mono: true,
              ),
            if (v.approvedAt != null)
              DlRow(
                label: dt('auditApproved'),
                value: Fmt.dateTime(v.approvedAt),
                mono: true,
              ),
            if (v.rejectedAt != null)
              DlRow(
                label: dt('auditRejected'),
                value: Fmt.dateTime(v.rejectedAt),
                mono: true,
              ),
            if (v.paidAt != null)
              DlRow(
                label: dt('auditPaid'),
                value: _join([Fmt.dateTime(v.paidAt), v.paidBy]),
                mono: true,
              ),
            DlRow(
              label: dt('verificationCode'),
              value: v.verificationCode,
              mono: true,
            ),
          ],
        ),
      ),
    );
  }
}
