import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/server_voucher_document.dart';
import '../../widgets/stamps.dart';
import '../../widgets/voucher_document.dart';
import '../../widgets/vf/vf.dart';
import 'detail_bits.dart';
import 'detail_controller.dart';
import 'detail_dialogs.dart';
import 'detail_sections.dart';
import 'edit_voucher_page.dart' show openEditVoucher;

export 'detail_controller.dart' show VoucherDetailController;

/// One voucher, arranged around the decision in front of the reader — the
/// web's voucher page on a phone:
///
///   header      what it is, what it costs, where it stands, print/PDF/share
///   decision    what this person may do now — straight from `voucher.actions`
///   progress    who prepared, signed, approved and paid, and when
///   details     the request, payments, attachments and discussion
///   document    the voucher as the server prints it, in the company template
///
/// Nothing here is decided by role: every action comes from the workflow
/// engine's `actions`, and every consequential one goes through a dialog that
/// restates the voucher and amount.
class VoucherDetailPage extends StatefulWidget {
  const VoucherDetailPage({super.key});

  @override
  State<VoucherDetailPage> createState() => _VoucherDetailPageState();
}

class _VoucherDetailPageState extends State<VoucherDetailPage> {
  late final int id = Get.arguments as int;
  late final VoucherDetailController c = Get.put(
    VoucherDetailController(id),
    tag: '$id',
  );

  final _decisionKey = GlobalKey();
  final _decisionHidden = false.obs;

  @override
  void dispose() {
    Get.delete<VoucherDetailController>(tag: '$id');
    super.dispose();
  }

