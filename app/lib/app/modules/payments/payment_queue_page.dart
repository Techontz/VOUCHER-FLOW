import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../data/models/detail_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/session_service.dart';
import '../../data/services/voucher_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/vf/vf.dart';
import '../approvals/queue_row.dart';
import '../shell/shell_page.dart';
import '../vouchers/detail_bits.dart';

/// A `payments.` string.
String pt(String key, [Map<String, String>? params]) =>
    params == null ? 'payments.$key'.tr : 'payments.$key'.trParams(params);

typedef _Tally = ({int count, double amount});

/// The payment queue.
///
/// Everything here has already cleared the approval workflow; the person with
/// the pay capability releases the funds on the voucher itself, behind a
/// confirmation. Every figure covers the whole set, and what is awaiting
/// payment is counted by what is still owed — a part-paid voucher counts for
/// its balance, not its full approved amount.
class PaymentQueueController extends GetxController {
  final repo = Get.find<VoucherRepository>();
  final session = Get.find<SessionService>();

  final filter = 'all'.obs;
  final page = 1.obs;
  final due = Rxn<VoucherPage>();
  final paid = Rxn<VoucherPage>();
  final figures = Rxn<({_Tally due, _Tally bank, _Tally cash, _Tally paidMonth})>();
  final error = RxnString();
  final workflows = Rxn<List<WorkflowInfo>>();
  final exporting = RxnString();

  String get kind => filter.value == 'all' ? '' : filter.value;

  @override
  void onInit() {
    super.onInit();
    reload();
    WorkflowCache.load().then((w) => workflows.value = w);
  }

  Future<void> reload() async {
    error.value = null;
    await Future.wait([loadFigures(), loadLists()]);
  }

  void _fail(Object e) => error.value = e is ApiException ? e.message : 'state.offline'.tr;

  /// What is owed, from the list's own balance total (part payments deducted).
  _Tally _owed(VoucherPage p) => (count: p.total, amount: p.totalBalance ?? p.totalAmount);

