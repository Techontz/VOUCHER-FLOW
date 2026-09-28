import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/detail_models.dart';
import '../../data/models/models.dart';
import '../../data/services/session_service.dart';
import '../../data/services/voucher_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/vf/vf.dart';

/// A `detail.` string, with `@name` parameters filled in.
String dt(String key, [Map<String, String>? params]) =>
    params == null ? 'detail.$key'.tr : 'detail.$key'.trParams(params);

String get currentLocale => Get.isRegistered<SessionService>()
    ? Get.find<SessionService>().locale.value
    : 'en';

const _tabular = [FontFeature.tabularFigures()];

/* ─────────────────────────────────────────────────────────── status ── */

/// The web's five status tones, keyed on the backend's status_key.
VfTone statusTone(String key) => switch (key) {
  'paid' || 'awaiting_payment' => VfTone.ok,
  'changes_requested' || 'partially_paid' => VfTone.warn,
  'rejected' => VfTone.bad,
  'draft' || 'cancelled' => VfTone.neutral,
  _ => VfTone.info,
};

/// The status as the web's `.badge tone-*`.
class VoucherStatusBadge extends StatelessWidget {
  const VoucherStatusBadge({
    super.key,
    required this.voucher,
    this.large = false,
  });

  final Voucher voucher;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = statusTone(voucher.statusKey).colors(context.vf);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 12 : 10,
        vertical: large ? 4 : 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(VfSize.radiusPill),
      ),
      child: Text(
        voucher.statusLabel,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: VfType.meta.copyWith(
          fontSize: large ? 13 : 12.5,
          fontWeight: FontWeight.w500,
          color: fg,
        ),
      ),
    );
  }
}

/// Bank or cash — the web's `.vf-kind`.
class VoucherKindTag extends StatelessWidget {
  const VoucherKindTag({super.key, required this.isCash});

  final bool isCash;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: t.surface3,
        borderRadius: BorderRadius.circular(VfSize.radiusXs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isCash ? PhosphorIconsRegular.money : PhosphorIconsRegular.bank,
            size: 14,
            color: t.text,
          ),
          const SizedBox(width: 5),
          Text(
            isCash ? dt('cash') : dt('bank'),
            style: VfType.meta.copyWith(
              color: t.text,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// A count pill beside a panel title (the web's `.vf-count`).
class CountPill extends StatelessWidget {
  const CountPill(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: t.surface3,
        borderRadius: BorderRadius.circular(VfSize.radiusPill),
      ),
      child: Text(
        '$count',
        style: VfType.meta.copyWith(
          color: t.text2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A panel with the web's head (title, optional count and action) and body.
class DetailPanel extends StatelessWidget {
  const DetailPanel({
    super.key,
    required this.title,
    required this.child,
    this.count,
    this.action,
    this.padding = const EdgeInsets.all(16),
  });

  final String title;
  final int? count;
  final Widget? action;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return VouchFlowCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: VfType.sectionTitle.copyWith(
                            color: t.text,
                            fontSize: 17,
                          ),
                        ),
                      ),
                      if ((count ?? 0) > 0) ...[
                        const SizedBox(width: 8),
                        CountPill(count!),
                      ],
                    ],
                  ),
                ),
                if (action != null) ...[const SizedBox(width: 8), action!],
              ],
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// A muted line with a leading icon (the web's `.app-muted-line`).
class MutedLine extends StatelessWidget {
  const MutedLine({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: t.muted),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: VfType.small.copyWith(color: t.muted)),
        ),
      ],
    );
  }
}

/// A label/value row, label left and value right-aligned — the web's `.vf-dl-row`.
class DlRow extends StatelessWidget {
  const DlRow({
    super.key,
    required this.label,
    required this.value,
    this.mono = false,
    this.strong = false,
    this.valueColor,
  });

