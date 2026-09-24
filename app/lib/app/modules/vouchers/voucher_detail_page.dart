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
import '../../widgets/design.dart';
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

  /// Runs one workflow transition. True when the API accepted it.
  Future<bool> run(
    Future<Voucher> Function() action,
    String title, [
    String? body,
  ]) async {
    busy.value = true;
    try {
      voucher.value = await action();
      showToast(title, body: body);
      await session.refreshUnread();
      return true;
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
    return false;
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
        leadingWidth: 60,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: IconButton.outlined(
              tooltip: 'action.back'.tr,
              style: IconButton.styleFrom(
                side: BorderSide(color: context.vfLine),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(VfTheme.rMd),
                ),
              ),
              onPressed: Get.back,
              icon: const Icon(Icons.chevron_left, size: 22),
            ),
          ),
        ),
        title: Obx(
          () => Mono(
            controller.voucher.value?.number ?? '',
            size: 13,
            colour: context.vfInk2,
          ),
        ),
        actions: [
          Obx(() {
            final v = controller.voucher.value;
            if (v == null || !(v.actions.print || v.actions.download)) {
              return const SizedBox(width: 12);
            }
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: PopupMenuButton<String>(
                tooltip: 'detail.more'.tr,
                icon: const Icon(Icons.more_horiz),
                onSelected: (value) => value == 'print'
                    ? controller.printPdf()
                    : controller.sharePdf(),
                itemBuilder: (_) => [
                  if (v.actions.print)
                    PopupMenuItem(
                      value: 'print',
                      child: _MenuRow(Icons.print_outlined, 'act.print'.tr),
                    ),
                  if (v.actions.download)
                    PopupMenuItem(
                      value: 'share',
                      child: _MenuRow(Icons.ios_share, 'act.sharePdf'.tr),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
      body: Obx(() {
        if (controller.loading.value && controller.voucher.value == null) {
          return const SkeletonList(count: 3);
        }
        if (controller.error.value != null) {
          return ErrorState(
            message: controller.error.value!,
            onRetry: controller.load,
          );
        }

        final v = controller.voucher.value!;
        final locale = Get.find<SessionService>().locale.value;
        final current = v.timeline.firstWhereOrNull(
          (t) => t.state == 'current',
        );
        final next = _nextStep(v);

        return RefreshIndicator(
          onRefresh: controller.load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: StatusBadge(voucher: v),
              ),
              const SizedBox(height: 12),
              AmountText(amount: v.amount, currency: v.currency, size: 30),
              const SizedBox(height: 6),
              Text(v.purpose, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 16),

              // After signing: the mark that was applied, and what happens next.
              if (v.actions.submitSigned &&
                  decodeSignature(current?.signature) != null) ...[
                _SignedCard(entry: current!),
                const SizedBox(height: 10),
              ],

              InfoRows(
                rows: [
                  (
                    'detail.payTo'.tr,
                    InfoRows.value(context, v.payee),
                  ),
                  if (v.requesterName != null)
                    (
                      'detail.requestedBy'.tr,
                      InfoRows.value(context, v.requesterName!),
                    ),
                  if (v.departmentName != null)
                    (
                      'voucher.department'.tr,
                      InfoRows.value(context, v.departmentName!),
                    ),
                  (
                    'voucher.method'.tr,
                    InfoRows.value(
                      context,
                      [
                        (v.paymentMethod ?? '').isNotEmpty
                            ? v.paymentMethod
                            : (v.isCash
                                  ? 'voucher.cashShort'.tr
                                  : 'voucher.bankShort'.tr),
                        v.payeeBank,
                      ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                    ),
                  ),
                  if (v.accountRef != null && v.accountRef!.isNotEmpty)
                    (
                      'voucher.reference'.tr,
                      Mono(v.accountRef!, size: 12.5, colour: context.vfInk),
                    ),
                  if (v.voucherTypeLabel != null)
                    (
                      'voucher.type'.tr,
                      InfoRows.value(context, v.voucherTypeLabel!),
                    ),
                  ('voucher.date'.tr, InfoRows.value(context, Fmt.date(v.voucherDate))),
                  if (v.category != null)
                    (
                      'voucher.category'.tr,
                      InfoRows.value(context, v.category!),
                    ),
                  if (v.costCentre != null)
                    (
                      'voucher.costCentre'.tr,
                      InfoRows.value(context, v.costCentre!),
                    ),
                  if (v.actions.submitSigned && next != null)
                    (
                      'detail.next'.tr,
                      InfoRows.value(
                        context,
                        [
                          next.person,
                          next.personTitle,
                        ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                      ),
                    ),
                  if (v.paymentReference != null)
                    (
                      'pay.reference'.tr,
                      Mono(v.paymentReference!, size: 12.5, colour: context.vfInk),
                    ),
                  if (v.receivedBy != null)
                    ('pay.receivedBy'.tr, InfoRows.value(context, v.receivedBy!)),
                  if (v.paidAt != null)
                    ('pay.on'.tr, InfoRows.value(context, Fmt.dateTime(v.paidAt))),
                  if (v.paidBy != null)
                    ('pay.by'.tr, InfoRows.value(context, v.paidBy!)),
                ],
              ),

              if (v.actions.submitSigned) ...[
                const SizedBox(height: 10),
                NoticeBanner(
                  icon: Icons.check_circle_outline,
                  tone: VfTone.ok,
                  title: 'sign.readyTitle'.tr,
                  body: 'msg.signedBody'.tr,
                ),
              ],

              if ((v.description ?? '').isNotEmpty ||
                  (v.notesToApprover ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((v.description ?? '').isNotEmpty) ...[
                        Text(
                          'voucher.description'.tr,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          v.description!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                      if ((v.description ?? '').isNotEmpty &&
                          (v.notesToApprover ?? '').isNotEmpty)
                        const SizedBox(height: 12),
                      if ((v.notesToApprover ?? '').isNotEmpty) ...[
                        Text(
                          'voucher.notes'.tr,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          v.notesToApprover!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              if (v.attachments.isNotEmpty) ...[
                const SizedBox(height: 10),
                _Attachments(voucher: v),
              ],

              const SizedBox(height: 22),
              SectionLabel('voucher.timeline'.tr),
              _Timeline(voucher: v, locale: locale),

              const SizedBox(height: 22),
              SectionLabel(
                'voucher.comments'.tr,
                trailing: v.comments.isEmpty
                    ? null
                    : Text(
                        '${v.comments.length}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
              ),
              _Comments(controller: controller, voucher: v),

              const SizedBox(height: 22),
              /* The printed sheet stays one tap away: what is on screen above
                 is the summary, this is exactly what prints. */
              Disclosure(
                title: 'doc.title'.tr,
                icon: Icons.description_outlined,
                child: DocumentFrame(
                  child: VoucherDocument(
                    voucher: v,
                    company: Get.find<SessionService>().company.value,
                  ),
                ),
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

/// The step after the one in progress, read from the API's own timeline.
TimelineEntry? _nextStep(Voucher v) {
  final at = v.timeline.indexWhere((t) => t.state == 'current');
  if (at == -1 || at + 1 >= v.timeline.length) return null;
  // The closing "Completed" row is not a step anyone submits to.
  if (at + 1 == v.timeline.length - 1) return null;
  return v.timeline[at + 1];
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: context.vfInk2),
      const SizedBox(width: 10),
      Text(label),
    ],
  );
}

class _SignedCard extends StatelessWidget {
  const _SignedCard({required this.entry});

  final TimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _SignatureImage(dataUrl: entry.signature, width: 96, height: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('sign.byYou'.tr, style: theme.textTheme.titleSmall),
                Text(
                  Fmt.dateTime(entry.when),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A signature on paper: the stored PNG on an off-white card.
class _SignatureImage extends StatelessWidget {
  const _SignatureImage({
    required this.dataUrl,
    this.width,
    this.height = 44,
  });

  final String? dataUrl;
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final bytes = decodeSignature(dataUrl);
    if (bytes == null) return const SizedBox.shrink();
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: SignaturePad.paper,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Image.memory(
        bytes,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}

class _Attachments extends StatelessWidget {
  const _Attachments({required this.voucher});

  final Voucher voucher;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < voucher.attachments.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : Border(top: BorderSide(color: context.vfLine)),
              ),
              child: Row(
                children: [
                  IconTile(
                    icon: voucher.attachments[i].isImage
                        ? Icons.image_outlined
                        : Icons.picture_as_pdf_outlined,
                    tone: voucher.attachments[i].isImage
                        ? VfTone.info
                        : VfTone.brand,
                    size: 34,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          voucher.attachments[i].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          voucher.attachments[i].size,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
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

/// The approval trail: each step with who, what and when, drawn as a
/// vertical rail.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.voucher, required this.locale});

  final Voucher voucher;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...voucher.timeline.asMap().entries.map((entry) {
            final row = entry.value;
            final last = entry.key == voucher.timeline.length - 1;

            final (tone, icon) = switch (row.state) {
              'rejected' => (VfTone.bad, Icons.close_rounded),
              'done' => (VfTone.ok, Icons.check_rounded),
              'current' => (VfTone.brand, Icons.hourglass_top_rounded),
              _ => (VfTone.neutral, Icons.more_horiz),
            };
            final colour = tone.colour(context);
            final pending = row.state == 'pending';

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: pending ? Colors.transparent : tone.soft(context),
                          border: Border.all(
                            color: pending
                                ? context.vfLineStrong
                                : colour.withValues(alpha: .6),
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          icon,
                          size: 13,
                          color: pending ? context.vfMuted : colour,
                        ),
                      ),
                      if (!last)
                        Expanded(
                          child: Container(
                            width: 1.5,
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            color: row.state == 'done'
                                ? context.vfOk.withValues(alpha: .45)
                                : context.vfLine,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: last ? 0 : 18, top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${row.person} · ${row.action(locale)}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: row.state == 'current'
                                  ? context.vfAccent
                                  : pending
                                  ? context.vfInk2
                                  : null,
                            ),
                          ),
                          Text(
                            [
                              row.label(locale),
                              if (row.when != null) Fmt.dateTime(row.when),
                            ].join(' · '),
                            style: theme.textTheme.bodySmall,
                          ),
                          if (row.capabilityText.isNotEmpty)
                            Text(
                              '${'voucher.permitted'.tr}: ${row.capabilityText}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: context.vfFaint,
                                fontSize: 11.5,
                              ),
                            ),
                          if (decodeSignature(row.signature) != null) ...[
                            const SizedBox(height: 6),
                            _SignatureImage(
                              dataUrl: row.signature,
                              width: 110,
                              height: 40,
                            ),
                          ],
                          if (row.comment != null) ...[
                            const SizedBox(height: 6),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: context.vfElev2,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '“${row.comment!}”',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: context.vfInk2,
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
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Divider(color: context.vfLine),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  '${'voucher.verification'.tr}  ',
                  style: theme.textTheme.bodySmall,
                ),
                Mono(voucher.verificationCode!, size: 12, colour: context.vfInk2),
              ],
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
        ...voucher.comments.map(
          (comment) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InitialsAvatar(initials: comment.authorInitials, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${comment.authorName} · ${Fmt.relative(comment.createdAt)}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 2),
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
              tooltip: 'action.send'.tr,
              style: IconButton.styleFrom(
                backgroundColor: VfColors.accent500,
                foregroundColor: VfColors.onAccent,
                minimumSize: const Size(46, 46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(VfTheme.rMd),
                ),
              ),
              onPressed: controller.postComment,
              icon: const Icon(Icons.send_rounded, size: 18),
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
    final locale = Get.find<SessionService>().locale.value;
    final next = _nextStep(voucher);

    // Request changes lives inside the reject and sign sheets when either is
    // offered; on its own it gets a button of its own.
    final changesAlone = a.requestChanges && !a.reject && !a.sign;

    Widget full(Widget child) => SizedBox(width: double.infinity, child: child);

    return Obx(() {
      final busy = controller.busy.value;
      return StickyActions(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (a.sign && !voucher.currentStepCanApprove)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'sign.noApprove'.tr,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ),

            if (a.reject || a.approve)
              Row(
                children: [
                  if (a.reject)
                    Expanded(
                      child: OutlinedButton.icon(
                        style: VfButtons.destructiveOutline(context),
                        onPressed: busy
                            ? null
                            : () => _reason(context, controller, isReject: true),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: Text('act.reject'.tr),
                      ),
                    ),
                  if (a.reject && a.approve) const SizedBox(width: 10),
                  if (a.approve)
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: busy
                            ? null
                            : () => _sign(context, controller, approve: true),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: Text(
                          'act.approveShort'.tr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
              ),

            if (a.sign) ...[
              if (a.reject || a.approve) const SizedBox(height: 10),
              full(
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () => _sign(context, controller, approve: false),
                  icon: const Icon(Icons.draw_outlined, size: 18),
                  label: Text('act.sign'.tr),
                ),
              ),
            ],

            if (a.submitSigned) ...[
              if (a.sign || a.reject || a.approve) const SizedBox(height: 10),
              full(
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () => controller.run(
                          () => controller.repo.submitSigned(voucher.id),
                          'msg.forwarded'.tr,
                        ),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: Text(
                    next == null
                        ? 'act.submitSigned'.tr
                        : 'act.submitTo'.trParams({
                            'step': next.label(locale),
                          }),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],

            if (changesAlone) ...[
              if (a.submitSigned || a.approve) const SizedBox(height: 10),
              full(
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => _reason(context, controller, isReject: false),
                  icon: const Icon(Icons.u_turn_left, size: 18),
                  label: Text('act.requestChanges'.tr),
                ),
              ),
            ],

            if (a.submit)
              full(
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () => controller.run(
                          () => controller.repo.submit(voucher.id),
                          'msg.submitted'.tr,
                        ),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: Text('voucher.submit'.tr),
                ),
              ),

            if (a.pay)
              full(
                FilledButton.icon(
                  style: VfButtons.success(),
                  onPressed: busy
                      ? null
                      : () => _recordPayment(context, controller, voucher),
                  icon: const Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 18,
                  ),
                  label: Text(
                    voucher.isCash ? 'pay.release'.tr : 'pay.record'.tr,
                  ),
                ),
              ),
          ],
        ),
      );
    });
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
  final receivedBy = TextEditingController();
  final comment = TextEditingController();
  final method = (voucher.isCash ? 'Cash — office float' : 'Bank transfer').obs;
  final ready = false.obs;

  // A cash voucher has no transfer reference to quote; what it has is a person
  // who took the notes. Each format gates on the field it can actually supply.
  void revalidate() => ready.value = voucher.isCash
      ? receivedBy.text.trim().isNotEmpty
      : reference.text.trim().isNotEmpty;

  reference.addListener(revalidate);
  receivedBy.addListener(revalidate);

  final methods = voucher.isCash
      ? const ['Cash — office float', 'Cash — branch float']
      : const ['Bank transfer', 'Cheque', 'Mobile money'];

  Future<bool>? payment;
  // The action bar this was opened from is gone once the voucher is paid;
  // the navigator outlives it, so the confirmation is shown from there.
  final host = Navigator.of(context).context;

  await showVfSheet<void>(
    context,
    builder: (sheetContext) => _SheetScope(
      onDispose: [reference.dispose, receivedBy.dispose, comment.dispose],
      child: SheetScaffold(
        eyebrow: Mono(voucher.number, size: 11.5),
        title: 'pay.payTo'.trParams({'payee': voucher.payee}),
        trailing: KindTag(kind: voucher.kind),
        children: [
          SectionCard(
            colour: sheetContext.vfElev1,
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
            child: Column(
              children: [
                Center(
                  child: AmountText(
                    amount: voucher.amount,
                    currency: voucher.currency,
                    size: 28,
                  ),
                ),
                if ((voucher.amountInWords ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    voucher.amountInWords!,
                    textAlign: TextAlign.center,
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          FieldLabel('pay.from'.tr),
          Obx(
            () => DropdownButtonFormField<String>(
              initialValue: method.value,
              isExpanded: true,
              items: methods
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) => method.value = v ?? method.value,
            ),
          ),
          const SizedBox(height: 14),
          if (voucher.isCash) ...[
            FieldLabel('pay.receivedBy'.tr, required: true),
            TextField(
              controller: receivedBy,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: voucher.payee,
                helperText: 'pay.receivedByHint'.tr,
              ),
            ),
          ] else
            Obx(() {
              // The label follows the METHOD, not the format: only a cheque
              // has a cheque number.
              final cheque = method.value.toLowerCase().contains('cheque');
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FieldLabel(
                    cheque ? 'pay.cheque'.tr : 'pay.reference'.tr,
                    required: true,
                  ),
                  TextField(
                    controller: reference,
                    style: Mono.style(
                      sheetContext,
                      size: 14,
                      colour: sheetContext.vfInk,
                    ),
                    decoration: InputDecoration(
                      hintText: cheque ? '004471' : 'CRDB-TRX-8841207',
                    ),
                  ),
                ],
              );
            }),
          const SizedBox(height: 14),
          FieldLabel('pay.comment'.tr),
          TextField(
            controller: comment,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(hintText: 'voucher.addComment'.tr),
          ),
          const SizedBox(height: 12),
          Text(
            'pay.note'.tr,
            style: Theme.of(sheetContext).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Obx(
            () => FilledButton.icon(
              style: VfButtons.success(),
              onPressed: ready.value
                  ? () {
                      Navigator.of(sheetContext).pop();
                      payment = controller.run(
                        () => controller.repo.pay(
                          voucher.id,
                          isCash: voucher.isCash,
                          method: method.value,
                          reference: reference.text.trim(),
                          receivedBy: receivedBy.text.trim(),
                          comment: comment.text.trim().isEmpty
                              ? null
                              : comment.text.trim(),
                        ),
                        'pay.record'.tr,
                        '${voucher.number} · ${voucher.amountText}',
                      );
                    }
                  : null,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(
                'pay.markAmountPaid'.trParams({'amount': voucher.amountText}),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: Text('action.cancel'.tr),
          ),
        ],
      ),
    ),
  );

  // The sheet closes before the API answers; wait for it.
  final paid = await (payment ?? Future.value(false));
  final after = controller.voucher.value;
  if (paid && after != null && after.status == 'paid' && host.mounted) {
    Get.closeAllSnackbars();
    await _paidConfirmation(host, controller, after);
  }
}

/// The receipt moment: what was paid, to whom, and the PDF to send on.
Future<void> _paidConfirmation(
  BuildContext context,
  VoucherDetailController controller,
  Voucher voucher,
) => showVfSheet<void>(
  context,
  builder: (sheetContext) {
    final theme = Theme.of(sheetContext);
    return SheetScaffold(
      title: '',
      children: [
        const Center(
          child: IconTile(icon: Icons.check_rounded, tone: VfTone.ok, size: 56),
        ),
        const SizedBox(height: 14),
        Text(
          'pay.paidTitle'.tr,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          [
            '${voucher.amountText} → ${voucher.payee}',
            if ((voucher.receivedBy ?? '').isNotEmpty)
              '${'pay.receivedBy'.tr}: ${voucher.receivedBy}',
          ].join('\n'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: sheetContext.vfInk2,
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Mono(
            [
              voucher.number,
              voucher.paymentReference,
              voucher.verificationCode,
            ].whereType<String>().where((s) => s.isNotEmpty).join('  ·  '),
            size: 11.5,
          ),
        ),
        const SizedBox(height: 22),
        if (voucher.actions.download) ...[
          OutlinedButton.icon(
            onPressed: controller.sharePdf,
            icon: const Icon(Icons.ios_share, size: 18),
            label: Text('act.sharePdf'.tr),
          ),
          const SizedBox(height: 10),
        ],
        FilledButton(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: Text('action.done'.tr),
        ),
      ],
    );
  },
);

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
  final voucher = controller.voucher.value!;
  var switchToChanges = false;

  await showVfSheet<void>(
    context,
    builder: (sheetContext) => _SheetScope(
      onDispose: [pad.dispose, comment.dispose],
      child: Obx(() {
        final canAct = statement.value && (useSaved.value || pad.isNotEmpty);
        final hasSaved = decodeSignature(controller.savedSignature) != null;

        return SheetScaffold(
          title: approve ? 'act.approve'.tr : 'act.sign'.tr,
          subtitle: approve
              ? '${voucher.number} · ${voucher.amountText}'
              : 'sign.noApprove'.tr,
          trailing: hasSaved
              ? VfSegmented<bool>(
                  compact: true,
                  value: useSaved.value,
                  options: [
                    (false, 'sign.draw'.tr, null),
                    (true, 'sign.savedShort'.tr, null),
                  ],
                  onChanged: (v) => useSaved.value = v,
                )
              : null,
          children: [
            if (useSaved.value && hasSaved)
              Container(
                height: 150,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: SignaturePad.paper,
                  borderRadius: BorderRadius.circular(VfTheme.rMd),
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
                builder: (_, _) => SignaturePad(controller: pad, height: 150),
              ),
              const SizedBox(height: 4),
              _CheckRow(
                value: saveForNext.value,
                onChanged: (v) => saveForNext.value = v,
                label: 'sign.saveAsMine'.tr,
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: comment,
              minLines: 1,
              maxLines: 2,
              decoration: InputDecoration(hintText: 'sign.comment'.tr),
            ),
            const SizedBox(height: 6),
            _CheckRow(
              value: statement.value,
              onChanged: (v) => statement.value = v,
              label: approve
                  ? 'sign.approveStatement'.tr
                  : 'sign.statement'.tr,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: !canAct
                  ? null
                  : () async {
                      // Capture everything the sheet owns, then close it, so
                      // no BuildContext is used after an await.
                      final navigator = Navigator.of(sheetContext);
                      final drawn = useSaved.value ? null : await pad.toPng();
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
              icon: Icon(
                approve ? Icons.check_rounded : Icons.draw_outlined,
                size: 18,
              ),
              label: Text(approve ? 'act.approve'.tr : 'act.sign'.tr),
            ),
            if (voucher.actions.requestChanges) ...[
              const SizedBox(height: 4),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: sheetContext.vfInk2,
                ),
                onPressed: () {
                  switchToChanges = true;
                  Navigator.of(sheetContext).pop();
                },
                child: Text('act.requestChangesInstead'.tr),
              ),
            ],
          ],
        );
      }),
    ),
  );

  if (switchToChanges && context.mounted) {
    await _reason(context, controller, isReject: false);
  }
}

/// Reject or request changes — both require a written reason for the record.
Future<void> _reason(
  BuildContext context,
  VoucherDetailController controller, {
  required bool isReject,
}) async {
  final reason = TextEditingController();
  final showError = false.obs;
  final voucher = controller.voucher.value!;
  var switchToChanges = false;

  await showVfSheet<void>(
    context,
    builder: (sheetContext) => _SheetScope(
      onDispose: [reason.dispose],
      child: SheetScaffold(
        title: isReject ? 'reject.title'.tr : 'act.requestChanges'.tr,
        subtitle: (voucher.requesterName ?? '').isEmpty
            ? null
            : (isReject ? 'reject.sub' : 'changes.sub').trParams({
                'name': voucher.requesterName!,
              }),
        children: [
          FieldLabel(
            isReject ? 'sign.rejectReason'.tr : 'sign.changesNeeded'.tr,
            required: true,
          ),
          Obx(
            () => TextField(
              controller: reason,
              minLines: 3,
              maxLines: 5,
              autofocus: true,
              onChanged: (_) {
                if (showError.value && reason.text.trim().length >= 3) {
                  showError.value = false;
                }
              },
              decoration: InputDecoration(
                errorText: showError.value ? 'sign.reasonRequired'.tr : null,
              ),
            ),
          ),
          if (isReject && voucher.actions.requestChanges)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () {
                  switchToChanges = true;
                  Navigator.of(sheetContext).pop();
                },
                child: Text('act.requestChangesInstead'.tr),
              ),
            ),
          const SizedBox(height: 10),
          FilledButton(
            style: isReject ? VfButtons.destructive() : null,
            onPressed: () {
              final text = reason.text.trim();
              if (text.length < 3) {
                showError.value = true;
                return;
              }
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
            child: Text(
              isReject ? 'reject.confirm'.tr : 'act.requestChanges'.tr,
            ),
          ),
        ],
      ),
    ),
  );

  if (switchToChanges && context.mounted) {
    await _reason(context, controller, isReject: false);
  }
}

/// A checkbox with its label, the whole row tappable.
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onChanged(!value),
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            height: 24,
            child: Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.vfInk2,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