  Future<void> loadFigures() async {
    final now = DateTime.now();
    String d(DateTime x) => '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    final from = d(DateTime(now.year, now.month, 1));
    final to = d(DateTime(now.year, now.month + 1, 0));
    try {
      final r = await Future.wait([
        repo.page(status: 'approved', perPage: 1),
        repo.page(status: 'approved', kind: 'bank', perPage: 1),
        repo.page(status: 'approved', kind: 'cash', perPage: 1),
        repo.page(status: 'paid', paidFrom: from, paidTo: to, perPage: 1),
      ]);
      figures.value = (
        due: _owed(r[0]),
        bank: _owed(r[1]),
        cash: _owed(r[2]),
        paidMonth: (count: r[3].total, amount: r[3].totalAmount),
      );
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> loadLists() async {
    try {
      final r = await Future.wait([
        repo.page(status: 'approved', kind: kind, page: page.value, perPage: 20),
        repo.page(status: 'paid', kind: kind, perPage: 10),
      ]);
      due.value = r[0];
      paid.value = r[1];
    } catch (e) {
      _fail(e);
    }
  }

  void setFilter(String value) {
    filter.value = value;
    page.value = 1;
    loadLists();
  }

  void setPage(int value) {
    page.value = value;
    loadLists();
  }

  /// Exports the report behind this screen, with the same bank/cash choice,
  /// and hands the file to the phone's share sheet.
  Future<void> export(String format) async {
    final reportKind = filter.value == 'cash' ? 'cash' : 'payments';
    exporting.value = format;
    try {
      final bytes = await repo.exportReport(reportKind, {if (filter.value == 'bank') 'kind': 'bank'}, format);
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final name = 'vouchflow-$reportKind-$today.$format';
      await Share.shareXFiles([XFile.fromData(bytes, name: name)], subject: name);
      showToast(pt('exportReady'), body: format.toUpperCase());
    } on ApiException catch (e) {
      showToast(pt('exportFailed'), body: e.message, kind: ToastKind.bad);
    } catch (_) {
      showToast(pt('exportFailed'), body: 'state.offline'.tr, kind: ToastKind.bad);
    } finally {
      exporting.value = null;
    }
  }
}

class PaymentQueuePage extends StatefulWidget {
  const PaymentQueuePage({super.key});

  @override
  State<PaymentQueuePage> createState() => _PaymentQueuePageState();
}

class _PaymentQueuePageState extends State<PaymentQueuePage> {
  late final PaymentQueueController c = Get.put(PaymentQueueController());

  @override
  void dispose() {
    Get.delete<PaymentQueueController>();
    super.dispose();
  }

  void _go(String href) {
    if (Get.isRegistered<ShellController>()) {
      Get.find<ShellController>().go(href);
    }
  }

  Future<void> _afterVoucher() async {
    await c.reload();
    if (Get.isRegistered<ShellController>()) {
      Get.find<ShellController>().refreshCounts();
    }
  }

  String _plural(int n) => n == 1 ? pt('voucherWord') : pt('vouchersWord');

  String _kindCount(int n, String kind) => n == 1 ? pt('${kind}One') : pt('${kind}Many', {'count': '$n'});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final t = context.vf;
      final due = c.due.value;
      final figures = c.figures.value;
      if (c.error.value != null && (due == null || figures == null)) {
        return VouchFlowPageBody(
          onRefresh: c.reload,
          children: [VouchFlowErrorState(message: c.error.value!, onRetry: c.reload, retryLabel: 'action.retry'.tr)],
        );
      }
      if (due == null || figures == null) {
        return const VouchFlowPageBody(children: [VouchFlowLoadingState(rows: 5)]);
      }

      final currency = c.session.company.value?.currency ?? 'TZS';
      final paid = c.paid.value;
      final workflows = c.workflows.value;
      final hasShell = Get.isRegistered<ShellController>();

      return VouchFlowPageBody(
        onRefresh: c.reload,
        children: [
          VouchFlowPageHeader(
            title: '${figures.due.count} ${_plural(figures.due.count)} ${pt('awaitingPayment').toLowerCase()}',
            subtitle: pt('payNote'),
            actions: [
              _ExportMenu(controller: c),
              if (hasShell)
                VouchFlowButton(
                  label: pt('voucherRegister'),
                  icon: PhosphorIconsRegular.receipt,
                  variant: VfButtonVariant.secondary,
                  onPressed: () => _go('/vouchers'),
                ),
            ],
          ),
          const SizedBox(height: 20),
          FigureGrid(
            children: [
              VouchFlowStatCard(
                label: pt('awaitingPayment'),
                value: Fmt.money(figures.due.amount, currency),
                sub: '${figures.due.count} ${_plural(figures.due.count)}',
                tone: figures.due.count > 0 ? VfTone.info : VfTone.primary,
              ),
              VouchFlowStatCard(
                label: pt('bankTransfers'),
                value: Fmt.money(figures.bank.amount, currency),
                sub: _kindCount(figures.bank.count, 'bank'),
              ),
              VouchFlowStatCard(
                label: pt('cashDue'),
                value: Fmt.money(figures.cash.amount, currency),
                sub: _kindCount(figures.cash.count, 'cash'),
              ),
              VouchFlowStatCard(
                label: pt('paidThisMonth'),
                value: Fmt.money(figures.paidMonth.amount, currency),
                sub: '${figures.paidMonth.count} ${_plural(figures.paidMonth.count)}',
                tone: VfTone.ok,
              ),
            ],
          ),
          const SizedBox(height: 20),
          VouchFlowCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: t.border)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              pt('awaitingPayment'),
                              style: VfType.sectionTitle.copyWith(color: t.text, fontSize: 17),
                            ),
                          ),
                          const SizedBox(width: 8),
                          CountPill(due.total),
                        ],
                      ),
                      const SizedBox(height: 12),
                      KindFilter(value: c.filter.value, onChanged: c.setFilter),
                    ],
                  ),
                ),
                if (due.data.isEmpty)
                  VouchFlowEmptyState(
                    icon: PhosphorIconsRegular.checkCircle,
                    title: pt('nothingAwaiting'),
                    body: pt('nothingAwaitingBody'),
                    actionLabel: hasShell ? pt('voucherRegister') : null,
                    onAction: () => _go('/vouchers'),
                  )
                else ...[
                  for (var i = 0; i < due.data.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: t.border),
                    QueueRow(
                      voucher: due.data[i],
                      owing: true,
                      progress: deriveProgress(due.data[i], workflows),
                      onOpen: () => openVoucher(due.data[i].id, then: _afterVoucher),
                    ),
                  ],
                  if (due.lastPage > 1)
                    _Pagination(page: due.currentPage, lastPage: due.lastPage, total: due.total, onChange: c.setPage),
                  PanelFoot(text: pt('approveNextNote')),
                ],
              ],
            ),
          ),
          if (paid != null && paid.data.isNotEmpty) ...[
            const SizedBox(height: 16),
            VouchFlowCard(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
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
                                  pt('paidVouchers'),
                                  style: VfType.sectionTitle.copyWith(color: t.text, fontSize: 17),
                                ),
                              ),
                              const SizedBox(width: 8),
                              CountPill(paid.total),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (hasShell)
                          Flexible(
                            child: VouchFlowButton(
                              label: pt('viewAllPaid'),
                              trailingIcon: PhosphorIconsRegular.arrowRight,
                              variant: VfButtonVariant.ghost,
                              compact: true,
                              onPressed: () {
                                // The web's /vouchers?status=paid.
                                Get.find<ShellController>().register.setStatus('paid');
                                _go('/vouchers');
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (var i = 0; i < paid.data.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: t.border),
                    QueueRow(
                      voucher: paid.data[i],
                      history: true,
                      showCta: false,
                      onOpen: () => openVoucher(paid.data[i].id, then: _afterVoucher),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    });
  }
}