  final String label;
  final String? value;
  final bool mono, strong;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final v = value;
    if (v == null || v.trim().isEmpty) return const SizedBox.shrink();
    final t = context.vf;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 42,
            child: Text(label, style: VfType.small.copyWith(color: t.muted)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 58,
            child: Text(
              v,
              style: (strong ? VfType.bodyStrong : VfType.body).copyWith(
                fontSize: 14.5,
                color: valueColor ?? t.text,
                fontFeatures: mono ? _tabular : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* ───────────────────────────────────────────────────────── the stage ── */

const _roleNames = {
  'hod': ['HOD', 'Mkuu wa Idara'],
  'ceo': ['CEO', 'Mkurugenzi Mtendaji'],
  'manager': ['Manager', 'Meneja'],
  'director': ['Director', 'Mkurugenzi'],
  'finance': ['Finance', 'Idara ya Fedha'],
  'cashier': ['Cashier', 'Mhasibu'],
};

/// Where the voucher is now, or how it ended, in one plain phrase — the web's
/// `voucherStage`.
String voucherStage(Voucher v) {
  final sw = currentLocale == 'sw';
  final step = v.currentStepName;
  final role = step == null
      ? ''
      : (_roleNames[v.currentStepRole]?[sw ? 1 : 0] ?? step);
  switch (v.statusKey) {
    case 'draft':
      return dt('draftNotSubmitted');
    case 'awaiting_signature':
      return step != null ? dt('stageWithSign', {'role': role}) : v.statusLabel;
    case 'signed_pending_submit':
      return dt('signedNotSubmitted');
    case 'awaiting_approval':
      return step != null
          ? dt('stageWithApproval', {'role': role})
          : v.statusLabel;
    case 'awaiting_review':
      return step != null ? dt('stageWith', {'step': step}) : v.statusLabel;
    case 'awaiting_payment':
      return dt('awaitingPayment');
    case 'partially_paid':
      return v.balanceText != null
          ? dt('stagePartlyPaid', {'amount': v.balanceText!})
          : v.statusLabel;
    case 'paid':
      final on = v.paymentDate ?? v.paidAt;
      return on != null
          ? dt('stagePaidOn', {'date': Fmt.date(on)})
          : dt('paidAct');
    case 'rejected':
      return v.decidedBy != null
          ? dt('stageRejectedBy', {'name': v.decidedBy!})
          : dt('rejected');
    case 'changes_requested':
      return v.decidedBy != null
          ? dt('stageReturnedBy', {'name': v.decidedBy!})
          : dt('stageReturned');
    case 'cancelled':
      return dt('stageCancelled');
    default:
      return v.statusLabel;
  }
}

/// The one call to action a list row offers — always leading to the voucher.
({String label, IconData icon, bool strong})? primaryAction(Voucher v) {
  final a = v.actions;
  if (a.pay) {
    return (
      label: dt('recordPayment'),
      icon: PhosphorIconsRegular.wallet,
      strong: true,
    );
  }
  if (a.approve) {
    return (
      label: dt('reviewApprove'),
      icon: PhosphorIconsRegular.sealCheck,
      strong: true,
    );
  }
  if (a.sign) {
    return (
      label: dt('reviewSign'),
      icon: PhosphorIconsRegular.signature,
      strong: true,
    );
  }
  if (a.submitSigned) {
    return (
      label: dt('submitSigned'),
      icon: PhosphorIconsRegular.paperPlaneTilt,
      strong: true,
    );
  }
  if (a.edit && v.status == 'changes_requested') {
    return (
      label: dt('reviseVoucher'),
      icon: PhosphorIconsRegular.pencilSimple,
      strong: true,
    );
  }
  if (a.edit) {
    return (
      label: dt('continueDraft'),
      icon: PhosphorIconsRegular.pencilSimple,
      strong: false,
    );
  }
  return null;
}

/* ─────────────────────────────────────────────────────── the progress ── */

enum RouteStepState { done, current, pending, rejected }

typedef ProgressStep = ({String key, String label, RouteStepState state});

/// The company's workflows, fetched once per company and shared by every list.
class WorkflowCache {
  WorkflowCache._();

  static final Map<int, List<WorkflowInfo>> _cache = {};
  static final Map<int, Future<List<WorkflowInfo>>> _inflight = {};

  static List<WorkflowInfo>? peek() {
    final id = _companyId();
    return id == null ? null : _cache[id];
  }

  static int? _companyId() => Get.isRegistered<SessionService>()
      ? Get.find<SessionService>().company.value?.id
      : null;

  /// Never throws: progress is an enhancement on a list.
  static Future<List<WorkflowInfo>> load() {
    final id = _companyId();
    if (id == null) return Future.value(const []);
    final cached = _cache[id];
    if (cached != null) return Future.value(cached);
    return _inflight[id] ??= Get.find<VoucherRepository>()
        .workflows()
        .then((w) => _cache[id] = w)
        .catchError((_) => <WorkflowInfo>[])
        .whenComplete(() => _inflight.remove(id));
  }
}

/// The web's `deriveProgress`: the voucher's route, from its workflow.
List<ProgressStep> deriveProgress(Voucher v, List<WorkflowInfo>? workflows) {
  final workflow = workflows?.firstWhereOrNull((w) => w.id == v.workflowId);
  if (workflow == null || workflow.steps.isEmpty) return const [];
  final locale = currentLocale;

  final steps = [...workflow.steps]
    ..sort((a, b) => a.position.compareTo(b.position));
  final applicable = steps
      .where((s) => s.isRequestStep || s.appliesTo(v.amount))
      .toList();
  final approvals = applicable.where(
    (s) => !s.isRequestStep && !s.isPaymentStep,
  );
  final payment = applicable.firstWhereOrNull((s) => s.isPaymentStep);
  final status = v.status;
  final at = v.currentStepPosition;

  final result = <ProgressStep>[
    (
      key: 'prepared',
      label: dt('prepared'),
      state: status == 'draft' ? RouteStepState.current : RouteStepState.done,
    ),
  ];
  final approvalSteps = <ProgressStep>[];
  for (final step in approvals) {
    var state = RouteStepState.pending;
    if (status == 'approved' || status == 'paid') {
      state = RouteStepState.done;
    } else if ((status == 'in_review' || status == 'rejected') && at != null) {
      state = step.position < at
          ? RouteStepState.done
          : step.position == at
          ? (status == 'rejected'
                ? RouteStepState.rejected
                : RouteStepState.current)
          : RouteStepState.pending;
    }
    approvalSteps.add((
      key: 'step-${step.position}',
      label: step.label(locale),
      state: state,
    ));
  }
  if (status == 'rejected' &&
      !approvalSteps.any((s) => s.state == RouteStepState.rejected) &&
      approvalSteps.isNotEmpty) {
    final i = approvalSteps.lastIndexWhere(
      (s) => s.state != RouteStepState.done,
    );
    final idx = i == -1 ? approvalSteps.length - 1 : i;
    final s = approvalSteps[idx];
    approvalSteps[idx] = (
      key: s.key,
      label: s.label,
      state: RouteStepState.rejected,
    );
  }
  result.addAll(approvalSteps);
  if (payment != null) {
    result.add((
      key: 'payment',
      label: payment.label(locale),
      state: status == 'paid'
          ? RouteStepState.done
          : status == 'approved'
          ? RouteStepState.current
          : RouteStepState.pending,
    ));
  }
  return result;
}

/// ✓ Prepared — ✓ HOD — ● MD — ○ Finance, wrapping on a phone.
class ProgressStepsLine extends StatelessWidget {
  const ProgressStepsLine({super.key, required this.steps});

  final List<ProgressStep> steps;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final children = <Widget>[];
    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      final mark = switch (s.state) {
        RouteStepState.done => Container(
          width: 17,
          height: 17,
          decoration: BoxDecoration(
            color: t.successStrong,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            PhosphorIconsBold.check,
            size: 10,
            color: Colors.white,
          ),
        ),
        RouteStepState.rejected => Container(
          width: 17,
          height: 17,
          decoration: BoxDecoration(
            color: t.dangerStrong,
            shape: BoxShape.circle,
          ),
          child: const Icon(PhosphorIconsBold.x, size: 10, color: Colors.white),
        ),
        RouteStepState.current => Container(
          width: 17,
          height: 17,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.surface,
            shape: BoxShape.circle,
            border: Border.all(color: t.primary, width: 1.5),
          ),
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: t.primary, shape: BoxShape.circle),
          ),
        ),
        RouteStepState.pending => Container(
          width: 17,
          height: 17,
          decoration: BoxDecoration(
            color: t.surface,
            shape: BoxShape.circle,
            border: Border.all(color: t.borderStrong, width: 1.5),
          ),
        ),
      };
      children.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (i > 0) ...[
              Container(width: 12, height: 1, color: t.borderStrong),
              const SizedBox(width: 6),
            ],
            mark,
            const SizedBox(width: 6),
            Text(
              s.label,
              style: VfType.meta.copyWith(
                fontSize: 13,
                color: switch (s.state) {
                  RouteStepState.current => t.text,
                  RouteStepState.done => t.text2,
                  _ => t.muted,
                },
                fontWeight: s.state == RouteStepState.current
                    ? FontWeight.w500
                    : FontWeight.w400,
              ),
            ),
          ],
        ),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}

