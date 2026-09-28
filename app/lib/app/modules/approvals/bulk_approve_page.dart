import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/detail_models.dart';
import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/session_service.dart';
import '../../data/services/voucher_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart';
import '../../widgets/vf/vf.dart';
import '../shell/shell_page.dart';
import '../vouchers/detail_bits.dart';
import '../vouchers/detail_dialogs.dart' show DialogActions, StatementCheck;
import 'queue_row.dart';

/// Whether a queued voucher can be approved from the list: an approving step
/// that is ready, or one the approver's saved signature can sign first.
bool bulkEligible(Voucher v) =>
    v.actions.approve || (v.actions.sign && v.currentStepCanApprove);

/// Every voucher waiting on this person's step, laid out for deciding — and,
/// for those that may be, approved several at once behind one confirmation.
class BulkApproveController extends GetxController {
  final repo = Get.find<VoucherRepository>();
  final session = Get.find<SessionService>();

  final queue = Rxn<List<Voucher>>();
  final error = RxnString();
  final workflows = Rxn<List<WorkflowInfo>>();
  final selected = <int>{}.obs;
  final busy = false.obs;
  final query = ''.obs;
  final kind = 'all'.obs;

  @override
  void onInit() {
    super.onInit();
    load();
    WorkflowCache.load().then((w) => workflows.value = w);
  }

  Future<void> load() async {
    error.value = null;
    try {
      final fresh = await repo.pending();
      queue.value = fresh;
      selected.removeWhere(
        (id) => !fresh.any((v) => v.id == id && bulkEligible(v)),
      );
    } on ApiException catch (e) {
      error.value = e.message;
    } catch (_) {
      error.value = 'state.offline'.tr;
    }
  }

  List<Voucher> get shown {
    final needle = query.value.trim().toLowerCase();
    return (queue.value ?? const <Voucher>[]).where((v) {
      if (kind.value != 'all' && v.kind != kind.value) return false;
      if (needle.isEmpty) return true;
      return [
        v.number,
        v.purpose,
        v.payee,
        v.requesterName,
        v.departmentName,
      ].whereType<String>().any((x) => x.toLowerCase().contains(needle));
    }).toList();
  }

  List<Voucher> get chosen => (queue.value ?? const <Voucher>[])
      .where((v) => selected.contains(v.id))
      .toList();

  double get chosenTotal => chosen.fold(0, (sum, v) => sum + v.amount);

  void toggle(int id) =>
      selected.contains(id) ? selected.remove(id) : selected.add(id);

  Future<BulkApproveResult?> approve(String? comment) async {
    busy.value = true;
    try {
      final r = await repo.bulkApproveVouchers(
        chosen.map((v) => v.id).toList(),
        comment: comment,
      );
      final n = r.approved.length;
      showToast(
        n == 1
            ? dt('bulkApprovedOne')
            : dt('bulkApprovedMany', {'count': '$n'}),
        body: r.skipped.isEmpty
            ? null
            : '${dt('skipped')} — ${r.skipped.join(' ')}',
        kind: r.skipped.isEmpty ? ToastKind.ok : ToastKind.warn,
      );
      selected.clear();
      session.refreshUnread();
      if (Get.isRegistered<ShellController>()) {
        Get.find<ShellController>().refreshCounts();
      }
      await load();
      return r;
    } on ApiException catch (e) {
      showToast(dt('approveFailed'), body: e.message, kind: ToastKind.bad);
    } catch (_) {
      showToast(
        dt('approveFailed'),
        body: 'state.offline'.tr,
        kind: ToastKind.bad,
      );
    } finally {
      busy.value = false;
    }
    return null;
  }
}

/// A shell page at `/approvals`, and a pushed page at [Routes.bulkApprove].
class BulkApprovePage extends StatefulWidget {
  const BulkApprovePage({super.key});

  @override
  State<BulkApprovePage> createState() => _BulkApprovePageState();
}

