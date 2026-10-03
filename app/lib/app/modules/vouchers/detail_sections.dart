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

/// Who, what, where and how — one info list with icons.
class RequestDetailsPanel extends StatelessWidget {
  const RequestDetailsPanel({super.key, required this.voucher});

  final Voucher voucher;

  @override
  Widget build(BuildContext context) {
    final v = voucher;
    final hasBank =
        !v.isCash &&
        ((v.payeeBank ?? '').isNotEmpty ||
            (v.payeeAccountNumber ?? '').isNotEmpty);
    return DetailPanel(
      title: dt('details'),
      padding: const EdgeInsets.fromLTRB(14, 2, 16, 2),
      child: InfoList(
        rows: [
          DlRow(
            icon: PhosphorIconsRegular.user,
            label: dt('payee'),
            value: v.payee,
          ),
          DlRow(
            icon: PhosphorIconsRegular.userCircle,
            label: dt('requestedBy'),
            value: _join([v.requesterName, v.requesterJobTitle]),
          ),
          DlRow(
            icon: PhosphorIconsRegular.buildings,
            label: dt('department'),
            value: _join([v.departmentName, v.costCentre]),
          ),
          DlRow(
            icon: PhosphorIconsRegular.calendarBlank,
            label: dt('date'),
            value: v.voucherDate == null ? null : Fmt.date(v.voucherDate),
          ),
          DlRow(
            icon: PhosphorIconsRegular.tag,
            label: dt('voucherType'),
            value: v.voucherTypeLabel,
          ),
          DlRow(
            icon: PhosphorIconsRegular.folderSimple,
            label: dt('category'),
            value: v.category,
          ),
          DlRow(
            icon: v.isCash
                ? PhosphorIconsRegular.money
                : PhosphorIconsRegular.bank,
            label: dt('voucherFormat'),
            value: v.isCash ? dt('cash') : dt('bank'),
          ),
          DlRow(
            icon: PhosphorIconsRegular.creditCard,
            label: dt('paymentMethod'),
            value: v.paymentMethod,
          ),
          DlRow(
            icon: PhosphorIconsRegular.hash,
            label: dt('accountRef'),
            value: v.accountRef,
            mono: true,
          ),
          if (hasBank) ...[
            DlRow(
              icon: PhosphorIconsRegular.bank,
              label: dt('bank'),
              value: _join([v.payeeBank, v.payeeBankBranch]),
            ),
            DlRow(
              icon: PhosphorIconsRegular.identificationCard,
              label: dt('accountName'),
              value: v.payeeAccountName,
            ),
            DlRow(
              icon: PhosphorIconsRegular.hash,
              label: dt('accountNumber'),
              value: v.payeeAccountNumber,
              mono: true,
            ),
          ],
          if (v.isCash)
            DlRow(
              icon: PhosphorIconsRegular.wallet,
              label: dt('payFrom'),
              value: v.cashFloat,
            ),
          if (v.status == 'paid') ...[
            DlRow(
              icon: PhosphorIconsRegular.checkCircle,
              label: dt('paidByOn'),
              value: _join([
                v.paidBy,
                v.paidAt == null ? null : Fmt.dateTime(v.paidAt),
              ]),
            ),
            DlRow(
              icon: PhosphorIconsRegular.receipt,
              label: dt('paymentRef'),
              value: v.paymentReference,
              mono: true,
            ),
            DlRow(
              icon: PhosphorIconsRegular.handCoins,
              label: dt('receivedBy'),
              value: v.receivedBy,
            ),
          ],
          DlRow(
            icon: PhosphorIconsRegular.textAlignLeft,
            label: dt('description'),
            value: v.description,
            stacked: true,
          ),
          DlRow(
            icon: PhosphorIconsRegular.note,
            label: dt('notes'),
            value: v.notesToApprover,
            stacked: true,
          ),
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

    return DetailPanel(
      title: dt('payments'),
      count: v.payments.length,
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoList(
            rows: [
              DlRow(
                label: dt('approvedAmount'),
                value: v.amountText,
                mono: true,
                strong: true,
              ),
              DlRow(
                label: dt('paidSoFar'),
                value: v.amountPaidText ?? Fmt.money(paid, v.currency),
                mono: true,
                strong: true,
                valueColor: paid > 0 ? t.successStrong : null,
              ),
              DlRow(
                label: dt('balanceLabel'),
                value: v.balanceText ?? Fmt.money(balance, v.currency),
                mono: true,
                strong: true,
                valueColor: balance > 0 ? t.warningStrong : null,
              ),
            ],
          ),
          Divider(height: 1, color: t.border),
          if (v.payments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
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
      padding: const EdgeInsets.symmetric(vertical: 14),
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
      padding: EdgeInsets.fromLTRB(14, v.attachments.isEmpty ? 14 : 4, 14, v.attachments.isEmpty ? 14 : 4),
      action: v.actions.attach
          ? Obx(
              () => PanelAction(
                label: afterDecision ? dt('addReceipt') : dt('add'),
                icon: PhosphorIconsBold.plus,
                loading: controller.working.value == 'attach',
                onTap: controller.working.value != null
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
          if (v.attachments.isEmpty)
            MutedLine(
              icon: PhosphorIconsRegular.paperclip,
              text: dt('noneAttached'),
            )
          else
            for (var i = 0; i < v.attachments.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: 52,
                  color: t.border.withValues(alpha: t.isDark ? 1 : .7),
                ),
              _FileRow(controller: controller, voucher: v, file: v.attachments[i]),
            ],
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
    return InkWell(
        onTap: () => openAttachment(controller, file),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: file.isImage ? t.infoSoft : t.dangerSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  file.isImage
                      ? PhosphorIconsFill.image
                      : PhosphorIconsFill.filePdf,
                  size: 20,
                  color: file.isImage ? t.infoStrong : t.dangerStrong,
                ),
              ),
              const SizedBox(width: 12),
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
                        PhosphorIconsBold.caretRight,
                        size: 14,
                        color: t.faint,
                      ),
              ),
            ],
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
    final pill = OutlineInputBorder(
      borderRadius: BorderRadius.circular(VfSize.radiusPill),
      borderSide: BorderSide.none,
    );
    return DetailPanel(
      title: dt('comments'),
      count: voucher.comments.length,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in voucher.comments) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VouchFlowAvatar(initials: c.authorInitials, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                    decoration: BoxDecoration(
                      color: t.surface3,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                c.authorName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: VfType.small.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: t.text,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              Fmt.relative(c.createdAt),
                              style: VfType.meta.copyWith(
                                fontSize: 12,
                                color: t.muted,
                              ),
                            ),
                          ],
                        ),
                        if ((c.authorDepartment ?? c.authorRole ?? '').isNotEmpty)
                          Text(
                            (c.authorDepartment ?? c.authorRole)!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: VfType.meta.copyWith(
                              fontSize: 12,
                              color: t.muted,
                            ),
                          ),
                        const SizedBox(height: 3),
                        Text(c.body, style: VfType.body.copyWith(color: t.text)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller.commentField,
                  style: VfType.body.copyWith(color: t.text),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => controller.postComment(),
                  cursorColor: t.primary,
                  decoration: InputDecoration(
                    hintText: dt('addComment'),
                    hintMaxLines: 1,
                    hintStyle: VfType.body.copyWith(color: t.muted),
                    isDense: true,
                    filled: true,
                    fillColor: t.surface3,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    border: pill,
                    enabledBorder: pill,
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(VfSize.radiusPill),
                      borderSide: BorderSide(color: t.primary, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Obx(() {
                final empty = controller.commentText.value.trim().isEmpty;
                return Tooltip(
                  message: dt('post'),
                  child: Material(
                    color: empty ? t.surface3 : t.primary,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: empty ? null : controller.postComment,
                      child: SizedBox(
                        width: 46,
                        height: 46,
                        child: Icon(
                          PhosphorIconsFill.paperPlaneRight,
                          size: 19,
                          color: empty ? t.faint : Colors.white,
                          semanticLabel: dt('post'),
                        ),
                      ),
                    ),
                  ),
                );
              }),
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
    return DetailDisclosure(
      title: dt('auditTrail'),
      icon: PhosphorIconsRegular.scroll,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: InfoList(
          rows: [
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
