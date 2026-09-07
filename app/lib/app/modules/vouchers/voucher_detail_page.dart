import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/session_service.dart';
import '../../data/services/voucher_repository.dart';
import '../../widgets/common.dart';
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
              const SizedBox(height: 20),
              _Details(voucher: v),
              const SizedBox(height: 22),
              _Timeline(voucher: v),
              const SizedBox(height: 22),
              _Comments(controller: controller, voucher: v),
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

class _Header extends StatelessWidget {
  const _Header({required this.voucher});

  final Voucher voucher;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The number is the record's identity — it gets the full width and never
        // wraps; the status sits beneath it with the rest of the meta line.
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
            StatusChip(label: voucher.statusLabel, tag: voucher.statusTag),
            Text(
              [
                voucher.voucherTypeLabel,
                voucher.departmentName,
                Fmt.date(voucher.voucherDate),
              ].whereType<String>().join(' · '),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(voucher.amountText, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 12),
        Text(voucher.purpose, style: theme.textTheme.titleLarge),
        if (voucher.description != null) ...[
          const SizedBox(height: 6),
          Text(voucher.description!, style: theme.textTheme.bodyLarge),
        ],
        if (voucher.amountInWords != null) ...[
          const SizedBox(height: 8),
          Text(
            voucher.amountInWords!,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.voucher});

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
                      file.isImage
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
      ],
    );
  }
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
                              decoration: const BoxDecoration(
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

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (a.sign && !voucher.currentStepCanApprove)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'sign.noApprove'.tr,
                style: theme.textTheme.bodySmall,
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
                onPressed: () => controller.run(
                  () => controller.repo.submit(voucher.id),
                  'msg.submitted'.tr,
                ),
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
                  voucher.isCash ? 'pay.release'.tr : 'pay.record'.tr,
                ),
              ),
            ),
            const SizedBox(height: 8),
            VfNote('pay.note'.tr),
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

/// Records a payment against an approved voucher.
///
/// This step never decides anything — the approval already happened. It
/// captures how the money left and the reference it left under.
Future<void> _recordPayment(
  BuildContext context,
  VoucherDetailController controller,
  Voucher voucher,
) async {
  final reference = TextEditingController();
  final comment = TextEditingController();
  final method = (voucher.isCash ? 'Cash — office float' : 'Bank transfer').obs;
  final ready = false.obs;

  reference.addListener(() => ready.value = reference.text.trim().isNotEmpty);

  final methods = voucher.isCash
      ? const ['Cash — office float', 'Cash — branch float']
      : const ['Bank transfer', 'Cheque', 'Mobile money'];

  await Get.bottomSheet<void>(
    isScrollControlled: true,
    _SheetScope(
      onDispose: [reference.dispose, comment.dispose],
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
                  voucher.isCash ? 'pay.release'.tr : 'pay.record'.tr,
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
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      KindChip(kind: voucher.kind, dense: false),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
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
                TextField(
                  controller: reference,
                  decoration: InputDecoration(
                    labelText: voucher.isCash
                        ? 'pay.reference'.tr
                        : 'pay.cheque'.tr,
                    hintText: voucher.isCash ? 'PC-REL-4471' : 'TRF-2026-4471',
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
                VfNote('pay.note'.tr),
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
                                  Get.back();
                                  controller.run(
                                    () => controller.repo.pay(
                                      voucher.id,
                                      reference: reference.text.trim(),
                                      method: method.value,
                                      comment: comment.text.trim().isEmpty
                                          ? null
                                          : comment.text.trim(),
                                    ),
                                    'pay.record'.tr,
                                    '${voucher.number} · ${voucher.amountText}',
                                  );
                                }
                              : null,
                          child: Text('pay.markPaid'.tr),
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
