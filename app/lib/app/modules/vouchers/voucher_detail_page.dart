import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/html_voucher_document.dart';
import '../../widgets/server_voucher_document.dart';
import '../../widgets/voucher_document.dart';
import '../../widgets/vf/vf.dart';
import 'detail_bits.dart';
import 'detail_controller.dart';
import 'detail_dialogs.dart';
import 'detail_sections.dart';
import 'edit_voucher_page.dart' show openEditVoucher;

export 'detail_controller.dart' show VoucherDetailController;

/// One voucher, as an app screen:
///
///   hero        number, status, purpose and the amount on a gradient card
///   actions     round print / PDF / share / edit / withdraw / delete buttons
///   progress    who prepared, signed, approved and paid — a timeline
///   sections    details, payments, attachments, comments, document, audit
///   bottom bar  this person's decision, always within reach
///
/// Nothing here is decided by role: every action comes from the workflow
/// engine's `actions`, and every consequential one goes through a sheet that
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

  @override
  void dispose() {
    Get.delete<VoucherDetailController>(tag: '$id');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final v = c.voucher.value;
      return VouchFlowPushedScaffold(
        title: dt('voucher'),
        body: _body(context, v),
        bottomBar: v == null ? null : DecisionBar(controller: c, voucher: v),
      );
    });
  }

  Widget _body(BuildContext context, Voucher? v) {
    if (c.loading.value && v == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(
          VfSize.pagePad,
          8,
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
              radius: VfSize.radiusXl,
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

    const gap = SizedBox(height: 24);
    return RefreshIndicator(
      onRefresh: c.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          VfSize.pagePad,
          8,
          VfSize.pagePad,
          32,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  VoucherHero(voucher: v),
                  QuickActions(controller: c, voucher: v),
                  const SizedBox(height: 8),
                  DetailPanel(
                    title: dt('approvalProgress'),
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                    child: v.timeline.isEmpty
                        ? MutedLine(
                            icon: PhosphorIconsRegular.hourglassMedium,
                            text: dt('notStarted'),
                          )
                        : ApprovalTrack(
                            rows: v.timeline,
                            youActHere: _hasDecision(v) && v.status != 'draft',
                          ),
                  ),
                  gap,
                  RequestDetailsPanel(voucher: v),
                  if (v.payments.isNotEmpty ||
                      v.status == 'approved' ||
                      v.status == 'paid') ...[
                    gap,
                    PaymentsPanel(controller: c, voucher: v),
                  ],
                  gap,
                  AttachmentsPanel(controller: c, voucher: v),
                  gap,
                  CommentsPanel(controller: c, voucher: v),
                  gap,
                  _DocumentPanel(controller: c, voucher: v),
                  const SizedBox(height: 12),
                  AuditTrail(voucher: v),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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

/* ─────────────────────────────────────────────────────────── the hero ── */

/// The voucher at a glance on a gradient card: number and status, the
/// purpose, and the amount large.
class VoucherHero extends StatelessWidget {
  const VoucherHero({super.key, required this.voucher});

  final Voucher voucher;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final v = voucher;
    const white = Colors.white;
    final soft = white.withValues(alpha: .78);
    const tabular = [FontFeature.tabularFigures()];

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [t.palette.hoverDark, t.palette.primaryLight],
        ),
        boxShadow: [
          BoxShadow(
            color: t.palette.primaryLight.withValues(
              alpha: t.isDark ? .28 : .34,
            ),
            blurRadius: 28,
            offset: const Offset(0, 12),
            spreadRadius: -10,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Two soft rings for depth.
          Positioned(right: -60, top: -70, child: _Ring(size: 200, alpha: .10)),
          Positioned(
            right: 30,
            bottom: -90,
            child: _Ring(size: 160, alpha: .07),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 18, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: white.withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        v.isCash
                            ? PhosphorIconsFill.money
                            : PhosphorIconsFill.bank,
                        size: 20,
                        color: white,
                        semanticLabel: v.isCash ? dt('cash') : dt('bank'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            v.number,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: VfType.bodyStrong.copyWith(
                              color: white,
                              height: 1.3,
                              fontFeatures: tabular,
                            ),
                          ),
                          Text(
                            v.voucherTypeLabel ??
                                (v.isCash ? dt('cash') : dt('bank')),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: VfType.meta.copyWith(color: soft),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _HeroStatus(voucher: v),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  v.purpose,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: VfType.cardTitle.copyWith(
                    color: soft,
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    v.amountText,
                    style: VfType.figure.copyWith(
                      fontSize: 32,
                      color: white,
                      fontFeatures: tabular,
                    ),
                  ),
                ),
                if ((v.amountInWords ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    v.amountInWords!,
                    style: VfType.meta.copyWith(color: soft),
                  ),
                ],
                if (v.isPartiallyPaid && v.balanceText != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 5, 12, 5),
                    decoration: BoxDecoration(
                      color: white.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(VfSize.radiusPill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          PhosphorIconsFill.hourglassMedium,
                          size: 14,
                          color: Color(0xFFFDE68A),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            dt('balanceAmount', {'amount': v.balanceText!}),
                            style: VfType.meta.copyWith(
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFFDE68A),
                              fontFeatures: tabular,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.size, required this.alpha});

  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: Colors.white.withValues(alpha: alpha),
        width: 26,
      ),
    ),
  );
}

/// The status on the hero: a frosted pill with a tone dot.
class _HeroStatus extends StatelessWidget {
  const _HeroStatus({required this.voucher});

  final Voucher voucher;

  @override
  Widget build(BuildContext context) {
    final dot = switch (statusTone(voucher.statusKey)) {
      VfTone.ok => const Color(0xFF4ADE80),
      VfTone.warn => const Color(0xFFFBBF24),
      VfTone.bad => const Color(0xFFF87171),
      VfTone.neutral => const Color(0xFFCBD5E1),
      _ => Colors.white,
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 5, 11, 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .18),
          borderRadius: BorderRadius.circular(VfSize.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                voucher.statusLabel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: VfType.meta.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ──────────────────────────────────────────────────── quick actions ── */

typedef _QuickAction = ({
  IconData icon,
  String label,
  VoidCallback? onTap,
  bool loading,
  bool danger,
});

/// Round buttons with one-word labels: whatever this person may do with the
/// document itself.
class QuickActions extends StatelessWidget {
  const QuickActions({
    super.key,
    required this.controller,
    required this.voucher,
  });

  final VoucherDetailController controller;
  final Voucher voucher;

  @override
  Widget build(BuildContext context) {
    final v = voucher;
    final a = v.actions;
    return Obx(() {
      final working = controller.working.value;
      final idle = working == null;
      final items = <_QuickAction>[
        if (a.print)
          (
            icon: PhosphorIconsRegular.printer,
            label: dt('print'),
            onTap: idle ? controller.printPdf : null,
            loading: working == 'print',
            danger: false,
          ),
        if (a.download) ...[
          (
            icon: PhosphorIconsRegular.filePdf,
            label: 'PDF',
            onTap: idle ? controller.sharePdf : null,
            loading: working == 'pdf',
            danger: false,
          ),
          (
            icon: PhosphorIconsRegular.shareNetwork,
            label: dt('share'),
            onTap: controller.shareLink,
            loading: false,
            danger: false,
          ),
        ],
        if (a.edit)
          (
            icon: PhosphorIconsRegular.pencilSimple,
            label: dt('edit'),
            onTap: () async {
              if (await openEditVoucher(v.id)) await controller.load();
            },
            loading: false,
            danger: false,
          ),
        if (a.cancel)
          (
            icon: PhosphorIconsRegular.prohibit,
            label: dt('withdraw'),
            onTap: () => showCommentActionDialog(
              context,
              controller,
              CommentAction.cancel,
            ),
            loading: false,
            danger: true,
          ),
        if (a.delete)
          (
            icon: PhosphorIconsRegular.trash,
            label: dt('delete'),
            onTap: () async {
              final gone = await showDeleteDialog(context, controller);
              if (gone && context.mounted) {
                Navigator.of(context).maybePop(true);
              }
            },
            loading: false,
            danger: true,
          ),
      ];
      if (items.isEmpty) return const SizedBox(height: 16);
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 12),
        child: Row(
          mainAxisAlignment: items.length < 4
              ? MainAxisAlignment.spaceEvenly
              : MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in items) Flexible(child: _RoundAction(item: item)),
          ],
        ),
      );
    });
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.item});

  final _QuickAction item;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final fg = item.danger ? t.dangerStrong : t.primaryText;
    final bg = item.danger ? t.dangerSoft : t.primarySoft;
    return Semantics(
      button: true,
      label: item.label,
      excludeSemantics: true,
      child: SizedBox(
        width: 68,
        child: Column(
          children: [
            Material(
              color: bg,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: item.loading ? null : item.onTap,
                child: SizedBox(
                  width: 54,
                  height: 54,
                  child: Center(
                    child: item.loading
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: fg,
                            ),
                          )
                        : Icon(item.icon, size: 22, color: fg),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: VfType.meta.copyWith(
                fontWeight: FontWeight.w500,
                color: item.danger ? t.dangerStrong : t.text2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ─────────────────────────────────────────────────────── decision bar ── */

/// What this person may decide now — straight from `voucher.actions` — as a
/// sticky bar of full-width buttons at the bottom of the screen.
class DecisionBar extends StatelessWidget {
  const DecisionBar({
    super.key,
    required this.controller,
    required this.voucher,
  });

  final VoucherDetailController controller;
  final Voucher voucher;

  @override
  Widget build(BuildContext context) {
    final v = voucher;
    final a = v.actions;
    final primary = primaryDecision(v);
    final secondary = <(String, IconData, VfButtonVariant, VoidCallback)>[
      // A step that both signs and approves offers signing as its own act.
      if (a.sign && primary?.icon != PhosphorIconsRegular.signature)
        (
          dt('signShort'),
          PhosphorIconsRegular.signature,
          VfButtonVariant.secondary,
          () => showSignDialog(context, controller),
        ),
      if (a.requestChanges)
        (
          dt('changesShort'),
          PhosphorIconsRegular.arrowUUpLeft,
          VfButtonVariant.secondary,
          () => showReasonDialog(context, controller, reject: false),
        ),
      if (a.reject)
        (
          dt('reject'),
          PhosphorIconsRegular.x,
          VfButtonVariant.danger,
          () => showReasonDialog(context, controller, reject: true),
        ),
    ];
    if (primary == null && secondary.isEmpty) return const SizedBox.shrink();

    final t = context.vf;
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: t.isDark ? Border(top: BorderSide(color: t.border)) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: t.isDark ? .4 : .08),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (secondary.isNotEmpty)
                Row(
                  children: [
                    for (var i = 0; i < secondary.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: VouchFlowButton(
                          label: secondary[i].$1,
                          icon: secondary.length < 3 ? secondary[i].$2 : null,
                          variant: secondary[i].$3,
                          height: 46,
                          expand: true,
                          onPressed: secondary[i].$4,
                        ),
                      ),
                    ],
                  ],
                ),
              if (secondary.isNotEmpty && primary != null)
                const SizedBox(height: 10),
              if (primary != null)
                VouchFlowButton(
                  label: primary.label,
                  icon: primary.icon,
                  expand: true,
                  height: 52,
                  onPressed: () => primary.open(context, controller),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ────────────────────────────────────────────────────── the document ── */

/// The printed voucher, in the company's template — folded away until asked
/// for. The server's own PDF, rasterised; the native sheet stands in while it
/// loads, offline, or where the step may not print.
class _DocumentPanel extends StatelessWidget {
  const _DocumentPanel({required this.controller, required this.voucher});

  final VoucherDetailController controller;
  final Voucher voucher;

  @override
  Widget build(BuildContext context) {
    final v = voucher;
    return DetailDisclosure(
      title: dt('voucherDocument'),
      icon: PhosphorIconsRegular.fileText,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: HtmlVoucherDocument(
          title: v.number,
          load: () => controller.repo.documentHtml(v.id),
          refreshKey: [
            v.status,
            v.updatedAt?.toIso8601String(),
            v.timeline.length,
            v.attachments.length,
            v.payments.length,
            v.amountPaid,
            currentLocale,
          ].join('|'),
          // Without the HTML: the printed PDF, then the drawn copy.
          fallback: ServerVoucherDocument(
            title: v.number,
            load: () => controller.repo.pdf(v.id),
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
                company: controller.session.company.value,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