class _BulkApprovePageState extends State<BulkApprovePage> {
  late final BulkApproveController c = Get.put(BulkApproveController());
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    Get.delete<BulkApproveController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pushed = ModalRoute.of(context)?.settings.name == Routes.bulkApprove;
    final body = Obx(() => _body(context));
    return pushed
        ? VouchFlowPushedScaffold(title: 'nav.bulkApprove'.tr, body: body)
        : body;
  }

  void _toRegister() {
    if (Get.isRegistered<ShellController>()) {
      if (ModalRoute.of(context)?.settings.name == Routes.bulkApprove) {
        Navigator.of(context).pop();
      }
      Get.find<ShellController>().go('/vouchers');
    }
  }

  Widget _body(BuildContext context) {
    final t = context.vf;
    final queue = c.queue.value;
    if (c.error.value != null && queue == null) {
      return VouchFlowPageBody(
        onRefresh: c.load,
        children: [
          VouchFlowErrorState(
            message: c.error.value!,
            onRetry: c.load,
            retryLabel: 'action.retry'.tr,
          ),
        ],
      );
    }
    if (queue == null) {
      return const VouchFlowPageBody(
        children: [VouchFlowLoadingState(rows: 4)],
      );
    }

    final currency = c.session.company.value?.currency ?? 'TZS';
    final shown = c.shown;
    final eligible = shown.where(bulkEligible).toList();
    final chosen = c.chosen;
    final allChosen =
        eligible.isNotEmpty && eligible.every((v) => c.selected.contains(v.id));
    final total = queue.fold<double>(0, (s, v) => s + v.amount);
    final oldest = queue.isEmpty
        ? null
        : ([...queue]..sort((a, b) => _since(a).compareTo(_since(b)))).first;
    final word = queue.length == 1 ? dt('voucherWord') : dt('vouchersWord');
    final signOnly =
        queue.isNotEmpty && queue.every((v) => !v.currentStepCanApprove);
    final workflows = c.workflows.value;

    final list = Stack(
      children: [
        VouchFlowPageBody(
          onRefresh: c.load,
          padding: EdgeInsets.fromLTRB(
            VfSize.pagePad,
            20,
            VfSize.pagePad,
            chosen.isEmpty ? 32 : 120,
          ),
          children: [
            VouchFlowPageHeader(
              title: queue.isNotEmpty
                  ? '${queue.length} $word ${dt('awaitingYou')}'
                  : dt('nothingAwaiting'),
              subtitle: signOnly ? dt('signOnlyNote') : dt('bulkApproveIntro'),
              actions: [
                if (Get.isRegistered<ShellController>())
                  VouchFlowButton(
                    label: dt('voucherRegister'),
                    icon: PhosphorIconsRegular.receipt,
                    variant: VfButtonVariant.secondary,
                    onPressed: _toRegister,
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (queue.isNotEmpty) ...[
              FigureGrid(
                children: [
                  VouchFlowStatCard(
                    label: dt('awaitingYouLabel'),
                    value: '${queue.length}',
                    tone: VfTone.info,
                  ),
                  VouchFlowStatCard(
                    label: dt('total'),
                    value: Fmt.money(total, currency),
                  ),
                  VouchFlowStatCard(
                    label: dt('bank'),
                    value: '${queue.where((v) => !v.isCash).length}',
                  ),
                  VouchFlowStatCard(
                    label: dt('cash'),
                    value: '${queue.where((v) => v.isCash).length}',
                  ),
                  if (oldest != null)
                    VouchFlowStatCard(
                      label: dt('waitingSince'),
                      value: Fmt.date(oldest.submittedAt ?? oldest.voucherDate),
                      sub: oldest.number,
                    ),
                ],
              ),
              const SizedBox(height: 20),
            ],
            VouchFlowCard(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (queue.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: t.border)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          VouchFlowSearchField(
                            placeholder: dt('searchPh'),
                            controller: search,
                            onChanged: (q) => c.query.value = q,
                          ),
                          const SizedBox(height: 12),
                          KindFilter(
                            value: c.kind.value,
                            onChanged: (k) => c.kind.value = k,
                          ),
                          if (eligible.length > 1)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: StatementCheck(
                                value: allChosen,
                                onChanged: (_) => allChosen
                                    ? c.selected.clear()
                                    : c.selected.addAll(
                                        eligible.map((v) => v.id),
                                      ),
                                text: dt('selectAllForApproval'),
                              ),
                            ),
                          const SizedBox(height: 6),
                          Text(
                            '${dt('showing')} ${shown.length} ${dt('of')} ${queue.length}',
                            style: VfType.small.copyWith(color: t.muted),
                          ),
                        ],
                      ),
                    ),
                  if (queue.isEmpty)
                    VouchFlowEmptyState(
                      icon: PhosphorIconsRegular.checkCircle,
                      title: dt('nothingAwaiting'),
                      body: dt('nothingAwaitingBody'),
                      actionLabel: Get.isRegistered<ShellController>()
                          ? dt('register')
                          : null,
                      onAction: _toRegister,
                    )
                  else if (shown.isEmpty)
                    VouchFlowEmptyState(
                      icon: PhosphorIconsRegular.magnifyingGlass,
                      title: dt('noResults'),
                    )
                  else ...[
                    for (var i = 0; i < shown.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: t.border),
                      _row(context, shown[i], eligible.isNotEmpty, workflows),
                    ],
                    PanelFoot(
                      text: dt('clearedNote'),
                      icon: PhosphorIconsRegular.shieldCheck,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (chosen.isNotEmpty)
          Positioned(
            left: VfSize.pagePad,
            right: VfSize.pagePad,
            bottom: 12,
            child: _bulkBar(context, chosen, currency),
          ),
      ],
    );
    return list;
  }

  Widget _row(
    BuildContext context,
    Voucher v,
    bool withChecks,
    List<WorkflowInfo>? workflows,
  ) {
    final t = context.vf;
    final row = QueueRow(
      voucher: v,
      progress: deriveProgress(v, workflows),
      onOpen: () => openVoucher(v.id, then: c.load),
    );
    if (!withChecks) return row;
    final eligible = bulkEligible(v);
    final selected = c.selected.contains(v.id);
    return Container(
      color: selected ? t.primarySoft : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: SizedBox(
              width: 44,
              height: 44,
              child: eligible
                  ? Checkbox(
                      value: selected,
                      onChanged: (_) => c.toggle(v.id),
                      activeColor: t.primary,
                      side: BorderSide(color: t.borderStrong, width: 1.5),
                      semanticLabel: '${dt('select')} ${v.number}',
                    )
                  : null,
            ),
          ),
          Expanded(child: row),
        ],
      ),
    );
  }

  Widget _bulkBar(BuildContext context, List<Voucher> chosen, String currency) {
    final t = context.vf;
    return Material(
      color: t.surface,
      elevation: 8,
      shadowColor: Colors.black45,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VfSize.radiusL),
        side: BorderSide(color: t.borderStrong),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${chosen.length}',
                    style: TextStyle(
                      color: t.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: ' ${dt('selected')} · '),
                  TextSpan(
                    text: Fmt.money(c.chosenTotal, currency),
                    style: TextStyle(
                      color: t.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              style: VfType.body.copyWith(color: t.text2),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: VouchFlowButton(
                    label: dt('clearSelection'),
                    variant: VfButtonVariant.ghost,
                    compact: true,
                    expand: true,
                    onPressed: c.selected.clear,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: VouchFlowButton(
                    label: '${dt('approveSelected')} (${chosen.length})',
                    icon: PhosphorIconsRegular.sealCheck,
                    compact: true,
                    expand: true,
                    onPressed: () => _confirm(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _BulkConfirm(controller: c),
  );
}

DateTime _since(Voucher v) => v.submittedAt ?? v.voucherDate ?? DateTime(2100);

class _BulkConfirm extends StatefulWidget {
  const _BulkConfirm({required this.controller});

  final BulkApproveController controller;

  @override
  State<_BulkConfirm> createState() => _BulkConfirmState();
}

class _BulkConfirmState extends State<_BulkConfirm> {
  final comment = TextEditingController();
  bool reviewed = false;

  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final t = context.vf;
    final currency = c.session.company.value?.currency ?? 'TZS';
    return Obx(() {
      final chosen = c.chosen;
      final busy = c.busy.value;
      return VouchFlowDialog(
        icon: PhosphorIconsRegular.sealCheck,
        tone: VfTone.ok,
        title: chosen.length == 1
            ? dt('bulkApproveQOne')
            : dt('bulkApproveQMany', {'count': '${chosen.length}'}),
        subtitle: dt('bulkApproveSub'),
        summary: [
          VfSummaryRow(dt('bulkCount'), '${chosen.length}'),
          VfSummaryRow(dt('total'), Fmt.money(c.chosenTotal, currency)),
        ],
        actions: [
          DialogActions(
            children: [
              VouchFlowButton(
                label: dt('cancel'),
                variant: VfButtonVariant.ghost,
                onPressed: busy ? null : () => Navigator.of(context).pop(),
              ),
              VouchFlowButton(
                label: dt('approveSelected'),
                icon: PhosphorIconsRegular.sealCheck,
                loading: busy,
                onPressed: !reviewed || busy || chosen.isEmpty
                    ? null
                    : () async {
                        final navigator = Navigator.of(context);
                        final r = await c.approve(
                          comment.text.trim().isEmpty
                              ? null
                              : comment.text.trim(),
                        );
                        if (r != null && navigator.mounted) navigator.pop();
                      },
              ),
            ],
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                border: Border.all(color: t.border),
                borderRadius: BorderRadius.circular(VfSize.radiusM),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: chosen.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: t.border),
                itemBuilder: (_, i) {
                  final v = chosen[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Text(
                          v.number,
                          style: VfType.small.copyWith(
                            color: t.text,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            v.purpose,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: VfType.small.copyWith(color: t.text2),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          v.amountText,
                          style: VfType.small.copyWith(
                            color: t.text,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            VouchFlowTextField(
              label: dt('bulkComment'),
              controller: comment,
              maxLines: 2,
              minLines: 2,
            ),
            const SizedBox(height: 8),
            StatementCheck(
              value: reviewed,
              onChanged: (v) => setState(() => reviewed = v),
              text: dt('bulkReviewedStatement'),
            ),
          ],
        ),
      );
    });
  }
}
