import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/services/voucher_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/signature_pad.dart';
import '../../widgets/vf/vf.dart';
import 'detail_bits.dart';
import 'detail_controller.dart';

/* Every consequential action goes through a dialog that restates the voucher
   and amount, so nobody signs, approves or pays the wrong one by accident —
   the web's dialogs, risen as bottom sheets as they are on a phone. */

Future<T?> _sheet<T>(
  BuildContext context,
  Widget child, {
  bool dismissible = true,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  isDismissible: dismissible,
  enableDrag: dismissible,
  builder: (_) => child,
);

List<VfSummaryRow> _summary(Voucher v) => [
  VfSummaryRow(dt('voucher'), v.number),
  VfSummaryRow(dt('payee'), v.payee),
  VfSummaryRow(dt('amount'), v.amountText),
];

String? _trim(String text) => text.trim().isEmpty ? null : text.trim();

/// A ticked statement (the web's `.radio.vf-statement`): the whole row toggles.
class StatementCheck extends StatelessWidget {
  const StatementCheck({
    super.key,
    required this.value,
    required this.onChanged,
    required this.text,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Semantics(
      checked: value,
      child: InkWell(
        borderRadius: BorderRadius.circular(VfSize.radiusM),
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: Checkbox(
                  value: value,
                  onChanged: (v) => onChanged(v ?? false),
                  activeColor: t.primary,
                  side: BorderSide(color: t.borderStrong, width: 1.5),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 6),
                  child: Text(
                    text,
                    style: VfType.small.copyWith(fontSize: 14.5, color: t.text),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ────────────────────────────────────────────────────────── signature ── */

enum SignatureMode { draw, upload, saved }

/// Draw / upload / reuse a saved signature — the web's `SignaturePad`.
class SignatureChoice extends ChangeNotifier {
  SignatureChoice({this.saved})
    : mode = saved != null ? SignatureMode.saved : SignatureMode.draw {
    pad.addListener(notifyListeners);
  }

  final String? saved;
  final pad = SignaturePadController();
  SignatureMode mode;
  String? uploaded;

  bool get hasSignature => switch (mode) {
    SignatureMode.draw => pad.isNotEmpty,
    SignatureMode.upload => uploaded != null,
    SignatureMode.saved => saved != null,
  };

  /// Whether this signature is newly made (and so worth saving for next time).
  bool get isNew => mode != SignatureMode.saved;

  void setMode(SignatureMode value) {
    mode = value;
    notifyListeners();
  }

  void setUploaded(String? dataUrl) {
    uploaded = dataUrl;
    notifyListeners();
  }

  /// The signature as the data URL the API stores.
  Future<String?> resolve() async => switch (mode) {
    SignatureMode.draw => await pad.toPng().then(
      (png) => png == null ? null : VoucherRepository.encodeSignature(png),
    ),
    SignatureMode.upload => uploaded,
    SignatureMode.saved => saved,
  };

  @override
  void dispose() {
    pad.dispose();
    super.dispose();
  }
}

class SignatureCapture extends StatelessWidget {
  const SignatureCapture({
    super.key,
    required this.choice,
    required this.controller,
  });

  final SignatureChoice choice;
  final VoucherDetailController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return AnimatedBuilder(
      animation: choice,
      builder: (context, _) {
        Widget preview(Uint8List? bytes) => Container(
          height: 120,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: VfDoc.paper,
            border: Border.all(color: t.borderStrong),
            borderRadius: BorderRadius.circular(VfSize.radiusL),
          ),
          child: bytes == null
              ? const SizedBox.shrink()
              : Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<SignatureMode>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: t.primarySoftStrong,
                selectedForegroundColor: t.primaryText,
                foregroundColor: t.text2,
                side: BorderSide(color: t.border),
                textStyle: VfType.label.copyWith(fontSize: 13.5),
                visualDensity: VisualDensity.standard,
              ),
              segments: [
                ButtonSegment(
                  value: SignatureMode.draw,
                  label: Text(
                    dt('drawSignature'),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ButtonSegment(
                  value: SignatureMode.upload,
                  label: Text(
                    dt('uploadSignature'),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ButtonSegment(
                  value: SignatureMode.saved,
                  enabled: choice.saved != null,
                  label: Text(
                    dt('savedSignature'),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              selected: {choice.mode},
              onSelectionChanged: (s) => choice.setMode(s.first),
            ),
            const SizedBox(height: 12),
            switch (choice.mode) {
              SignatureMode.draw => SignaturePad(
                controller: choice.pad,
                height: 170,
              ),
              SignatureMode.upload => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  VouchFlowButton(
                    label: dt('chooseSignatureImage'),
                    icon: PhosphorIconsRegular.image,
                    variant: VfButtonVariant.secondary,
                    expand: true,
                    onPressed: () async {
                      final docs = await controller.pick(
                        DocSource.gallery,
                        multiple: false,
                      );
                      if (docs.isNotEmpty) {
                        choice.setUploaded(
                          VoucherDetailController.imageDataUrl(docs.first),
                        );
                      }
                    },
                  ),
                  if (choice.uploaded != null) ...[
                    const SizedBox(height: 10),
                    preview(decodeSignature(choice.uploaded)),
                  ],
                ],
              ),
              SignatureMode.saved =>
                choice.saved != null
                    ? preview(decodeSignature(choice.saved))
                    : Text(
                        dt('noSavedSignature'),
                        style: VfType.small.copyWith(color: t.muted),
                      ),
            },
          ],
        );
      },
    );
  }
}

/* ─────────────────────────────────────────────────────── sign/approve ── */

Future<void> showSignDialog(BuildContext context, VoucherDetailController c) =>
    _sheet(context, _SignDialog(controller: c, approve: false));

Future<void> showApproveDialog(
  BuildContext context,
  VoucherDetailController c,
) => _sheet(context, _SignDialog(controller: c, approve: true));

class _SignDialog extends StatefulWidget {
  const _SignDialog({required this.controller, required this.approve});

  final VoucherDetailController controller;
  final bool approve;

  @override
  State<_SignDialog> createState() => _SignDialogState();
}

class _SignDialogState extends State<_SignDialog> {
  late final choice = SignatureChoice(
    saved: widget.controller.savedSignature.value,
  );
  final comment = TextEditingController();
  final signedAt = Fmt.dateTime(DateTime.now());
  bool statement = false;
  bool saveForNext = true;

  @override
  void initState() {
    super.initState();
    choice.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    choice.dispose();
    comment.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final c = widget.controller;
    final navigator = Navigator.of(context);
    final signature = await choice.resolve();
    final ok = widget.approve
        ? await c.approve(comment: _trim(comment.text), signature: signature)
        : await c.sign(
            signature: signature,
            save: saveForNext && choice.isNew,
            comment: _trim(comment.text),
          );
    if (ok && navigator.mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final v = c.voucher.value!;
    final me = c.session.user.value;
    final approve = widget.approve;
    // A step that both signs and approves captures the signature on approval.
    final withPad = !approve || v.currentStepCanSign;

    return Obx(() {
      final busy = c.busy.value;
      final valid = approve ? statement : statement && choice.hasSignature;
      return VouchFlowDialog(
        icon: approve
            ? PhosphorIconsRegular.sealCheck
            : PhosphorIconsRegular.signature,
        tone: approve ? VfTone.ok : VfTone.info,
        title: approve ? dt('approveVoucherQ') : dt('confirmSignature'),
        subtitle: approve
            ? dt('approvingForPayment')
            : '${dt('signingAs')} ${me?.name ?? ''}${(me?.jobTitle ?? '').isNotEmpty ? ' — ${me!.jobTitle}' : ''}.',
        summary: [
          ..._summary(v),
          if (!approve) VfSummaryRow(dt('dateTime'), signedAt),
        ],
        actions: [
          DialogActions(
            children: [
              VouchFlowButton(
                label: dt('cancel'),
                variant: VfButtonVariant.secondary,
                onPressed: busy ? null : () => Navigator.of(context).pop(),
              ),
              VouchFlowButton(
                label: approve ? dt('approveVoucher') : dt('confirmSign'),
                icon: approve
                    ? PhosphorIconsRegular.sealCheck
                    : PhosphorIconsRegular.signature,
                loading: busy,
                onPressed: valid && !busy ? _confirm : null,
              ),
            ],
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (withPad) ...[
              SignatureCapture(choice: choice, controller: c),
              if (!approve)
                StatementCheck(
                  value: saveForNext,
                  onChanged: (v) => setState(() => saveForNext = v),
                  text: 'sign.saveForNext'.tr,
                ),
              const SizedBox(height: 10),
            ],
            VouchFlowTextField(
              label: approve ? dt('approvalNote') : dt('commentOptional'),
              controller: comment,
              maxLines: 3,
              minLines: 2,
            ),
            const SizedBox(height: 10),
            StatementCheck(
              value: statement,
              onChanged: (v) => setState(() => statement = v),
              text: approve ? dt('approveStatement') : dt('signStatement'),
            ),
            if (!approve) ...[
              const SizedBox(height: 10),
              VfNote(
                '${dt('signatureRecorded')}${v.currentStepCanApprove ? '' : ' ${dt('signNoApprove')}'}',
              ),
            ],
          ],
        ),
      );
    });
  }
}

/* ─────────────────────────────────────────── reject · request changes ── */

Future<void> showReasonDialog(
  BuildContext context,
  VoucherDetailController c, {
  required bool reject,
}) => _sheet(context, _ReasonDialog(controller: c, reject: reject));

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.controller, required this.reject});

  final VoucherDetailController controller;
  final bool reject;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final reason = TextEditingController();

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final reject = widget.reject;
    final v = c.voucher.value!;
    return Obx(() {
      final busy = c.busy.value;
      final valid = reason.text.trim().length >= 3;
      return VouchFlowDialog(
        icon: reject
            ? PhosphorIconsRegular.xCircle
            : PhosphorIconsRegular.arrowUUpLeft,
        tone: reject ? VfTone.bad : VfTone.warn,
        title: reject ? dt('rejectVoucherQ') : dt('requestChangesQ'),
        subtitle: reject ? dt('rejectingNote') : dt('requestChangesNote'),
        summary: _summary(v),
        actions: [
          DialogActions(
            children: [
              VouchFlowButton(
                label: dt('cancel'),
                variant: VfButtonVariant.secondary,
                onPressed: busy ? null : () => Navigator.of(context).pop(),
              ),
              VouchFlowButton(
                label: reject ? dt('rejectVoucher') : dt('requestChanges'),
                variant: reject
                    ? VfButtonVariant.dangerSolid
                    : VfButtonVariant.primary,
                loading: busy,
                onPressed: !valid || busy
                    ? null
                    : () async {
                        final navigator = Navigator.of(context);
                        final text = reason.text.trim();
                        final ok = reject
                            ? await c.reject(text)
                            : await c.requestChanges(text);
                        if (ok && navigator.mounted) navigator.pop();
                      },
              ),
            ],
          ),
        ],
        child: VouchFlowTextField(
          label: reject ? dt('rejectReason') : dt('changesNeeded'),
          required: true,
          controller: reason,
          autofocus: true,
          maxLines: 5,
          minLines: 4,
          onChanged: (_) => setState(() {}),
          hint: valid ? null : (reject ? dt('rejectHint') : dt('changesHint')),
        ),
      );
    });
  }
}

/* ─────────────────────────────────── submit · submit signed · withdraw ── */

enum CommentAction { submit, submitSigned, cancel }

Future<void> showCommentActionDialog(
  BuildContext context,
  VoucherDetailController c,
  CommentAction action,
) => _sheet(context, _CommentActionDialog(controller: c, action: action));

class _CommentActionDialog extends StatefulWidget {
  const _CommentActionDialog({required this.controller, required this.action});

  final VoucherDetailController controller;
  final CommentAction action;

  @override
  State<_CommentActionDialog> createState() => _CommentActionDialogState();
}

class _CommentActionDialogState extends State<_CommentActionDialog> {
  final comment = TextEditingController();

  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final v = c.voucher.value!;
    final action = widget.action;
    final cancel = action == CommentAction.cancel;
    final (title, sub, label) = switch (action) {
      CommentAction.submit => (
        dt('submitVoucherQ'),
        dt('submitNote'),
        dt('submitApproval'),
      ),
      CommentAction.submitSigned => (
        dt('submitSigned'),
        dt('submitSignedNote'),
        dt('submitSigned'),
      ),
      CommentAction.cancel => (
        dt('cancelVoucherQ'),
        dt('cancelNote'),
        dt('cancelVoucher'),
      ),
    };
    return Obx(() {
      final busy = c.busy.value;
      return VouchFlowDialog(
        icon: cancel
            ? PhosphorIconsRegular.prohibit
            : PhosphorIconsRegular.paperPlaneTilt,
        tone: cancel ? VfTone.bad : VfTone.info,
        title: title,
        subtitle: sub,
        summary: _summary(v),
        actions: [
          DialogActions(
            children: [
              VouchFlowButton(
                label: dt('cancel'),
                variant: VfButtonVariant.secondary,
                onPressed: busy ? null : () => Navigator.of(context).pop(),
              ),
              VouchFlowButton(
                label: label,
                icon: cancel ? null : PhosphorIconsRegular.paperPlaneTilt,
                variant: cancel
                    ? VfButtonVariant.dangerSolid
                    : VfButtonVariant.primary,
                loading: busy,
                onPressed: busy
                    ? null
                    : () async {
                        final navigator = Navigator.of(context);
                        final text = _trim(comment.text);
                        final ok = switch (action) {
                          CommentAction.submit => await c.submit(comment: text),
                          CommentAction.submitSigned => await c.submitSigned(
                            comment: text,
                          ),
                          CommentAction.cancel => await c.cancel(comment: text),
                        };
                        if (ok && navigator.mounted) navigator.pop();
                      },
              ),
            ],
          ),
        ],
        child: VouchFlowTextField(
          label: dt('commentOptional'),
          controller: comment,
          maxLines: 3,
          minLines: 2,
        ),
      );
    });
  }
}

/// Delete a draft — behind a confirmation, never a single tap. Returns true
/// once it is gone.
Future<bool> showDeleteDialog(
  BuildContext context,
  VoucherDetailController c,
) async {
  final v = c.voucher.value!;
  final result = await _sheet<bool>(
    context,
    Obx(() {
      final busy = c.busy.value;
      return Builder(
        builder: (ctx) => VouchFlowDialog(
          icon: PhosphorIconsRegular.trash,
          tone: VfTone.bad,
          title: dt('deleteDraftQ'),
          subtitle: dt('cannotBeUndone'),
          summary: _summary(v),
          actions: [
            DialogActions(
              children: [
                VouchFlowButton(
                  label: dt('cancel'),
                  variant: VfButtonVariant.secondary,
                  onPressed: busy ? null : () => Navigator.of(ctx).pop(false),
                ),
                VouchFlowButton(
                  label: dt('deleteDraft'),
                  icon: PhosphorIconsRegular.trash,
                  variant: VfButtonVariant.dangerSolid,
                  loading: busy,
                  onPressed: busy
                      ? null
                      : () async {
                          final navigator = Navigator.of(ctx);
                          final ok = await c.deleteDraft();
                          if (ok && navigator.mounted) navigator.pop(true);
                        },
                ),
              ],
            ),
          ],
        ),
      );
    }),
  );
  return result == true;
}

/* ───────────────────────────────────────────────────────────── pay ── */

/// Record a payment — the whole balance by default, or part of it now and the
/// rest later. Then the receipt, and with it the acknowledgement to print.
Future<void> showPayDialog(
  BuildContext context,
  VoucherDetailController c,
) async {
  final result = await _sheet<(Voucher, VoucherPayment?)>(
    context,
    _PayDialog(controller: c),
  );
  if (result == null || !context.mounted) return;
  await _sheet<void>(
    context,
    _ReceiptDialog(controller: c, voucher: result.$1, payment: result.$2),
  );
}

class _PayDialog extends StatefulWidget {
  const _PayDialog({required this.controller});

  final VoucherDetailController controller;

  @override
  State<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends State<_PayDialog> {
  late final Voucher v = widget.controller.voucher.value!;
  late final double outstanding = v.balance ?? v.outstanding;
  late final amount = TextEditingController(
    text: outstanding % 1 == 0
        ? Fmt.plain(outstanding)
        : outstanding.toStringAsFixed(2),
  );
  final reference = TextEditingController();
  late final receivedBy = TextEditingController(text: v.isCash ? v.payee : '');
  final receiverId = TextEditingController();
  final comment = TextEditingController();
  late String method = v.isCash ? 'Cash — office float' : 'Bank transfer';

  List<String> get methods => v.isCash
      ? const ['Cash — office float', 'Cash — branch float']
      : const ['Bank transfer', 'Cheque', 'Mobile money'];

  bool get isCheque => method.toLowerCase().contains('cheque');

  @override
  void dispose() {
    for (final c in [amount, reference, receivedBy, receiverId, comment]) {
      c.dispose();
    }
    super.dispose();
  }

  double? get value {
    final cleaned = amount.text.replaceAll(RegExp(r'[,\s]'), '');
    if (cleaned.isEmpty) return null;
    final n = double.tryParse(cleaned);
    return n == null ? null : (n * 100).roundToDouble() / 100;
  }

  String? get amountError {
    final n = value;
    if (n == null || n <= 0) return dt('amountMustBePositive');
    if (n > outstanding + 0.001) {
      return dt('amountOverBalance', {
        'amount': Fmt.money(outstanding, v.currency),
      });
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final t = context.vf;
    final partly = v.isPartiallyPaid;
    final err = amountError;
    final remainder = value == null
        ? outstanding
        : (outstanding - value!).clamp(0, outstanding).toDouble();
    final settles = value != null && err == null && remainder <= 0.001;
    final ready =
        err == null &&
        (v.isCash
            ? receivedBy.text.trim().isNotEmpty
            : reference.text.trim().isNotEmpty);

    return Obx(() {
      final busy = c.busy.value;
      return VouchFlowDialog(
        icon: PhosphorIconsRegular.wallet,
        tone: VfTone.ok,
        title: partly ? dt('payRemainingBalance') : dt('recordPayment'),
        subtitle: settles || err != null
            ? dt('markAsPaidNote')
            : dt('partPayNote'),
        summary: [
          ..._summary(v),
          if (partly) ...[
            VfSummaryRow(dt('paidSoFar'), v.amountPaidText ?? '—'),
            VfSummaryRow(
              dt('balanceLabel'),
              v.balanceText ?? Fmt.money(outstanding, v.currency),
            ),
          ],
          VfSummaryRow(dt('voucherFormat'), v.isCash ? dt('cash') : dt('bank')),
        ],
        actions: [
          DialogActions(
            children: [
              VouchFlowButton(
                label: dt('cancel'),
                variant: VfButtonVariant.secondary,
                onPressed: busy ? null : () => Navigator.of(context).pop(),
              ),
              VouchFlowButton(
                label: partly ? dt('payRemainingBalance') : dt('recordPayment'),
                icon: PhosphorIconsBold.check,
                loading: busy,
                onPressed: !ready || busy
                    ? null
                    : () async {
                        final navigator = Navigator.of(context);
                        final n = value!;
                        final result = await c.pay(
                          method: method,
                          reference: _trim(reference.text),
                          receivedBy: _trim(receivedBy.text),
                          receiverIdNumber: _trim(receiverId.text),
                          comment: _trim(comment.text),
                          // Left out, the server pays the whole balance.
                          amount: n < outstanding - 0.001 ? n : null,
                        );
                        if (result != null && navigator.mounted) {
                          navigator.pop(result);
                        }
                      },
              ),
            ],
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            VouchFlowTextField(
              label: dt('amountToPayNow'),
              required: true,
              controller: amount,
              prefixText: '${v.currency} ',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              error: amount.text.trim().isEmpty ? null : err,
              hint: settles
                  ? dt('settlesVoucher')
                  : dt('balanceAfterPayment', {
                      'amount': Fmt.money(remainder, v.currency),
                    }),
            ),
            const SizedBox(height: 14),
            VouchFlowDropdown<String>(
              label: dt('payFrom'),
              items: methods,
              value: method,
              itemLabel: (m) => m,
              onChanged: (m) => setState(() => method = m ?? method),
            ),
            const SizedBox(height: 14),
            if (!v.isCash)
              VouchFlowTextField(
                label: isCheque ? dt('chequeNo') : dt('paymentRef'),
                required: true,
                controller: reference,
                onChanged: (_) => setState(() {}),
                hint: dt('eg', {
                  'value': isCheque ? '004471' : 'CRDB-TRX-8841207',
                }),
              )
            else ...[
              VouchFlowTextField(
                label: dt('receivedBy'),
                required: true,
                controller: receivedBy,
                onChanged: (_) => setState(() {}),
                hint: dt('receivedByHint'),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 14),
              VouchFlowTextField(
                label: dt('receiverIdNo'),
                controller: receiverId,
                hint: dt('receiverIdHint'),
              ),
            ],
            const SizedBox(height: 14),
            VouchFlowTextField(
              label: dt('commentOptional'),
              controller: comment,
              maxLines: 3,
              minLines: 2,
            ),
            if (v.isCash) ...[
              const SizedBox(height: 12),
              Text(
                'pay.ackNote'.tr,
                style: VfType.meta.copyWith(color: t.muted),
              ),
            ],
          ],
        ),
      );
    });
  }
}

class _ReceiptDialog extends StatelessWidget {
  const _ReceiptDialog({
    required this.controller,
    required this.voucher,
    required this.payment,
  });

  final VoucherDetailController controller;
  final Voucher voucher;
  final VoucherPayment? payment;

  @override
  Widget build(BuildContext context) {
    final p = payment;
    final v = voucher;
    final paid = v.status == 'paid';
    final cash = v.isCash;
    final reference = p?.paymentReference ?? v.paymentReference;
    return Obx(
      () => VouchFlowDialog(
        icon: PhosphorIconsRegular.checkCircle,
        tone: VfTone.ok,
        title: paid ? dt('paymentCompleted') : dt('partPaymentRecorded'),
        subtitle: !paid && p != null
            ? dt('partPaymentBody', {
                'amount': p.amountText,
                'balance': p.balanceAfterText,
              })
            : null,
        summary: [
          VfSummaryRow(dt('voucher'), p?.reference ?? v.number),
          VfSummaryRow(dt('amount'), p?.amountText ?? v.amountText),
          if (p != null && p.balanceAfter > 0)
            VfSummaryRow(dt('balanceAfter'), p.balanceAfterText),
          if ((p?.receivedBy ?? '').isNotEmpty)
            VfSummaryRow(
              dt('receivedBy'),
              [p!.receivedBy!, ?p.receiverIdNumber].join(' · '),
            ),
          VfSummaryRow(
            dt('paidByOn'),
            p?.paidBy ?? v.paidBy ?? controller.session.user.value?.name ?? '—',
          ),
          VfSummaryRow(dt('dateTime'), Fmt.dateTime(p?.paidAt ?? v.paidAt)),
          if ((reference ?? '').isNotEmpty)
            VfSummaryRow(dt('paymentRef'), reference!),
        ],
        actions: [
          DialogActions(
            children: [
              VouchFlowButton(
                label: dt('done'),
                variant: cash || p == null
                    ? VfButtonVariant.secondary
                    : VfButtonVariant.primary,
                onPressed: () => Navigator.of(context).pop(),
              ),
              if (p != null)
                VouchFlowButton(
                  label: dt('printAcknowledgement'),
                  icon: PhosphorIconsRegular.printer,
                  variant: cash
                      ? VfButtonVariant.primary
                      : VfButtonVariant.secondary,
                  loading: controller.working.value == 'ack-print-${p.id}',
                  onPressed: controller.working.value != null
                      ? null
                      : () => controller.printAcknowledgement(p),
                ),
            ],
          ),
        ],
        child: p == null
            ? null
            : VfNote(cash ? dt('printAckForReceiver') : dt('printAckForFile')),
      ),
    );
  }
}

/* ─────────────────────────────────────────────────── picking a file ── */

/// Camera, gallery or a file — where the document is coming from.
Future<DocSource?> pickDocSource(
  BuildContext context, {
  required String title,
  String? hint,
}) {
  return showVouchFlowBottomSheet<DocSource>(
    context,
    title: title,
    child: Builder(
      builder: (ctx) {
        final t = ctx.vf;
        Widget tile(IconData icon, String label, DocSource source) => ListTile(
          contentPadding: EdgeInsets.zero,
          minTileHeight: 60,
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: t.primarySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 21, color: t.primaryText),
          ),
          trailing: Icon(PhosphorIconsBold.caretRight, size: 14, color: t.faint),
          title: Text(label, style: VfType.body.copyWith(color: t.text)),
          onTap: () => Navigator.of(ctx).pop(source),
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hint != null) ...[
                Text(hint, style: VfType.small.copyWith(color: t.muted)),
                const SizedBox(height: 8),
              ],
              tile(
                PhosphorIconsRegular.camera,
                'voucher.addReceiptCamera'.tr,
                DocSource.camera,
              ),
              tile(
                PhosphorIconsRegular.images,
                'voucher.addReceiptGallery'.tr,
                DocSource.gallery,
              ),
              tile(
                PhosphorIconsRegular.filePdf,
                dt('chooseFile'),
                DocSource.file,
              ),
            ],
          ),
        );
      },
    ),
  );
}

