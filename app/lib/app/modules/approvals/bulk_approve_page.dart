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

  /// Selection mode: round checks on the rows, a bar to approve them.
  bool selecting = false;

  @override
  void dispose() {
    search.dispose();
    Get.delete<BulkApproveController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pushed = ModalRoute.of(context)?.settings.name == Routes.bulkApprove;
    final body = Obx(() => _body(context, pushed));
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

  void _setSelecting(bool on) {
    setState(() => selecting = on);
    if (!on) c.selected.clear();
  }

  Widget _body(BuildContext context, bool pushed) {
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
    // A selection made elsewhere (or kept across a reload) shows its checks.
    final inSelection = (selecting && eligible.isNotEmpty) || chosen.isNotEmpty;
    final allChosen =
        eligible.isNotEmpty && eligible.every((v) => c.selected.contains(v.id));
    final total = queue.fold<double>(0, (s, v) => s + v.amount);
    final oldest = queue.isEmpty
        ? null
        : ([...queue]..sort((a, b) => _since(a).compareTo(_since(b)))).first;
    final signOnly =
        queue.isNotEmpty && queue.every((v) => !v.currentStepCanApprove);
    final workflows = c.workflows.value;
    final hasShell = Get.isRegistered<ShellController>();

    return Stack(
      children: [
        VouchFlowPageBody(
          onRefresh: c.load,
          padding: EdgeInsets.fromLTRB(
            VfSize.pagePad,
            pushed ? 4 : 16,
            VfSize.pagePad,
            chosen.isEmpty ? 32 : 140,
          ),
          children: [
            AppScreenTitle(
              title: pushed ? '' : 'nav.approvals'.tr,
              count: queue.isEmpty ? null : queue.length,
              trailing: [
                if (eligible.isNotEmpty)
                  AppTextAction(
                    label: inSelection ? dt('cancel') : dt('select'),
                    icon: inSelection ? null : PhosphorIconsRegular.checkCircle,
                    onPressed: () => _setSelecting(!inSelection),
                  ),
                if (hasShell)
                  VfBarButton(
                    icon: PhosphorIconsRegular.receipt,
                    tooltip: dt('voucherRegister'),
                    onPressed: _toRegister,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (queue.isNotEmpty) ...[
              AppStatStrip(
                stats: [
                  AppStat(
                    dt('total'),
                    Fmt.money(total, currency),
                    icon: PhosphorIconsFill.wallet,
                  ),
                  AppStat(
                    dt('bank'),
                    '${queue.where((v) => !v.isCash).length}',
                    icon: PhosphorIconsFill.bank,
                    tint: (t.infoStrong, t.infoSoft),
                  ),
                  AppStat(
                    dt('cash'),
                    '${queue.where((v) => v.isCash).length}',
                    icon: PhosphorIconsFill.money,
                    tint: (t.successStrong, t.successSoft),
                  ),
                  if (oldest != null)
                    AppStat(
                      dt('waitingSince'),
                      Fmt.date(oldest.submittedAt ?? oldest.voucherDate),
                      sub: oldest.number,
                      icon: PhosphorIconsFill.clock,
                      tint: (t.warningStrong, t.warningSoft),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (signOnly) ...[
                _Note(text: dt('signOnlyNote')),
                const SizedBox(height: 12),
              ],
              VouchFlowSearchField(
                placeholder: dt('searchPh'),
                controller: search,
                onChanged: (q) => c.query.value = q,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: KindFilter(
                      value: c.kind.value,
                      onChanged: (k) => c.kind.value = k,
                    ),
                  ),
                  if (inSelection && eligible.length > 1)
                    TextButton(
                      onPressed: () => allChosen
                          ? c.selected.clear()
                          : c.selected.addAll(eligible.map((v) => v.id)),
                      child: Text(
                        allChosen
                            ? dt('clearSelection')
                            : 'payments.selectAll'.tr,
                        style: VfType.label.copyWith(
                          color: t.primaryText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            if (queue.isEmpty)
              VouchFlowCard(
                radius: VfSize.radiusXl,
                padding: EdgeInsets.zero,
                child: VouchFlowEmptyState(
                  icon: PhosphorIconsRegular.checkCircle,
                  title: dt('nothingAwaiting'),
                  actionLabel: hasShell ? dt('register') : null,
                  onAction: _toRegister,
                ),
              )
            else if (shown.isEmpty)
              VouchFlowCard(
                radius: VfSize.radiusXl,
                padding: EdgeInsets.zero,
                child: VouchFlowEmptyState(
                  icon: PhosphorIconsRegular.magnifyingGlass,
                  title: dt('noResults'),
                ),
              )
            else
              AppListGroup(
                children: [
                  for (final v in shown)
                    QueueRow(
                      voucher: v,
                      progress: deriveProgress(v, workflows),
                      onOpen: () => openVoucher(v.id, then: c.load),
                      selecting: inSelection,
                      selectable: bulkEligible(v),
                      selected: c.selected.contains(v.id),
                      onToggle: () => c.toggle(v.id),
                      onLongPress: bulkEligible(v)
                          ? () {
                              setState(() => selecting = true);
                              c.toggle(v.id);
                            }
                          : null,
                    ),
                ],
              ),
          ],
        ),
        if (chosen.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _bulkBar(context, chosen, currency),
          ),
      ],
    );
  }

  Widget _bulkBar(BuildContext context, List<Voucher> chosen, String currency) {
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        VfSize.pagePad,
        12,
        VfSize.pagePad,
        12,
      ),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(VfSize.radiusXl),
        ),
        border: Border(top: BorderSide(color: t.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: t.isDark ? .45 : .10),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${chosen.length} ${dt('selected')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VfType.meta.copyWith(color: t.muted),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    Fmt.money(c.chosenTotal, currency),
                    style: VfType.bodyStrong.copyWith(
                      color: t.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 16.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          VouchFlowIconButton(
            icon: PhosphorIconsRegular.x,
            tooltip: dt('clearSelection'),
            onPressed: () => _setSelecting(false),
          ),
          const SizedBox(width: 6),
          VouchFlowButton(
            label: '${'payments.approve'.tr} (${chosen.length})',
            icon: PhosphorIconsRegular.sealCheck,
            onPressed: () => _confirm(context),
          ),
        ],
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

/// A one-line tinted note (shown only when it changes what the reader does).
class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(
        color: t.infoSoft,
        borderRadius: BorderRadius.circular(VfSize.radiusL),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhosphorIconsFill.info, size: 17, color: t.infoStrong),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: VfType.small.copyWith(color: t.infoStrong),
            ),
          ),
        ],
      ),
    );
  }
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