/* ──────────────────────────────────────────────────── approval track ── */

/// The full approval ladder from the backend's own timeline: who prepared,
/// signed, approved and paid — and when. The web's `ApprovalTrack`, with each
/// step's recorded signature beneath it.
class ApprovalTrack extends StatelessWidget {
  const ApprovalTrack({super.key, required this.rows, this.youActHere = false});

  final List<TimelineEntry> rows;
  final bool youActHere;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final locale = currentLocale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++)
          _row(context, t, locale, rows[i], i == rows.length - 1),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    VfTokens t,
    String locale,
    TimelineEntry row,
    bool last,
  ) {
    final state = row.state;
    final when = row.when == null ? null : Fmt.dateTime(row.when);
    final act = row.action(locale);
    final String whenLine;
    if (state == 'done' || state == 'rejected') {
      whenLine = [if (act.isNotEmpty && act != 'null') act, ?when].join(' · ');
    } else if (state == 'current') {
      whenLine = youActHere
          ? (row.act == 'Awaiting signature'
                ? dt('waitingForYourSignature')
                : row.act.startsWith('Signed')
                ? act
                : dt('waitingForYou'))
          : (act.isNotEmpty && act != 'null' ? act : dt('inProgress'));
    } else {
      whenLine = dt('notStarted');
    }
    final showPerson =
        row.person.isNotEmpty &&
        row.person != '—' &&
        row.person != 'VouchFlow' &&
        row.person != 'null';
    final signature = decodeSignature(row.signature);

    final Widget mark = switch (state) {
      'done' => Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(color: t.successSoft, shape: BoxShape.circle),
        child: Icon(PhosphorIconsBold.check, size: 14, color: t.successStrong),
      ),
      'rejected' => Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(color: t.dangerSoft, shape: BoxShape.circle),
        child: Icon(PhosphorIconsBold.x, size: 14, color: t.dangerStrong),
      ),
      'current' => Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.surface,
          shape: BoxShape.circle,
          border: Border.all(color: t.primary, width: 1.5),
          boxShadow: [BoxShadow(color: t.primarySoft, spreadRadius: 4)],
        ),
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: t.primary, shape: BoxShape.circle),
        ),
      ),
      _ => Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: t.surface,
          shape: BoxShape.circle,
          border: Border.all(color: t.borderStrong, width: 1.5),
        ),
      ),
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                mark,
                if (!last)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      margin: const EdgeInsets.only(top: 2),
                      color: state == 'done'
                          ? t.successStrong.withValues(alpha: .5)
                          : t.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 20, top: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.label(locale),
                    style: VfType.bodyStrong.copyWith(
                      color: state == 'pending' ? t.muted : t.text,
                    ),
                  ),
                  if (showPerson)
                    Text(
                      [
                        row.person,
                        if ((row.personTitle ?? '').isNotEmpty)
                          row.personTitle!,
                      ].join(' · '),
                      style: VfType.small.copyWith(
                        fontSize: 14,
                        color: t.text2,
                      ),
                    ),
                  if (whenLine.isNotEmpty)
                    Text(
                      whenLine,
                      style: VfType.meta.copyWith(fontSize: 13, color: t.muted),
                    ),
                  if (state == 'current' && youActHere)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: t.primarySoftStrong,
                        borderRadius: BorderRadius.circular(VfSize.radiusPill),
                      ),
                      child: Text(
                        dt('yourTurn'),
                        style: VfType.meta.copyWith(
                          color: t.primaryText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (signature != null)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      height: 46,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: VfDoc.paper,
                        borderRadius: BorderRadius.circular(VfSize.radiusS),
                        border: Border.all(color: t.border),
                      ),
                      child: Image.memory(
                        signature,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  if ((row.comment ?? '').isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      decoration: BoxDecoration(
                        color: t.surface2,
                        borderRadius: BorderRadius.circular(VfSize.radiusM),
                        border: Border(
                          left: BorderSide(color: t.borderStrong, width: 2),
                        ),
                      ),
                      child: Text(
                        '“${row.comment}”',
                        style: VfType.small.copyWith(
                          fontSize: 14,
                          color: t.text2,
                        ),
                      ),
                    ),
                  if (row.capabilityText.isNotEmpty &&
                      row.capabilityText != 'null' &&
                      state != 'pending')
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${dt('permitted')}: ${row.capabilityText}',
                        style: VfType.meta.copyWith(
                          fontSize: 12,
                          color: t.faint,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
