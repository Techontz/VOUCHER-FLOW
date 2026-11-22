import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart';
import '../../data/models/sales_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/sales_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart' show showToast;
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate, dashDateTime;
import '../erp/erp_widgets.dart';
import 'sales_widgets.dart';

/// One sales invoice (the web's /erp/sales/invoices/[id]): lines, totals,
/// what was paid and credited, what is still owed; Post and Cancel a
/// draft, and Receive payment against a posted one. Opened with the
/// invoice id as the argument.
class SalesInvoicePage extends StatefulWidget {
  const SalesInvoicePage({super.key, this.invoiceId});

  final int? invoiceId;

  @override
  State<SalesInvoicePage> createState() => _SalesInvoicePageState();
}

class _SalesInvoicePageState extends State<SalesInvoicePage> {
  late final int _id = widget.invoiceId ?? (Get.arguments as int);
  final _repo = SalesRepository.to;
  final _erp = ErpService.to;
  SalesInvoice? _invoice;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final i = await _repo.invoice(_id);
      if (mounted) setState(() { _invoice = i; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'state.offline'.tr);
    }
  }

  List<VfSummaryRow> _summary(SalesInvoice i) => [
    VfSummaryRow('sal.customer'.tr, i.customer?.name ?? '-'),
    VfSummaryRow('sal.total'.tr, salesMoney(i.totals.total)),
    if (i.dueDate != null) VfSummaryRow('sal.due'.tr, dashDate(i.dueDate)),
  ];

  Future<void> _post(SalesInvoice i) async {
    final m = await confirmSalesAction(
      context,
      icon: PhosphorIconsRegular.checkCircle,
      title: 'sal.postInvoiceQ'.trParams({'number': i.number}),
      subtitle: 'sal.postInvoiceSub'.tr,
      summary: _summary(i),
      confirmLabel: 'sal.post'.tr,
      run: (_) => _repo.postInvoice(i.id),
    );
    if (m == null) return;
    showToast(m.isEmpty ? salesStatusLabel(SalesStatus.posted) : m);
    _load();
  }

  Future<void> _cancel(SalesInvoice i) async {
    final m = await confirmSalesAction(
      context,
      icon: PhosphorIconsRegular.xCircle,
      tone: VfTone.warn,
      title: 'sal.cancelInvoiceQ'.trParams({'number': i.number}),
      summary: _summary(i),
      confirmLabel: 'sal.cancelDoc'.tr,
      backLabel: 'sal.keep'.tr,
      danger: true,
      run: (_) => _repo.cancelInvoice(i.id),
    );
    if (m == null) return;
    showToast(m.isEmpty ? salesStatusLabel(SalesStatus.cancelled) : m);
    _load();
  }

  Future<void> _receive(SalesInvoice i) async {
    await Get.toNamed(Routes.salesReceiptNew, arguments: {'customerId': i.customerId, 'invoiceId': i.id});
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final i = _invoice;
    return VouchFlowPushedScaffold(
      title: i?.number ?? 'sal.invoice'.tr,
      body: i == null
          ? (_error == null
                ? const VfLoadingView()
                : ErpPageBody(children: [VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)]))
          : _body(context, i),
      bottomBar: i == null ? null : _actions(i),
    );
  }

  Widget? _actions(SalesInvoice i) {
    final buttons = <Widget>[
      if (i.status == SalesStatus.draft && _erp.can('sales.invoice')) ...[
        VouchFlowButton(label: 'sal.cancelDoc'.tr, variant: VfButtonVariant.secondary, onPressed: () => _cancel(i)),
        VouchFlowButton(label: 'sal.post'.tr, icon: PhosphorIconsRegular.checkCircle, onPressed: () => _post(i)),
      ],
      if (i.isOpen && _erp.can('sales.receipt'))
        VouchFlowButton(label: 'sal.receivePayment'.tr, icon: PhosphorIconsRegular.handCoins, onPressed: () => _receive(i)),
    ];
    return buttons.isEmpty ? null : SalesActionBar(children: buttons);
  }

  Widget _body(BuildContext context, SalesInvoice i) {
    final t = context.vf;
    return ErpPageBody(
      onRefresh: _load,
      children: [
        SalesDocHead(
          icon: PhosphorIconsRegular.receipt,
          tint: i.isOverdue ? t.dangerStrong : t.infoStrong,
          kind: 'sal.invoice'.tr,
          number: i.number,
          status: i.status,
          subtitle: [?i.customer?.name, if (i.invoiceDate != null) dashDate(i.invoiceDate)].join(' · '),
          extra: i.isOverdue
              ? VouchFlowStatusBadge(label: 'sal.filter.overdue'.tr, tag: 'tag-accent-2', large: true)
              : (i.status == SalesStatus.posted && !i.isOpen
                    ? VouchFlowStatusBadge(label: 'sal.st.paid'.tr, tag: 'tag-accent', large: true)
                    : null),
        ),
        if (i.isOpen) ...[
          VouchFlowFigureCard(
            label: 'sal.balanceDue'.tr,
            value: salesMoney(i.balance),
            hint: i.dueDate == null
                ? null
                : (i.isOverdue ? 'sal.overdueSince' : 'sal.dueOn').trParams({'date': dashDate(i.dueDate)}),
            icon: PhosphorIconsRegular.scales,
            tone: i.isOverdue ? VfTone.bad : VfTone.warn,
          ),
          erpGap,
        ],
        VouchFlowPanel(
          title: 'sal.lines'.tr,
          padded: false,
          child: Column(
            children: [
              for (var n = 0; n < i.lines.length; n++)
                VouchFlowListRow(
                  divider: n > 0,
                  title: i.lines[n].productName,
                  titleMaxLines: 2,
                  subtitle: [
                    '${ErpFmt.qty(i.lines[n].quantity)}${i.lines[n].unitCode == null ? '' : ' ${i.lines[n].unitCode}'} × ${ErpFmt.amount(i.lines[n].unitPrice)}',
                    if (i.lines[n].quantityCredited > 0) 'sal.credited'.trParams({'n': ErpFmt.qty(i.lines[n].quantityCredited)}),
                  ].join(' · '),
                  trailing: MoneyText(i.lines[n].lineTotal, style: VfType.small.copyWith(fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'sal.summary'.tr,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SalesTotalsBlock(
                totals: i.totals,
                extra: [
                  if (i.amountPaid > 0) ('sal.paid'.tr, -i.amountPaid, false),
                  if (i.amountCredited > 0) ('sal.creditedAmount'.tr, -i.amountCredited, false),
                  if (i.status == SalesStatus.posted) ('sal.balance'.tr, i.balance, true),
                ],
              ),
              const SizedBox(height: 8),
              SalesFact(
                'sal.customer'.tr,
                i.customer?.name,
                onTap: i.customer == null || !_erp.can('customers.view')
                    ? null
                    : () => Get.toNamed(Routes.salesCustomer, arguments: i.customer!.id),
              ),
              SalesFact(
                'sal.order'.tr,
                i.order?.number,
                onTap: i.order == null ? null : () => Get.toNamed(Routes.salesOrder, arguments: i.order!.id, preventDuplicates: false),
              ),
              SalesFact('sal.deliveryNote'.tr, i.deliveryNoteNumber),
              SalesFact('sal.due'.tr, i.dueDate == null ? null : dashDate(i.dueDate)),
              SalesFact('sal.prepared'.tr, [i.creator ?? '-', if (i.createdAt != null) dashDateTime(i.createdAt)].join(' · ')),
              if (i.postedAt != null) SalesFact('sal.postedBy'.tr, [i.poster ?? '-', dashDateTime(i.postedAt)].join(' · ')),
              SalesFact('sal.notes'.tr, i.notes),
            ],
          ),
        ),
        if (i.allocations.isNotEmpty) ...[
          erpGap,
          VouchFlowPanel(
            title: 'sal.payments'.tr,
            padded: false,
            child: Column(
              children: [
                for (var n = 0; n < i.allocations.length; n++)
                  VouchFlowListRow(
                    divider: n > 0,
                    icon: PhosphorIconsRegular.handCoins,
                    iconColor: t.successStrong,
                    title: i.allocations[n].receipt?.number ?? '-',
                    subtitle: [
                      if (i.allocations[n].method != null) salesMethodLabel(i.allocations[n].method!),
                      if (i.allocations[n].date != null) dashDate(i.allocations[n].date),
                      if (i.allocations[n].receipt?.status != null) salesStatusLabel(i.allocations[n].receipt!.status!),
                    ].join(' · '),
                    trailing: MoneyText(i.allocations[n].amount, style: VfType.small.copyWith(fontWeight: FontWeight.w600)),
                    onTap: i.allocations[n].receipt == null
                        ? null
                        : () => Get.toNamed(Routes.salesReceipt, arguments: i.allocations[n].receipt!.id),
                  ),
              ],
            ),
          ),
        ],
        if (i.creditNotes.isNotEmpty) ...[
          erpGap,
          VouchFlowPanel(
            title: 'sal.creditNotes'.tr,
            padded: false,
            child: Column(
              children: [
                for (var n = 0; n < i.creditNotes.length; n++)
                  VouchFlowListRow(
                    divider: n > 0,
                    icon: PhosphorIconsRegular.arrowUUpLeft,
                    iconColor: t.warningStrong,
                    title: i.creditNotes[n].number,
                    subtitle: [
                      if (i.creditNotes[n].date != null) dashDate(i.creditNotes[n].date),
                      salesMoney(i.creditNotes[n].total),
                    ].join(' · '),
                    trailing: SalesStatusBadge(i.creditNotes[n].status),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
