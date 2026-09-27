import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/session_service.dart';
import '../../data/services/voucher_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/voucher_document.dart';
import '../../widgets/signature_pad.dart';

class VoucherDetailController extends GetxController {
  VoucherDetailController(this.voucherId);

  final int voucherId;
  final repo = Get.find<VoucherRepository>();
  final session = Get.find<SessionService>();

  final voucher = Rxn<Voucher>();
  final loading = true.obs;
  final error = RxnString();
  final busy = false.obs;
  final commentField = TextEditingController();

  String? savedSignature;

  @override
  void onInit() {
    super.onInit();
    load();
    repo
        .savedSignature()
        .then((value) => savedSignature = value)
        .catchError((_) => null);
  }

  Future<void> load() async {
    loading.value = true;
    error.value = null;
    try {
      voucher.value = await repo.show(voucherId);
    } on ApiException catch (e) {
      error.value = e.isForbidden ? 'state.notAuthorisedBody'.tr : e.message;
    } catch (_) {
      error.value = 'state.offline'.tr;
    } finally {
      loading.value = false;
    }
  }

  /// Adds a photo of a receipt or document — also after approval and payment,
  /// when the voucher's details are locked but its paperwork is not.
  Future<void> addDocument(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
    );
    if (picked == null) return;
    busy.value = true;
    try {
      await repo.attach(voucherId, [
        await http.MultipartFile.fromPath('files[]', picked.path),
      ]);
      await load();
      showToast('voucher.receiptAdded'.tr);
    } on ApiException catch (e) {
      showToast('state.error'.tr, body: e.message, kind: ToastKind.bad);
    } catch (_) {
      showToast(
        'state.error'.tr,
        body: 'state.offline'.tr,
        kind: ToastKind.bad,
      );
    } finally {
      busy.value = false;
    }
  }

  Future<void> run(
    Future<Voucher> Function() action,
    String title, [
    String? body,
  ]) async {
    busy.value = true;
    try {
      voucher.value = await action();
      showToast(title, body: body);
      await session.refreshUnread();
    } on ApiException catch (e) {
      showToast('state.error'.tr, body: e.message, kind: ToastKind.bad);
    } catch (_) {
      showToast(
        'state.error'.tr,
        body: 'state.offline'.tr,
        kind: ToastKind.bad,
      );
    } finally {
      busy.value = false;
    }
  }

  /// Records one payment — all of the balance or part of it — then offers the
  /// acknowledgement the receiver signs for that payment.
  Future<void> pay({
    required String method,
    String? reference,
    String? receivedBy,
    String? receiverIdNumber,
    String? comment,
    double? amount,
  }) async {
    final v = voucher.value;
    if (v == null) return;
    final before = v.payments.map((p) => p.id).toSet();
    busy.value = true;
    Voucher updated;
    try {
      updated = await repo.pay(
        voucherId,
        isCash: v.isCash,
        method: method,
        reference: reference,
        receivedBy: receivedBy,
        receiverIdNumber: receiverIdNumber,
        comment: comment,
        amount: amount,
      );
      voucher.value = updated;
      await session.refreshUnread();
    } on ApiException catch (e) {
      showToast('state.error'.tr, body: e.message, kind: ToastKind.bad);
      return;
    } catch (_) {
      showToast(
        'state.error'.tr,
        body: 'state.offline'.tr,
        kind: ToastKind.bad,
      );
      return;
    } finally {
      busy.value = false;
    }

    final fresh = updated.payments.where((p) => !before.contains(p.id));
    final payment = fresh.isNotEmpty
        ? fresh.reduce((a, b) => a.sequence >= b.sequence ? a : b)
        : null;

    showToast(
      updated.isPartiallyPaid ? 'pay.partRecorded'.tr : 'pay.record'.tr,
      body: updated.isPartiallyPaid
          ? 'pay.balanceShort'.trParams({
              'amount':
                  updated.balanceText ??
                  Fmt.money(updated.outstanding, updated.currency),
            })
          : '${updated.number} · ${payment?.amountText ?? updated.amountText}',
    );
    if (payment == null) return;

    final printNow = await Get.dialog<bool>(
      AlertDialog(
        title: Text('pay.recordedTitle'.tr),
        content: Text(
          'pay.printAckPrompt'.trParams({
            'amount': payment.amountText,
            'reference': payment.reference,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('pay.later'.tr),
          ),
          FilledButton.icon(
            onPressed: () => Get.back(result: true),
            icon: const Icon(Icons.print_outlined, size: 18),
            label: Text('pay.printAck'.tr),
          ),
        ],
      ),
    );
    if (printNow == true) await printAcknowledgement(payment);
  }

  /// Prints the acknowledgement the receiver signs when taking the money.
  Future<void> printAcknowledgement(VoucherPayment payment) async {
    try {
      final bytes = await repo.acknowledgementPdf(
        voucherId,
        payment.id,
        lang: session.locale.value == 'sw' ? 'sw' : null,
      );
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'acknowledgement-${payment.reference.replaceAll('/', '-')}',
      );
    } on ApiException catch (e) {
      showToast('state.error'.tr, body: e.message, kind: ToastKind.bad);
    } catch (_) {
      showToast(
        'state.error'.tr,
        body: 'state.offline'.tr,
        kind: ToastKind.bad,
      );
    }
  }

  /// Files a photo of the receiver's signed acknowledgement against its
  /// payment. The server decides who may; a refusal is shown, not hidden.
  Future<void> uploadAcknowledgement(
    VoucherPayment payment,
    ImageSource source,
  ) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
    );
    if (picked == null) return;
    busy.value = true;
    try {
      voucher.value = await repo.uploadAcknowledgement(
        voucherId,
        payment.id,
        await http.MultipartFile.fromPath('file', picked.path),
      );
      showToast('pay.ackUploaded'.tr, body: payment.reference);
    } on ApiException catch (e) {
      showToast('state.error'.tr, body: e.message, kind: ToastKind.bad);
    } catch (_) {
      showToast(
        'state.error'.tr,
        body: 'state.offline'.tr,
        kind: ToastKind.bad,
      );
    } finally {
      busy.value = false;
    }
  }

  /// Whether to offer filing a signed copy: an administrator, anyone who can
  /// pay this voucher, or the cashier who made the payment.
  bool canFileAcknowledgement(VoucherPayment payment) {
    final me = session.user.value;
    final v = voucher.value;
    if (me == null || v == null) return false;
    return me.role == 'company_admin' ||
        v.actions.pay ||
        (me.isCashier && payment.paidBy == me.name);
  }

  Future<void> postComment() async {
    final text = commentField.text.trim();
    if (text.isEmpty) return;
    try {
      await repo.comment(voucherId, text);
      commentField.clear();
      await load();
    } on ApiException catch (e) {
      showToast('state.error'.tr, body: e.message, kind: ToastKind.bad);
    }
  }

  Future<void> printPdf() async {
    try {
      final bytes = await repo.pdf(voucherId);
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: voucher.value?.number ?? 'voucher',
      );
    } on ApiException catch (e) {
      showToast('state.error'.tr, body: e.message, kind: ToastKind.bad);
    }
  }

  Future<void> sharePdf() async {
    final v = voucher.value;
    final number = v?.number ?? 'voucher';
    try {
      final bytes = await repo.pdf(voucherId, download: true);
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            name: '$number.pdf',
            mimeType: 'application/pdf',
          ),
        ],
        subject: number,
        text: v?.purpose,
      );
    } on ApiException {
      // The PDF is generated server-side. Until it exists, share the voucher's
      // own particulars rather than nothing.
      if (v == null) return;
      await Share.share(
        [
          '${v.number} · ${v.statusLabel}',
          '${v.purpose} — ${v.payee}',
          v.amountText,
          if (v.amountInWords != null) v.amountInWords!,
          if (v.verificationCode != null)
            '${'voucher.verification'.tr}: ${v.verificationCode}',
        ].join('\n'),
        subject: v.number,
      );
    }
  }

  @override
  void onClose() {
    commentField.dispose();
    super.onClose();
  }
}