class _Pagination extends StatelessWidget {
  const _Pagination({required this.page, required this.lastPage, required this.total, required this.onChange});

  final int page, lastPage, total;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          Text(
            '${pt('showing')} $total · ${pt('page')} $page ${pt('of')} $lastPage',
            style: VfType.small.copyWith(color: t.muted),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              VouchFlowButton(
                label: pt('back'),
                icon: PhosphorIconsRegular.caretLeft,
                variant: VfButtonVariant.secondary,
                compact: true,
                onPressed: page <= 1 ? null : () => onChange(page - 1),
              ),
              const SizedBox(width: 8),
              VouchFlowButton(
                label: pt('next'),
                trailingIcon: PhosphorIconsRegular.caretRight,
                variant: VfButtonVariant.secondary,
                compact: true,
                onPressed: page >= lastPage ? null : () => onChange(page + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Export — PDF, Excel or CSV of the report behind this screen.
class _ExportMenu extends StatelessWidget {
  const _ExportMenu({required this.controller});

  final PaymentQueueController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Obx(() {
      final busy = controller.exporting.value != null;
      return PopupMenuButton<String>(
        enabled: !busy,
        tooltip: pt('exportBtn'),
        position: PopupMenuPosition.under,
        color: t.surface,
        onSelected: controller.export,
        itemBuilder: (_) => [
          for (final (format, icon, label) in [
            ('pdf', PhosphorIconsRegular.filePdf, 'PDF'),
            ('xlsx', PhosphorIconsRegular.microsoftExcelLogo, 'Excel (.xlsx)'),
            ('csv', PhosphorIconsRegular.fileCsv, 'CSV'),
          ])
            PopupMenuItem(
              value: format,
              child: Row(
                children: [
                  Icon(icon, size: 18, color: t.text2),
                  const SizedBox(width: 10),
                  Text(label, style: VfType.body.copyWith(color: t.text)),
                ],
              ),
            ),
        ],
        child: IgnorePointer(
          child: VouchFlowButton(
            label: pt('exportBtn'),
            icon: PhosphorIconsRegular.downloadSimple,
            trailingIcon: PhosphorIconsRegular.caretDown,
            variant: VfButtonVariant.secondary,
            loading: busy,
            onPressed: () {},
          ),
        ),
      );
    });
  }
}