  /// The sticky action bar only earns its place once the decision panel has
  /// scrolled away — showing both at once is the same button twice.
  bool _onScroll(ScrollNotification n) {
    final box = _decisionKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) {
      _decisionHidden.value = false;
      return false;
    }
    final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
    final top = MediaQuery.paddingOf(context).top + VfSize.topBarH;
    _decisionHidden.value = bottom < top;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final v = c.voucher.value;
      return VouchFlowPushedScaffold(
        title: v?.number ?? dt('voucher'),
        body: _body(context, v),
        bottomBar: v == null ? null : _stickyBar(context, v),
      );
    });
  }

  Widget _body(BuildContext context, Voucher? v) {
    if (c.loading.value && v == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(
          VfSize.pagePad,
          16,
          VfSize.pagePad,
          32,
        ),
        children: const [VouchFlowLoadingState(rows: 3, rowHeight: 180)],
      );
    }
    if (v == null) {
      return ListView(
        padding: const EdgeInsets.all(VfSize.pagePad),
        children: [
          if (c.forbidden.value)
            VouchFlowCard(
              child: VouchFlowEmptyState(
                icon: PhosphorIconsRegular.lockKey,
                title: dt('notAuthorised'),
                body: c.error.value,
                actionLabel: dt('register'),
                onAction: () => Navigator.of(context).maybePop(),
              ),
            )
          else
            VouchFlowErrorState(
              message: c.error.value ?? 'state.error'.tr,
              onRetry: c.load,
              retryLabel: 'action.retry'.tr,
            ),
        ],
      );
    }

    final wide = MediaQuery.sizeOf(context).width >= 760;
    final aside = [
      KeyedSubtree(
        key: _decisionKey,
        child: DecisionPanel(controller: c, voucher: v),
      ),
      const SizedBox(height: 16),
      DetailPanel(
        title: dt('approvalProgress'),
        child: v.timeline.isEmpty
            ? Text(
                dt('notStarted'),
                style: VfType.small.copyWith(color: context.vf.muted),
              )
            : ApprovalTrack(
                rows: v.timeline,
                youActHere: _hasDecision(v) && v.status != 'draft',
              ),
      ),
    ];
    final main = [
      RequestDetailsPanel(voucher: v),
      if (v.payments.isNotEmpty ||
          v.status == 'approved' ||
          v.status == 'paid') ...[
        const SizedBox(height: 16),
        PaymentsPanel(controller: c, voucher: v),
      ],
      const SizedBox(height: 16),
      AttachmentsPanel(controller: c, voucher: v),
      const SizedBox(height: 16),
      CommentsPanel(controller: c, voucher: v),
      const SizedBox(height: 16),
      _DocumentPanel(controller: c, voucher: v),
      const SizedBox(height: 16),
      AuditTrail(voucher: v),
    ];

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: RefreshIndicator(
        onRefresh: c.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            VfSize.pagePad,
            16,
            VfSize.pagePad,
            40,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DocumentHeader(controller: c, voucher: v),
                    const SizedBox(height: 16),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: main,
                            ),
                          ),
                          const SizedBox(width: 16),
                          SizedBox(
                            width: 330,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: aside,
                            ),
                          ),
                        ],
                      )
                    else ...[
                      ...aside,
                      const SizedBox(height: 16),
                      ...main,
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _stickyBar(BuildContext context, Voucher v) {
    final primary = primaryDecision(v);
    if (primary == null) return null;
    return Obx(() {
      if (!_decisionHidden.value) return const SizedBox.shrink();
      final t = context.vf;
      return Container(
        decoration: BoxDecoration(
          color: t.surface,
          border: Border(top: BorderSide(color: t.border)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 16,
              offset: Offset(0, -6),
              spreadRadius: -10,
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                if (v.actions.reject) ...[
                  Tooltip(
                    message: dt('reject'),
                    child: Material(
                      color: t.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(VfSize.radiusL),
                        side: BorderSide(
                          color: Color.lerp(
                            t.dangerStrong,
                            t.borderStrong,
                            .55,
                          )!,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => showReasonDialog(context, c, reject: true),
                        child: SizedBox(
                          width: VfSize.controlH,
                          height: VfSize.controlH,
                          child: Icon(
                            PhosphorIconsRegular.x,
                            size: 18,
                            color: t.dangerStrong,
                            semanticLabel: dt('reject'),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: VouchFlowButton(
                    label: primary.label,
                    icon: primary.icon,
                    expand: true,
                    onPressed: () => primary.open(context, c),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

bool _hasDecision(Voucher v) {
  final a = v.actions;
  return a.submit ||
      a.sign ||
      a.submitSigned ||
      a.approve ||
      a.reject ||
      a.requestChanges ||
      a.pay;
}

/// The one thing this person is asked to do, first among the actions.
({
  String label,
  IconData icon,
  Future<void> Function(BuildContext, VoucherDetailController) open,
})?
primaryDecision(Voucher v) {
  final a = v.actions;
  if (a.pay) {
    return (
      label: v.isPartiallyPaid
          ? dt('payRemainingBalance')
          : (v.isCash ? dt('releaseFunds') : dt('recordPayment')),
      icon: PhosphorIconsRegular.wallet,
      open: showPayDialog,
    );
  }
  if (a.approve) {
    return (
      label: dt('approveVoucher'),
      icon: PhosphorIconsRegular.sealCheck,
      open: showApproveDialog,
    );
  }
  if (a.sign) {
    return (
      label: dt('signVoucher'),
      icon: PhosphorIconsRegular.signature,
      open: showSignDialog,
    );
  }
  if (a.submitSigned) {
    return (
      label: dt('submitSigned'),
      icon: PhosphorIconsRegular.paperPlaneTilt,
      open: (ctx, c) =>
          showCommentActionDialog(ctx, c, CommentAction.submitSigned),
    );
  }
  if (a.submit) {
    return (
      label: dt('submitApproval'),
      icon: PhosphorIconsRegular.paperPlaneTilt,
      open: (ctx, c) => showCommentActionDialog(ctx, c, CommentAction.submit),
    );
  }
  return null;
}

/* ───────────────────────────────────────────────────────── the header ── */

/// The document's identity, its figure, and what can be done with it.
class DocumentHeader extends StatelessWidget {
  const DocumentHeader({
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
    final a = v.actions;
    final facts = <(String, String)>[
      (dt('payee'), v.payee),
      (dt('requestedBy'), v.requesterName ?? '—'),
      (dt('department'), v.departmentName ?? '—'),
      (dt('date'), Fmt.date(v.voucherDate)),
      (dt('paymentMethod'), v.paymentMethod ?? '—'),
    ];

    Widget fact((String, String) f) => Padding(
      padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            f.$1,
            style: VfType.meta.copyWith(fontSize: 12.5, color: t.muted),
          ),
          const SizedBox(height: 2),
          Text(
            f.$2,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: VfType.body.copyWith(
              fontWeight: FontWeight.w500,
              color: t.text,
            ),
          ),
        ],
      ),
    );

    final rows = <Widget>[];
    for (var i = 0; i < facts.length; i += 2) {
      rows.add(
        Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: t.border)),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: fact(facts[i])),
                if (i + 1 < facts.length) ...[
                  VerticalDivider(width: 1, thickness: 1, color: t.border),
                  Expanded(child: fact(facts[i + 1])),
                ] else
                  const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      );
    }

    return VouchFlowCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      v.number,
                      style: VfType.small.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: t.text2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                        border: Border(left: BorderSide(color: t.border)),
                      ),
                      child: Text(
                        v.voucherTypeLabel ?? dt('voucher'),
                        style: VfType.meta.copyWith(
                          fontSize: 13,
                          color: t.muted,
                        ),
                      ),
                    ),
                    VoucherKindTag(isCash: v.isCash),
                    VoucherStatusBadge(voucher: v),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  v.purpose,
                  style: VfType.sectionTitle.copyWith(
                    color: t.text,
                    fontSize: 19,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  dt('amount').toUpperCase(),
                  style: VfType.eyebrow.copyWith(fontSize: 12, color: t.muted),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    v.amountText,
                    style: VfType.figure.copyWith(
                      fontSize: 26,
                      color: t.text,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if ((v.amountInWords ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    v.amountInWords!,
                    style: VfType.meta.copyWith(fontSize: 13, color: t.muted),
                  ),
                ],
                if (v.isPartiallyPaid && v.balanceText != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    dt('balanceAmount', {'amount': v.balanceText!}),
                    style: VfType.meta.copyWith(
                      fontWeight: FontWeight.w600,
                      color: t.warning,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ...rows,
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.border)),
            ),
            child: Obx(() {
              final working = controller.working.value;
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (a.print)
                    VouchFlowButton(
                      label: dt('print'),
                      icon: PhosphorIconsRegular.printer,
                      variant: VfButtonVariant.secondary,
                      compact: true,
                      loading: working == 'print',
                      onPressed: working != null ? null : controller.printPdf,
                    ),
                  if (a.download) ...[
                    VouchFlowButton(
                      label: 'PDF',
                      icon: PhosphorIconsRegular.downloadSimple,
                      variant: VfButtonVariant.secondary,
                      compact: true,
                      loading: working == 'pdf',
                      onPressed: working != null ? null : controller.sharePdf,
                    ),
                    VouchFlowIconButton(
                      icon: PhosphorIconsRegular.shareNetwork,
                      tooltip: dt('share'),
                      size: 40,
                      onPressed: controller.shareLink,
                    ),
                  ],
                  if (a.edit)
                    VouchFlowButton(
                      label: dt('edit'),
                      icon: PhosphorIconsRegular.pencilSimple,
                      variant: VfButtonVariant.secondary,
                      compact: true,
                      onPressed: () async {
                        if (await openEditVoucher(v.id)) await controller.load();
                      },
                    ),
                  if (a.cancel)
                    _DangerLink(
                      icon: PhosphorIconsRegular.prohibit,
                      label: dt('cancelVoucher'),
                      onTap: () => showCommentActionDialog(
                        context,
                        controller,
                        CommentAction.cancel,
                      ),
                    ),
                  if (a.delete)
                    _DangerLink(
                      icon: PhosphorIconsRegular.trash,
                      label: dt('delete'),
                      onTap: () async {
                        final gone = await showDeleteDialog(
                          context,
                          controller,
                        );
                        if (gone && context.mounted) {
                          Navigator.of(context).maybePop(true);
                        }
                      },
                    ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _DangerLink extends StatelessWidget {
  const _DangerLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: t.dangerStrong,
        minimumSize: const Size(44, 40),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VfSize.radiusL),
        ),
      ),
      icon: Icon(icon, size: 15),
      label: Text(label, style: VfType.label.copyWith(color: t.dangerStrong)),
    );
  }
}

/* ─────────────────────────────────────────────────────── the decision ── */

/// What this person may do now — or, with nothing to do, where it stands.
class DecisionPanel extends StatelessWidget {
  const DecisionPanel({
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
    final a = v.actions;
    final primary = primaryDecision(v);

    if (!_hasDecision(v)) {
      final paid = v.status == 'paid';
      return VouchFlowCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: paid ? t.successSoft : t.surface3,
                borderRadius: BorderRadius.circular(VfSize.radiusM),
              ),
              child: Icon(
                paid
                    ? PhosphorIconsRegular.checkCircle
                    : v.isTerminal
                    ? PhosphorIconsRegular.archive
                    : PhosphorIconsRegular.hourglassMedium,
                size: 20,
                color: paid ? t.success : t.text2,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    v.isTerminal ? v.statusLabel : dt('noAction'),
                    style: VfType.cardTitle.copyWith(color: t.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    v.isTerminal ? dt('historyInReports') : v.statusLabel,
                    style: VfType.small.copyWith(color: t.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // A signing-only step: the holder signs (and may send back), never decides.
    final signOnly =
        (a.sign || a.submitSigned) &&
        !a.approve &&
        v.currentStepName != null &&
        !v.currentStepCanApprove;

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(VfSize.radiusL),
        border: Border.all(color: t.border),
        boxShadow: t.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: t.primary, width: 3)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: t.primarySoft,
                    borderRadius: BorderRadius.circular(VfSize.radiusM),
                  ),
                  child: Icon(
                    primary?.icon ?? PhosphorIconsRegular.handPointing,
                    size: 20,
                    color: t.primaryText,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      VouchFlowEyebrow(
                        signOnly ? dt('yourSignature') : dt('yourDecision'),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        v.currentStepName ?? v.statusLabel,
                        style: VfType.cardTitle.copyWith(
                          color: t.text,
                          fontSize: 17,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (a.submitSigned) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: t.surface2,
                  border: Border.all(color: t.border),
                  borderRadius: BorderRadius.circular(VfSize.radiusM),
                ),
                child: Row(
                  children: [
                    const Stamp(kind: StampKind.signed, scale: .8, tilt: -.05),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        dt('signedByYou'),
                        style: VfType.small.copyWith(color: t.text2),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (primary != null)
              VouchFlowButton(
                label: primary.label,
                icon: primary.icon,
                expand: true,
                height: 48,
                onPressed: () => primary.open(context, controller),
              ),
            // A step that both signs and approves offers signing as its own act.
            if (a.sign && primary?.icon != PhosphorIconsRegular.signature) ...[
              const SizedBox(height: 8),
              VouchFlowButton(
                label: dt('signVoucher'),
                icon: PhosphorIconsRegular.signature,
                variant: VfButtonVariant.secondary,
                expand: true,
                onPressed: () => showSignDialog(context, controller),
              ),
            ],
            if (a.requestChanges || a.reject) ...[
              const SizedBox(height: 8),
              DialogActions(
                reverseWhenStacked: false,
                children: [
                  if (a.requestChanges)
                    VouchFlowButton(
                      label: dt('requestChanges'),
                      icon: PhosphorIconsRegular.arrowUUpLeft,
                      variant: VfButtonVariant.secondary,
                      expand: true,
                      onPressed: () => showReasonDialog(context, controller, reject: false),
                    ),
                  if (a.reject)
                    VouchFlowButton(
                      label: dt('reject'),
                      icon: PhosphorIconsRegular.x,
                      variant: VfButtonVariant.danger,
                      expand: true,
                      onPressed: () => showReasonDialog(context, controller, reject: true),
                    ),
                ],
              ),
            ],
            if (signOnly) ...[
              const SizedBox(height: 12),
              Text(
                dt('signOnlyNote'),
                style: VfType.small.copyWith(fontSize: 13, color: t.muted),
              ),
            ],
            if (a.pay) ...[
              const SizedBox(height: 12),
              Text(
                v.isPartiallyPaid && v.balanceText != null
                    ? dt('balanceAmount', {'amount': v.balanceText!})
                    : dt('payNote'),
                style: VfType.small.copyWith(
                  fontSize: 13,
                  color: v.isPartiallyPaid ? t.warning : t.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/* ────────────────────────────────────────────────────── the document ── */

/// The printed voucher, in the company's template — folded away until asked
/// for, as on the web. The server's own PDF, rasterised; the native sheet
/// stands in while it loads, offline, or where the step may not print.
class _DocumentPanel extends StatefulWidget {
  const _DocumentPanel({required this.controller, required this.voucher});

  final VoucherDetailController controller;
  final Voucher voucher;

  @override
  State<_DocumentPanel> createState() => _DocumentPanelState();
}

class _DocumentPanelState extends State<_DocumentPanel> {
  bool open = false;
  bool opened = false;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final v = widget.voucher;
    return VouchFlowCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: open,
            child: InkWell(
              onTap: () => setState(() {
                open = !open;
                opened = true;
              }),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
                  child: Row(
                    children: [
                      Icon(
                        PhosphorIconsRegular.fileText,
                        size: 18,
                        color: t.text2,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          dt('voucherDocument'),
                          style: VfType.cardTitle.copyWith(color: t.text),
                        ),
                      ),
                      Text(
                        open ? dt('hideDocument') : dt('showDocument'),
                        style: VfType.meta.copyWith(color: t.muted),
                      ),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: open ? .5 : 0,
                        duration: const Duration(milliseconds: 160),
                        child: Icon(
                          PhosphorIconsRegular.caretDown,
                          size: 16,
                          color: t.text2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (opened)
            Offstage(
              offstage: !open,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: ServerVoucherDocument(
                  title: v.number,
                  load: () => widget.controller.repo.pdf(v.id),
                  refreshKey: [
                    v.status,
                    v.updatedAt?.toIso8601String(),
                    v.timeline.length,
                    v.attachments.length,
                    v.payments.length,
                    v.amountPaid,
                    currentLocale,
                  ].join('|'),
                  fallback: DocumentFrame(
                    child: VoucherDocument(
                      voucher: v,
                      company: widget.controller.session.company.value,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