class VoucherDetailPage extends StatelessWidget {
  const VoucherDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final id = Get.arguments as int;
    final controller = Get.put(VoucherDetailController(id), tag: '$id');

    return Scaffold(
      appBar: AppBar(
        title: Obx(
          () => Text(controller.voucher.value?.number ?? 'voucher.new'.tr),
        ),
        actions: [
          Obx(() {
            final v = controller.voucher.value;
            if (v == null) return const SizedBox.shrink();
            return Row(
              children: [
                if (v.actions.print)
                  IconButton(
                    tooltip: 'act.print'.tr,
                    onPressed: controller.printPdf,
                    icon: const Icon(Icons.print_outlined),
                  ),
                if (v.actions.download)
                  IconButton(
                    tooltip: 'act.share'.tr,
                    onPressed: controller.sharePdf,
                    icon: const Icon(Icons.ios_share),
                  ),
              ],
            );
          }),
        ],
      ),
      body: Obx(() {
        if (controller.loading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.error.value != null) {
          return ErrorView(
            message: controller.error.value!,
            onRetry: controller.load,
          );
        }

        final v = controller.voucher.value!;
        return RefreshIndicator(
          onRefresh: controller.load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 120),
            children: [
              _Header(voucher: v),
              const SizedBox(height: 18),

              /* The document is the page. Everything secondary folds away
                 beneath it, so what is on screen is what will print. */
              DocumentFrame(
                child: VoucherDocument(
                  voucher: v,
                  company: Get.find<SessionService>().company.value,
                ),
              ),
              const SizedBox(height: 16),

              if (v.payments.isNotEmpty || v.isPartiallyPaid)
                Disclosure(
                  title: 'pay.payments'.tr,
                  icon: Icons.payments_outlined,
                  count: v.payments.length,
                  initiallyOpen: v.isPartiallyPaid,
                  child: _Payments(voucher: v, controller: controller),
                ),
              Disclosure(
                title: 'voucher.attachments'.tr,
                icon: Icons.attach_file,
                count: v.attachments.length,
                child: _Details(voucher: v, controller: controller),
              ),
              Disclosure(
                title: 'voucher.timeline'.tr,
                icon: Icons.timeline_outlined,
                count: v.timeline.length,
                child: _Timeline(voucher: v),
              ),
              Disclosure(
                title: 'voucher.comments'.tr,
                icon: Icons.chat_bubble_outline,
                count: v.comments.length,
                child: _Comments(controller: controller, voucher: v),
              ),
            ],
          ),
        );
      }),
      bottomNavigationBar: Obx(() {
        final v = controller.voucher.value;
        if (v == null || !(v.actions.hasWorkflowAction || v.actions.submit)) {
          return const SizedBox.shrink();
        }
        return _ActionBar(controller: controller, voucher: v);
      }),
    );
  }
}