/* ──────────────────────────────────────────────── opening a document ── */

/// Opens a stored attachment or filed acknowledgement: an image or PDF shown
/// full screen, with the phone's share sheet to save or send it.
Future<void> openAttachment(VoucherDetailController c, Attachment file) async {
  c.working.value = 'open-${file.id}';
  final bytes = await c.attachmentBytes(file.id);
  c.working.value = null;
  if (bytes == null) return;
  await Get.to<void>(() => _AttachmentViewer(file: file, bytes: bytes));
}

class _AttachmentViewer extends StatefulWidget {
  const _AttachmentViewer({required this.file, required this.bytes});

  final Attachment file;
  final Uint8List bytes;

  @override
  State<_AttachmentViewer> createState() => _AttachmentViewerState();
}

class _AttachmentViewerState extends State<_AttachmentViewer> {
  List<Uint8List>? pages;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.file.isPdf) _raster();
  }

  Future<void> _raster() async {
    try {
      final out = <Uint8List>[];
      await for (final page in Printing.raster(widget.bytes, dpi: 144)) {
        out.add(await page.toPng());
      }
      if (mounted) setState(() => pages = out);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  Future<void> _share() => Share.shareXFiles([
    XFile.fromData(
      widget.bytes,
      name: widget.file.name,
      mimeType: widget.file.mimeType,
    ),
  ], subject: widget.file.name);

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final Widget body;
    if (!widget.file.isPdf) {
      body = InteractiveViewer(
        maxScale: 5,
        child: Center(
          child: Image.memory(
            widget.bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: VouchFlowEmptyState(
                icon: PhosphorIconsRegular.file,
                title: widget.file.name,
                body: dt('openFailed'),
              ),
            ),
          ),
        ),
      );
    } else if (pages == null && !failed) {
      body = const Center(child: CircularProgressIndicator());
    } else if (failed || pages!.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(24),
        child: VouchFlowEmptyState(
          icon: PhosphorIconsRegular.filePdf,
          title: widget.file.name,
          body: dt('openFailed'),
          actionLabel: dt('share'),
          onAction: _share,
        ),
      );
    } else {
      body = InteractiveViewer(
        maxScale: 5,
        child: ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: pages!.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, i) => DecoratedBox(
            decoration: BoxDecoration(boxShadow: t.cardShadow),
            child: Image.memory(pages![i], fit: BoxFit.fitWidth),
          ),
        ),
      );
    }
    return VouchFlowPushedScaffold(
      title: widget.file.name,
      actions: [
        VfBarButton(
          icon: PhosphorIconsRegular.shareNetwork,
          tooltip: dt('share'),
          onPressed: _share,
        ),
      ],
      body: ColoredBox(color: t.surface2, child: body),
    );
  }
}

/// A dialog's buttons side by side while their labels fit, stacked (the
/// confirming one first) when they would be cut short on a narrow phone.
class DialogActions extends StatelessWidget {
  const DialogActions({super.key, required this.children, this.reverseWhenStacked = true});

  final List<Widget> children;

  /// Stacked, a dialog puts its confirming (last) button first.
  final bool reverseWhenStacked;

  static double _need(Widget w) {
    if (w is! VouchFlowButton) return 120;
    final painter = TextPainter(
      text: TextSpan(text: w.label, style: VfType.bodyStrong),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width + 36 + (w.icon != null ? 26 : 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 10.0;
        final each =
            (c.maxWidth - gap * (children.length - 1)) / children.length;
        final fits = children.every((w) => _need(w) <= each);
        if (fits) {
          return Row(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                Expanded(child: children[i]),
              ],
            ],
          );
        }
        final ordered = reverseWhenStacked ? children.reversed.toList() : children;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < ordered.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              ordered[i],
            ],
          ],
        );
      },
    );
  }
}