/// Identity only. The document beneath carries the rest, so repeating the
/// purpose, description and amount here would just push it off the screen.
class _Header extends StatelessWidget {
  const _Header({required this.voucher});

  final Voucher voucher;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          voucher.number,
          style: theme.textTheme.displaySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            KindChip(kind: voucher.kind, dense: false),
            StatusChip(label: voucher.statusLabel, tag: voucher.displayTag),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          [
            voucher.voucherTypeLabel,
            voucher.departmentName,
            Fmt.date(voucher.voucherDate),
          ].whereType<String>().join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        Text(voucher.amountText, style: theme.textTheme.headlineMedium),
        if (voucher.isPartiallyPaid) ...[
          const SizedBox(height: 4),
          Text(
            [
              'pay.paidSoFarShort'.trParams({
                'amount':
                    voucher.amountPaidText ??
                    Fmt.money(voucher.amountPaid, voucher.currency),
              }),
              'pay.balanceShort'.trParams({
                'amount':
                    voucher.balanceText ??
                    Fmt.money(voucher.outstanding, voucher.currency),
              }),
            ].join(' · '),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: VfColors.warn,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.voucher, required this.controller});

  final VoucherDetailController controller;

  final Voucher voucher;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('voucher.payee'.tr, voucher.payee),
      ('voucher.requester'.tr, voucher.requesterName ?? '—'),
      ('voucher.method'.tr, voucher.paymentMethod ?? '—'),
      ('voucher.category'.tr, voucher.category ?? '—'),
      ('voucher.reference'.tr, voucher.accountRef ?? '—'),
      ('voucher.costCentre'.tr, voucher.costCentre ?? '—'),
      if (voucher.paymentReference != null)
        ('pay.reference'.tr, voucher.paymentReference!),
      if (voucher.paidAt != null) ('pay.on'.tr, Fmt.dateTime(voucher.paidAt)),
      if (voucher.paidBy != null) ('pay.by'.tr, voucher.paidBy!),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 12),
        Wrap(
          spacing: 26,
          runSpacing: 14,
          children: rows
              .map(
                (row) => SizedBox(
                  width: 150,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.$1.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        row.$2,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
        if (voucher.attachments.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'voucher.attachments'.tr,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: voucher.attachments
                .map(
                  (file) => Chip(
                    avatar: Icon(
                      file.isAcknowledgement
                          ? Icons.verified_outlined
                          : file.isImage
                          ? Icons.image_outlined
                          : Icons.picture_as_pdf_outlined,
                      size: 16,
                    ),
                    label: Text('${file.name} · ${file.size}'),
                  ),
                )
                .toList(),
          ),
        ],
        if (voucher.actions.attach) ...[
          const SizedBox(height: 14),
          if (voucher.status == 'approved' || voucher.status == 'paid')
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'voucher.receiptNote'.tr,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Obx(
            () => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: controller.busy.value
                      ? null
                      : () => controller.addDocument(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: Text('voucher.addReceiptCamera'.tr),
                ),
                OutlinedButton.icon(
                  onPressed: controller.busy.value
                      ? null
                      : () => controller.addDocument(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: Text('voucher.addReceiptGallery'.tr),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Every release of money against the voucher, with its acknowledgement.
///
/// Approved · paid so far · balance on top; beneath, one tile per payment
/// with who took the money, and whether their signed copy is on file.
class _Payments extends StatelessWidget {
  const _Payments({required this.voucher, required this.controller});

  final Voucher voucher;
  final VoucherDetailController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paid = voucher.payments.isEmpty
        ? voucher.amountPaid
        : voucher.payments.fold<double>(0, (sum, p) => sum + p.amount);
    final paidSoFar = voucher.amountPaid > 0 ? voucher.amountPaid : paid;

    Widget figure(String label, String value, {Color? colour}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: theme.textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(color: colour),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        const SizedBox(height: 8),
        Row(
          children: [
            figure('pay.approvedAmount'.tr, voucher.amountText),
            const SizedBox(width: 10),
            figure(
              'pay.paidSoFar'.tr,
              voucher.amountPaidText ?? Fmt.money(paidSoFar, voucher.currency),
            ),
            const SizedBox(width: 10),
            figure(
              'pay.balance'.tr,
              voucher.balanceText ??
                  Fmt.money(voucher.outstanding, voucher.currency),
              colour: voucher.outstanding > 0 ? VfColors.warn : VfColors.ok,
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (voucher.payments.isEmpty)
          Text('pay.noPayments'.tr, style: theme.textTheme.bodySmall)
        else
          ...voucher.payments.map(
            (p) => _PaymentTile(
              payment: p,
              voucher: voucher,
              controller: controller,
            ),
          ),
      ],
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({
    required this.payment,
    required this.voucher,
    required this.controller,
  });

  final VoucherPayment payment;
  final Voucher voucher;
  final VoucherDetailController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = payment;
    final reference = p.paymentReference ?? p.chequeNumber;

    final rows = <(String, String)>[
      ('pay.on'.tr, Fmt.date(p.paymentDate ?? p.paidAt)),
      (
        'voucher.method'.tr,
        [p.paymentMethod, reference].whereType<String>().join(' · '),
      ),
      if (p.receivedBy != null)
        (
          'pay.receivedBy'.tr,
          p.receiverIdNumber == null
              ? p.receivedBy!
              : '${p.receivedBy} (${'pay.idShort'.tr} ${p.receiverIdNumber})',
        ),
      if (p.paidBy != null) ('pay.by'.tr, p.paidBy!),
      ('pay.balanceAfter'.tr, p.balanceAfterText),
      if (p.note != null && p.note!.trim().isNotEmpty)
        ('voucher.comments'.tr, p.note!),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.vfElev1,
        border: Border.all(color: context.vfLine),
        borderRadius: BorderRadius.circular(VfTheme.rLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'pay.paymentN'.trParams({'n': '${p.sequence}'}) +
                          (p.reference.isEmpty ? '' : ' · ${p.reference}'),
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(p.amountText, style: theme.textTheme.titleLarge),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(
                label: p.isAcknowledged
                    ? 'pay.ackSigned'.tr
                    : 'pay.ackAwaiting'.tr,
                tag: p.isAcknowledged ? 'tag-accent' : 'tag-warn',
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 118,
                    child: Text(row.$1, style: theme.textTheme.bodySmall),
                  ),
                  Expanded(
                    child: Text(
                      row.$2.isEmpty ? '—' : row.$2,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (p.acknowledgedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'pay.ackFiledOn'.trParams({
                  'date': Fmt.dateTime(p.acknowledgedAt),
                }),
                style: theme.textTheme.bodySmall?.copyWith(color: VfColors.ok),
              ),
            ),
          const SizedBox(height: 10),
          Obx(
            () => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: controller.busy.value
                      ? null
                      : () => controller.printAcknowledgement(p),
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: Text('pay.printAck'.tr),
                ),
                if (controller.canFileAcknowledgement(p))
                  OutlinedButton.icon(
                    onPressed: controller.busy.value
                        ? null
                        : () => _pickAcknowledgementSource(controller, p),
                    icon: const Icon(Icons.upload_file_outlined, size: 18),
                    label: Text(
                      p.isAcknowledged
                          ? 'pay.ackReplace'.tr
                          : 'pay.ackUpload'.tr,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Camera or gallery for the signed copy.
Future<void> _pickAcknowledgementSource(
  VoucherDetailController controller,
  VoucherPayment payment,
) async {
  final source = await Get.bottomSheet<ImageSource>(
    SafeArea(
      child: Builder(
        builder: (context) => Container(
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  'pay.ackUpload'.tr,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                subtitle: Text('pay.ackUploadHint'.tr),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text('voucher.addReceiptCamera'.tr),
                onTap: () => Get.back(result: ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text('voucher.addReceiptGallery'.tr),
                onTap: () => Get.back(result: ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (source == null) return;
  await controller.uploadAcknowledgement(payment, source);
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.voucher});

  final Voucher voucher;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = Get.find<SessionService>().locale.value;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'voucher.timeline'.tr.toUpperCase(),
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 14),
          ...voucher.timeline.asMap().entries.map((entry) {
            final row = entry.value;
            final last = entry.key == voucher.timeline.length - 1;

            final colour = switch (row.state) {
              'rejected' => VfColors.bad,
              'done' => VfColors.accent500,
              'current' => VfColors.warn,
              _ => VfColors.lineStrong,
            };
            final icon = switch (row.state) {
              'rejected' => Icons.cancel_outlined,
              'done' => Icons.check_circle_outline,
              'current' => Icons.hourglass_top_outlined,
              _ => Icons.circle_outlined,
            };

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Icon(icon, size: 19, color: colour),
                      if (!last)
                        Expanded(
                          child: Container(width: 1, color: theme.dividerColor),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: last ? 0 : 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.step(locale).toUpperCase(),
                            style: theme.textTheme.labelSmall,
                          ),
                          Text(
                            row.label(locale),
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(row.person, style: theme.textTheme.bodyMedium),
                          Text(
                            row.when == null
                                ? row.action(locale)
                                : '${row.action(locale)} · ${Fmt.dateTime(row.when)}',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${'voucher.permitted'.tr}: ${row.capabilityText}',
                            style: theme.textTheme.bodySmall,
                          ),
                          if (decodeSignature(row.signature) != null) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: theme.dividerColor),
                              ),
                              child: Image.memory(
                                decodeSignature(row.signature)!,
                                height: 40,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          ],
                          if (row.comment != null) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.only(left: 10),
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: VfColors.accent500,
                                    width: 2,
                                  ),
                                ),
                              ),
                              child: Text(
                                row.comment!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          if (voucher.verificationCode != null) ...[
            const Divider(height: 24),
            Text(
              '${'voucher.verification'.tr}: ${voucher.verificationCode}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _Comments extends StatelessWidget {
  const _Comments({required this.controller, required this.voucher});

  final VoucherDetailController controller;
  final Voucher voucher;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('voucher.comments'.tr, style: theme.textTheme.titleMedium),
        const SizedBox(height: 10),
        ...voucher.comments.map(
          (comment) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: VfColors.accent700,
                  child: Text(
                    comment.authorInitials,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: VfColors.accentInk,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${comment.authorName} · ${Fmt.relative(comment.createdAt)}',
                        style: theme.textTheme.bodySmall,
                      ),
                      Text(comment.body, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller.commentField,
                decoration: InputDecoration(
                  hintText: 'voucher.addComment'.tr,
                  isDense: true,
                ),
                onSubmitted: (_) => controller.postComment(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: controller.postComment,
              icon: const Icon(Icons.send, size: 18),
            ),
          ],
        ),
      ],
    );
  }
}

/// The action bar mirrors the API's own permission flags — the app never
/// decides for itself what a step may do.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.controller, required this.voucher});

  final VoucherDetailController controller;
  final Voucher voucher;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = voucher.actions;
    final signOnly =
        (a.sign || a.submitSigned) &&
        !a.approve &&
        !voucher.currentStepCanApprove;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Signing and deciding are different acts: a sign-only step is
          // headed "Your signature" and says plainly who decides.
          if (signOnly || a.approve || a.reject)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (signOnly ? 'decision.signature' : 'decision.decision').tr
                        .toUpperCase(),
                    style: theme.textTheme.labelSmall,
                  ),
                  if (signOnly) ...[
                    const SizedBox(height: 4),
                    Text('sign.noApprove'.tr, style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          Row(
            children: [
              if (a.requestChanges)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        _reason(context, controller, isReject: false),
                    child: Text(
                      'act.requestChanges'.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              if (a.requestChanges && a.reject) const SizedBox(width: 8),
              if (a.reject)
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: VfColors.bad,
                      side: const BorderSide(color: VfColors.bad),
                    ),
                    onPressed: () =>
                        _reason(context, controller, isReject: true),
                    child: Text('act.reject'.tr),
                  ),
                ),
            ],
          ),
          if (a.requestChanges || a.reject) const SizedBox(height: 8),
          if (a.submit)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  final confirmed = await Get.dialog<bool>(
                    AlertDialog(
                      title: Text('voucher.submitConfirm'.tr),
                      content: Text('voucher.submitConfirmBody'.tr),
                      actions: [
                        TextButton(
                          onPressed: () => Get.back(result: false),
                          child: Text('action.cancel'.tr),
                        ),
                        FilledButton(
                          onPressed: () => Get.back(result: true),
                          child: Text('voucher.submit'.tr),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  await controller.run(
                    () => controller.repo.submit(voucher.id),
                    'msg.submitted'.tr,
                  );
                },
                icon: const Icon(Icons.send_outlined, size: 18),
                label: Text('voucher.submit'.tr),
              ),
            ),
          if (a.sign)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _sign(context, controller, approve: false),
                icon: const Icon(Icons.draw_outlined, size: 18),
                label: Text('act.sign'.tr),
              ),
            ),
          if (a.submitSigned)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => controller.run(
                  () => controller.repo.submitSigned(voucher.id),
                  'msg.forwarded'.tr,
                ),
                icon: const Icon(Icons.forward_outlined, size: 18),
                label: Text('act.submitSigned'.tr),
              ),
            ),
          if (a.approve)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _sign(context, controller, approve: true),
                icon: const Icon(Icons.verified_outlined, size: 18),
                label: Text('act.approve'.tr),
              ),
            ),
          if (a.pay) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _recordPayment(context, controller, voucher),
                icon: const Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 18,
                ),
                label: Text(
                  voucher.isPartiallyPaid
                      ? 'pay.payBalance'.tr
                      : voucher.isCash
                      ? 'pay.release'.tr
                      : 'pay.record'.tr,
                ),
              ),
            ),
            const SizedBox(height: 8),
            VfNote(
              voucher.isPartiallyPaid
                  ? 'pay.balanceShort'.trParams({
                      'amount':
                          voucher.balanceText ??
                          Fmt.money(voucher.outstanding, voucher.currency),
                    })
                  : 'pay.note'.tr,
            ),
          ],
        ],
      ),
    );
  }
}

/// Owns the lifetime of the controllers a sheet builds.
///
/// `Get.bottomSheet`'s future completes the moment the sheet is popped, while
/// its exit transition is still building — disposing controllers there throws
/// "used after being disposed" mid-animation. A State disposes only once the
/// route is genuinely gone.
class _SheetScope extends StatefulWidget {
  const _SheetScope({required this.onDispose, required this.child});

  final List<VoidCallback> onDispose;
  final Widget child;

  @override
  State<_SheetScope> createState() => _SheetScopeState();
}

class _SheetScopeState extends State<_SheetScope> {
  @override
  void dispose() {
    for (final release in widget.onDispose) {
      release();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Records a payment against an approved voucher — the whole balance, or
/// part of it now and the rest later.
///
/// This step never decides anything — the approval already happened. It
/// captures how much money left, how, and the reference it left under.
Future<void> _recordPayment(
  BuildContext context,
  VoucherDetailController controller,
  Voucher voucher,
) async {
  final outstanding = voucher.outstanding;
  final reference = TextEditingController();
  final receivedBy = TextEditingController();
  final receiverId = TextEditingController();
  final comment = TextEditingController();
  final amountField = TextEditingController(
    text: outstanding % 1 == 0
        ? Fmt.plain(outstanding)
        : outstanding.toStringAsFixed(2),
  );
  final method = (voucher.isCash ? 'Cash — office float' : 'Bank transfer').obs;
  final ready = false.obs;
  final amount = RxnDouble(outstanding);

  double? parseAmount() {
    final raw = amountField.text.replaceAll(RegExp(r'[,\s]'), '');
    return raw.isEmpty ? null : double.tryParse(raw);
  }

  String? amountError() {
    final value = amount.value;
    if (value == null || value <= 0) return 'pay.amountInvalid'.tr;
    if (value > outstanding + 0.001) {
      return 'pay.amountTooHigh'.trParams({
        'amount': Fmt.money(outstanding, voucher.currency),
      });
    }
    return null;
  }

  // A cash voucher has no transfer reference to quote; what it has is a person
  // who took the notes. Each format gates on the field it can actually supply,
  // and every payment on a sensible amount.
  void revalidate() {
    amount.value = parseAmount();
    ready.value =
        amountError() == null &&
        (voucher.isCash
            ? receivedBy.text.trim().isNotEmpty
            : reference.text.trim().isNotEmpty);
  }

  reference.addListener(revalidate);
  receivedBy.addListener(revalidate);
  amountField.addListener(revalidate);

  final methods = voucher.isCash
      ? const ['Cash — office float', 'Cash — branch float']
      : const ['Bank transfer', 'Cheque', 'Mobile money'];

  String? trimmed(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  await Get.bottomSheet<void>(
    isScrollControlled: true,
    _SheetScope(
      onDispose: [
        reference.dispose,
        receivedBy.dispose,
        receiverId.dispose,
        comment.dispose,
        amountField.dispose,
      ],
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 18,
            right: 18,
            top: 4,
            bottom: MediaQuery.of(context).viewInsets.bottom + 18,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  voucher.isPartiallyPaid
                      ? 'pay.payBalance'.tr
                      : voucher.isCash
                      ? 'pay.release'.tr
                      : 'pay.record'.tr,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 14),
                VfPanel(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${voucher.number} · ${voucher.payee}',
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              voucher.amountText,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            if (voucher.isPartiallyPaid) ...[
                              const SizedBox(height: 2),
                              Text(
                                [
                                  'pay.paidSoFarShort'.trParams({
                                    'amount':
                                        voucher.amountPaidText ??
                                        Fmt.money(
                                          voucher.amountPaid,
                                          voucher.currency,
                                        ),
                                  }),
                                  'pay.balanceShort'.trParams({
                                    'amount': Fmt.money(
                                      outstanding,
                                      voucher.currency,
                                    ),
                                  }),
                                ].join(' · '),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: VfColors.warn),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      KindChip(kind: voucher.kind, dense: false),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Obx(() {
                  final error = amountError();
                  final value = amount.value;
                  return TextField(
                    controller: amountField,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'pay.amountNow'.tr,
                      prefixText: '${voucher.currency} ',
                      errorText: amountField.text.isEmpty ? null : error,
                      helperText: error == null && value != null
                          ? 'pay.balanceAfterPayment'.trParams({
                              'amount': Fmt.money(
                                (outstanding - value).clamp(0, outstanding),
                                voucher.currency,
                              ),
                            })
                          : null,
                    ),
                  );
                }),
                const SizedBox(height: 12),
                Obx(
                  () => DropdownButtonFormField<String>(
                    initialValue: method.value,
                    decoration: InputDecoration(labelText: 'pay.from'.tr),
                    items: methods
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) => method.value = v ?? method.value,
                  ),
                ),
                const SizedBox(height: 12),
                if (voucher.isCash) ...[
                  TextField(
                    controller: receivedBy,
                    decoration: InputDecoration(
                      labelText: 'pay.receivedBy'.tr,
                      hintText: voucher.payee,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: receiverId,
                    decoration: InputDecoration(
                      labelText: 'pay.receiverId'.tr,
                      hintText: 'pay.optional'.tr,
                    ),
                  ),
                ] else
                  Obx(
                    () => TextField(
                      controller: reference,
                      decoration: InputDecoration(
                        // The label follows the METHOD, not the format: only a
                        // cheque has a cheque number.
                        labelText: method.value.toLowerCase().contains('cheque')
                            ? 'pay.cheque'.tr
                            : 'pay.reference'.tr,
                        hintText: method.value.toLowerCase().contains('cheque')
                            ? '004471'
                            : 'CRDB-TRX-8841207',
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: comment,
                  minLines: 2,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'voucher.addComment'.tr,
                  ),
                ),
                const SizedBox(height: 14),
                VfNote(voucher.isCash ? 'pay.ackNote'.tr : 'pay.note'.tr),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: Get.back,
                        child: Text('action.cancel'.tr),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Obx(
                        () => FilledButton(
                          onPressed: ready.value
                              ? () {
                                  final value = amount.value!;
                                  // The whole balance is the server's default;
                                  // only a part payment names its amount.
                                  final part = value < outstanding - 0.001;
                                  final args = (
                                    method: method.value,
                                    reference: trimmed(reference),
                                    receivedBy: trimmed(receivedBy),
                                    receiverId: trimmed(receiverId),
                                    comment: trimmed(comment),
                                  );
                                  Get.back();
                                  controller.pay(
                                    method: args.method,
                                    reference: args.reference,
                                    receivedBy: args.receivedBy,
                                    receiverIdNumber: args.receiverId,
                                    comment: args.comment,
                                    amount: part ? value : null,
                                  );
                                }
                              : null,
                          child: Text(
                            (amount.value ?? outstanding) < outstanding - 0.001
                                ? 'pay.payPart'.tr
                                : 'pay.markPaid'.tr,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Sign (and optionally approve) — the statement must be ticked before the
/// action is enabled, matching the web client and the design.
Future<void> _sign(
  BuildContext context,
  VoucherDetailController controller, {
  required bool approve,
}) async {
  final pad = SignaturePadController();
  final comment = TextEditingController();
  final statement = false.obs;
  final useSaved = (controller.savedSignature != null).obs;
  final saveForNext = true.obs;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _SheetScope(
      onDispose: [pad.dispose, comment.dispose],
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 4,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 18,
        ),
        child: SingleChildScrollView(
          child: Obx(() {
            final canAct =
                statement.value && (useSaved.value || pad.isNotEmpty);

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  approve ? 'act.approve'.tr : 'act.sign'.tr,
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  '${controller.voucher.value!.number} · ${controller.voucher.value!.amountText}',
                  style: Theme.of(sheetContext).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),

                if (decodeSignature(controller.savedSignature) != null)
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(value: true, label: Text('sign.saved'.tr)),
                      ButtonSegment(value: false, label: Text('sign.draw'.tr)),
                    ],
                    selected: {useSaved.value},
                    onSelectionChanged: (s) => useSaved.value = s.first,
                    showSelectedIcon: false,
                  ),
                const SizedBox(height: 12),

                if (useSaved.value && controller.savedSignature != null)
                  Container(
                    height: 110,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: VfColors.lineStrong),
                    ),
                    child: Image.memory(
                      decodeSignature(controller.savedSignature)!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  )
                else ...[
                  AnimatedBuilder(
                    animation: pad,
                    builder: (_, _) => SignaturePad(controller: pad),
                  ),
                  CheckboxListTile(
                    value: saveForNext.value,
                    onChanged: (v) => saveForNext.value = v ?? true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    title: Text(
                      'sign.saveForNext'.tr,
                      style: const TextStyle(fontSize: 13.5),
                    ),
                  ),
                ],

                const SizedBox(height: 8),
                TextField(
                  controller: comment,
                  maxLines: 2,
                  decoration: InputDecoration(labelText: 'sign.comment'.tr),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: statement.value,
                  onChanged: (v) => statement.value = v ?? false,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: Text(
                    approve ? 'sign.approveStatement'.tr : 'sign.statement'.tr,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                if (!approve) ...[
                  const SizedBox(height: 4),
                  Text(
                    'sign.noApprove'.tr,
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: !canAct
                      ? null
                      : () async {
                          // Capture everything the sheet owns, then close it, so no
                          // BuildContext is used after an await.
                          final navigator = Navigator.of(sheetContext);
                          final drawn = useSaved.value
                              ? null
                              : await pad.toPng();
                          navigator.pop();

                          final signature = drawn == null
                              ? null
                              : VoucherRepository.encodeSignature(drawn);
                          final id = controller.voucherId;
                          final text = comment.text.trim().isEmpty
                              ? null
                              : comment.text.trim();

                          if (approve) {
                            await controller.run(
                              () => controller.repo.approve(
                                id,
                                comment: text,
                                signature: signature,
                              ),
                              'msg.approved'.tr,
                            );
                          } else {
                            await controller.run(
                              () => controller.repo.sign(
                                id,
                                signature: signature,
                                comment: text,
                                save: saveForNext.value,
                              ),
                              'msg.signed'.tr,
                              'msg.signedBody'.tr,
                            );
                          }
                        },
                  child: Text(approve ? 'act.approve'.tr : 'act.sign'.tr),
                ),
              ],
            );
          }),
        ),
      ),
    ),
  );
}

/// Reject or request changes — both require a written reason for the record.
Future<void> _reason(
  BuildContext context,
  VoucherDetailController controller, {
  required bool isReject,
}) async {
  final reason = TextEditingController();

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _SheetScope(
      onDispose: [reason.dispose],
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 4,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isReject ? 'act.reject'.tr : 'act.requestChanges'.tr,
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              maxLines: 4,
              autofocus: true,
              decoration: InputDecoration(
                labelText: isReject
                    ? 'sign.rejectReason'.tr
                    : 'sign.changesNeeded'.tr,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              style: isReject
                  ? FilledButton.styleFrom(backgroundColor: VfColors.bad)
                  : null,
              onPressed: () {
                final text = reason.text.trim();
                if (text.length < 3) return;
                Navigator.of(sheetContext).pop();

                final id = controller.voucherId;
                if (isReject) {
                  controller.run(
                    () => controller.repo.reject(id, text),
                    'msg.rejected'.tr,
                  );
                } else {
                  controller.run(
                    () => controller.repo.requestChanges(id, text),
                    'msg.changes'.tr,
                  );
                }
              },
              child: Text(isReject ? 'act.reject'.tr : 'act.requestChanges'.tr),
            ),
          ],
        ),
      ),
    ),
  );
}
