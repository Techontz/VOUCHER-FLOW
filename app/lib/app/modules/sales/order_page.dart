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
import '../dashboard/dash_bits.dart' show dashDate;
import '../erp/erp_widgets.dart';
import 'sales_widgets.dart';

/// One sales order (the web's /erp/sales/orders/[id]): its lines and the
/// four quantities each travels through, totals, the credit policy, stock
/// on hand, its timeline and related invoices and loadings; and, gated by
/// permission, Submit, Approve, Reject, Cancel, Raise invoice and Create
/// loading order. Opened with the order id as the argument.
class SalesOrderPage extends StatefulWidget {
  const SalesOrderPage({super.key, this.orderId});

  final int? orderId;

  @override
  State<SalesOrderPage> createState() => _SalesOrderPageState();
}

class _SalesOrderPageState extends State<SalesOrderPage> {
  late final int _id = widget.orderId ?? (Get.arguments as int);
  final _repo = SalesRepository.to;
  final _erp = ErpService.to;
  SalesOrder? _order;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final o = await _repo.order(_id);
      if (mounted) setState(() { _order = o; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'state.offline'.tr);
    }
  }

  void _done(String? message, [String? fallback]) {
    if (message == null) return;
    showToast(message.isEmpty ? (fallback ?? 'sal.done'.tr) : message);
    _load();
  }

  List<VfSummaryRow> _summary(SalesOrder o) => [
    VfSummaryRow('sal.customer'.tr, o.customer?.name ?? '-'),
    VfSummaryRow('sal.total'.tr, salesMoney(o.totals.total)),
  ];

  Future<void> _submit(SalesOrder o) async => _done(
    await confirmSalesAction(
      context,
      icon: PhosphorIconsRegular.paperPlaneTilt,
      title: 'sal.submitQ'.trParams({'number': o.number}),
      subtitle: 'sal.submitSub'.tr,
      summary: _summary(o),
      confirmLabel: 'sal.submit'.tr,
      run: (_) => _repo.submitOrder(o.id),
    ),
  );

  Future<void> _approve(SalesOrder o) async {
    final policy = o.policy;
    final failed = policy != null && !policy.passed;
    final qty = {for (final l in o.lines) l.id: TextEditingController(text: ErpFmt.qty(l.quantity).replaceAll(',', ''))};
    final message = await confirmSalesAction(
      context,
      icon: PhosphorIconsRegular.sealCheck,
      tone: failed ? VfTone.warn : VfTone.ok,
      title: 'sal.approveQ'.trParams({'number': o.number}),
      subtitle: o.isPrepayment ? 'sal.approvePrepaySub'.tr : 'sal.approveCreditSub'.tr,
      confirmLabel: 'sal.approve'.tr,
      reason: failed ? SalesReason(label: 'sal.overrideReason'.tr, min: 5) : null,
      extra: (context, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (failed) ...[
            VouchFlowAlert(message: policy.reasons.join(' '), tone: VfTone.warn, icon: PhosphorIconsRegular.warning),
            const SizedBox(height: 14),
          ],
          for (final l in o.lines)
            SalesQtyField(
              label: '${l.productName} (${'sal.qtyOrdered'.tr} ${ErpFmt.qty(l.quantity)})',
              controller: qty[l.id]!,
              onChanged: (_) => setState(() {}),
            ),
        ],
      ),
      run: (reason) => _repo.approveOrder(
        o.id,
        quantities: {for (final l in o.lines) l.id: salesNum(qty[l.id]!.text)},
        overrideReason: reason,
      ),
    );
    // After the sheet has finished sliding away.
    Future.delayed(const Duration(seconds: 1), () {
      for (final c in qty.values) {
        c.dispose();
      }
    });
    _done(message);
  }

  Future<void> _reject(SalesOrder o) async => _done(
    await confirmSalesAction(
      context,
      icon: PhosphorIconsRegular.thumbsDown,
      tone: VfTone.warn,
      title: 'sal.rejectQ'.trParams({'number': o.number}),
      summary: _summary(o),
      confirmLabel: 'sal.reject'.tr,
      danger: true,
      reason: SalesReason(label: 'sal.reason'.tr),
      run: (reason) => _repo.rejectOrder(o.id, reason),
    ),
  );

  Future<void> _cancel(SalesOrder o) async => _done(
    await confirmSalesAction(
      context,
      icon: PhosphorIconsRegular.xCircle,
      tone: VfTone.warn,
      title: 'sal.cancelOrderQ'.trParams({'number': o.number}),
      subtitle: 'sal.cancelOrderSub'.tr,
      summary: _summary(o),
      confirmLabel: 'sal.cancelDoc'.tr,
      backLabel: 'sal.keep'.tr,
      danger: true,
      run: (_) => _repo.cancelOrder(o.id),
    ),
  );

  Future<void> _invoice(SalesOrder o, bool invoicedAll, List<LoadingOrder> deliveredUninvoiced) async {
    int? basis = invoicedAll ? deliveredUninvoiced.firstOrNull?.id : null;
    SalesInvoice? raised;
    final message = await confirmSalesAction(
      context,
      icon: PhosphorIconsRegular.receipt,
      title: 'sal.raiseInvoice'.tr,
      subtitle: 'sal.raiseInvoiceSub'.tr,
      confirmLabel: 'sal.raiseInvoice'.tr,
      extra: (context, setState) {
        final options = <int?>[if (!invoicedAll) null, for (final lo in deliveredUninvoiced) lo.id];
        if (options.length < 2) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: VouchFlowDropdown<int?>(
            label: 'sal.invoiceBasis'.tr,
            items: options,
            value: basis,
            itemLabel: (id) => id == null
                ? 'sal.invoiceApproved'.tr
                : 'sal.invoiceDelivery'.trParams({'number': deliveredUninvoiced.firstWhere((l) => l.id == id).number}),
            onChanged: (v) => setState(() => basis = v),
          ),
        );
      },
      run: (_) async {
        raised = await _repo.invoiceOrder(o.id, loadingOrderId: basis);
        return 'sal.invoicePrepared'.trParams({'number': raised!.number});
      },
    );
    if (message == null) return;
    showToast(message);
    final invoice = raised;
    if (invoice != null) {
      await Get.toNamed(Routes.salesInvoice, arguments: invoice.id);
    }
    _load();
  }

  Future<void> _createLoading(SalesOrder o) async {
    await Get.toNamed(Routes.dispatchLoadingNew, arguments: {'orderId': o.id});
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    return VouchFlowPushedScaffold(
      title: o?.number ?? 'sal.order'.tr,
      body: o == null
          ? (_error == null
                ? const VfLoadingView()
                : ErpPageBody(children: [VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)]))
          : _body(context, o),
      bottomBar: o == null ? null : _actions(o),
    );
  }

  Widget? _actions(SalesOrder o) {
    final invoicedAll = o.lines.every((l) => l.quantityInvoiced >= (l.quantityApproved ?? l.quantity) - 0.00001);
    final invoicedLoadings = {
      for (final i in o.invoices)
        if (i.status != SalesStatus.cancelled && i.loadingOrderId != null) i.loadingOrderId,
    };
    final deliveredUninvoiced =
        o.loadingOrders.where((l) => l.isDelivered && !invoicedLoadings.contains(l.id)).toList();
    final invoiceable = [
      SalesStatus.awaitingPayment, SalesStatus.ready, SalesStatus.loading, SalesStatus.dispatched, SalesStatus.delivered, //
    ].contains(o.status);
    final cancellable = [SalesStatus.draft, SalesStatus.submitted, SalesStatus.awaitingPayment, SalesStatus.ready].contains(o.status) &&
        o.loadingOrders.every((l) => l.status == SalesStatus.cancelled);

    final quiet = <Widget>[
      if (cancellable && _erp.can('sales.approve'))
        SalesQuietAction(label: 'sal.cancelDoc'.tr, icon: PhosphorIconsRegular.xCircle, onPressed: () => _cancel(o)),
    ];
    final main = <Widget>[
      if (o.status == SalesStatus.submitted && _erp.can('sales.approve')) ...[
        VouchFlowButton(label: 'sal.reject'.tr, variant: VfButtonVariant.secondary, onPressed: () => _reject(o)),
        VouchFlowButton(label: 'sal.approve'.tr, icon: PhosphorIconsRegular.sealCheck, onPressed: () => _approve(o)),
      ],
      if (o.status == SalesStatus.draft && _erp.can('sales.order'))
        VouchFlowButton(label: 'sal.submit'.tr, icon: PhosphorIconsRegular.paperPlaneTilt, onPressed: () => _submit(o)),
      if (invoiceable && _erp.can('sales.invoice') && (!invoicedAll || deliveredUninvoiced.isNotEmpty))
        VouchFlowButton(
          label: 'sal.raiseInvoice'.tr,
          icon: PhosphorIconsRegular.receipt,
          variant: VfButtonVariant.secondary,
          onPressed: () => _invoice(o, invoicedAll, deliveredUninvoiced),
        ),
      if (_erp.has('dispatch') &&
          _erp.can('dispatch.load') &&
          [SalesStatus.ready, SalesStatus.loading, SalesStatus.dispatched].contains(o.status) &&
          o.leftToLoad > 0)
        VouchFlowButton(label: 'sal.createLoading'.tr, icon: PhosphorIconsRegular.truck, onPressed: () => _createLoading(o)),
    ];
    // At most two full buttons; anything more becomes a quiet one.
    while (main.length > 2) {
      final b = main.removeAt(0) as VouchFlowButton;
      quiet.add(SalesQuietAction(label: b.label, icon: b.icon, onPressed: b.onPressed!));
    }
    final all = [...quiet, ...main];
    if (all.isEmpty) return null;
    return SalesActionBar(children: all);
  }

  Widget _body(BuildContext context, SalesOrder o) {
    final t = context.vf;
    final currency = _erp.currency;
    final policy = o.policy;
    final customer = o.customer;

    return ErpPageBody(
      onRefresh: _load,
      children: [
        SalesDocHead(
          icon: PhosphorIconsRegular.shoppingCart,
          tint: t.successStrong,
          kind: 'sal.order'.tr,
          number: o.number,
          status: o.status,
          subtitle: [?customer?.name, if (o.orderDate != null) dashDate(o.orderDate)].join(' · '),
          extra: VouchFlowStatusBadge(
            label: o.isPrepayment ? 'sal.prepayment'.tr : 'sal.credit'.tr,
            tag: 'tag-neutral',
            large: true,
          ),
        ),
        if (o.status == SalesStatus.awaitingPayment) ...[
          VouchFlowAlert(
            tone: VfTone.warn,
            icon: PhosphorIconsRegular.hourglassMedium,
            message: 'sal.awaitingPaymentBody'.trParams({
              'paid': salesMoney(o.verifiedPayments),
              'total': salesMoney(o.totals.total),
            }),
          ),
          erpGap,
        ],
        if (o.status == SalesStatus.rejected && o.rejectionReason != null) ...[
          VouchFlowAlert(tone: VfTone.bad, icon: PhosphorIconsRegular.thumbsDown, message: o.rejectionReason!),
          erpGap,
        ],
        if (o.overrideReason != null) ...[
          VouchFlowAlert(
            tone: VfTone.warn,
            icon: PhosphorIconsRegular.warning,
            message: '${'sal.overrodeBy'.trParams({'name': o.overrider ?? '-'})}: ${o.overrideReason}',
          ),
          erpGap,
        ],
        VouchFlowPanel(
          title: 'sal.lines'.tr,
          subtitle: 'sal.fourQuantities'.tr,
          padded: false,
          child: Column(
            children: [
              for (var i = 0; i < o.lines.length; i++) _OrderLineRow(line: o.lines[i], divider: i > 0),
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
                totals: o.totals,
                extra: [if (o.verifiedPayments > 0) ('sal.verifiedPayments'.tr, o.verifiedPayments, false)],
              ),
              const SizedBox(height: 8),
              SalesFact(
                'sal.customer'.tr,
                customer?.name,
                onTap: customer == null || !_erp.can('customers.view')
                    ? null
                    : () => Get.toNamed(Routes.salesCustomer, arguments: customer.id),
              ),
              SalesFact('sal.deliveryAddress'.tr, o.deliveryAddress),
              SalesFact('sal.requiredDate'.tr, o.requiredDate == null ? null : dashDate(o.requiredDate)),
              SalesFact('sal.warehouse'.tr, o.warehouse?.name),
              SalesFact(
                'sal.quotation'.tr,
                o.quotation?.number,
                onTap: o.quotation == null
                    ? null
                    : () => Get.toNamed(Routes.salesQuotation, arguments: o.quotation!.id, preventDuplicates: false),
              ),
              SalesFact('sal.notes'.tr, o.notes),
            ],
          ),
        ),
        if (policy != null) ...[
          erpGap,
          VouchFlowPanel(
            title: 'sal.creditPolicy'.tr,
            subtitle: o.policyIsPreview ? 'sal.policyPreview'.tr : 'sal.policyAtApproval'.tr,
            child: policy.mode == 'prepayment'
                ? Text('sal.policyPrepayment'.tr, style: VfType.small.copyWith(color: t.text2))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SalesFact('sal.creditLimit'.tr, salesMoney(policy.creditLimit)),
                      SalesFact('sal.outstanding'.tr, salesMoney(policy.outstanding)),
                      SalesFact('sal.uninvoicedOrders'.tr, salesMoney(policy.uninvoicedOrders)),
                      SalesFact('sal.thisOrder'.tr, salesMoney(policy.thisOrder)),
                      SalesFact('sal.exposure'.tr, salesMoney(policy.exposure), strong: true),
                      SalesFact('sal.overdueInvoices'.tr, '${policy.overdueInvoices}'),
                      const SizedBox(height: 8),
                      if (policy.passed)
                        Row(
                          children: [
                            Icon(PhosphorIconsRegular.checkCircle, size: 16, color: t.successStrong),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'sal.policyPassed'.tr,
                                style: VfType.small.copyWith(color: t.successStrong, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        )
                      else
                        for (final r in policy.reasons)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(PhosphorIconsRegular.warningCircle, size: 16, color: t.warningStrong),
                                const SizedBox(width: 6),
                                Expanded(child: Text(r, style: VfType.small.copyWith(color: t.text2))),
                              ],
                            ),
                          ),
                    ],
                  ),
          ),
        ],
        if (o.warehouses.isNotEmpty && o.availability.isNotEmpty && !_settled(o)) ...[
          erpGap,
          VouchFlowPanel(
            title: 'sal.stockCheck'.tr,
            subtitle: 'sal.stockCheckSub'.tr,
            padded: false,
            child: Column(
              children: [
                for (var i = 0; i < o.lines.length; i++)
                  VouchFlowListRow(
                    divider: i > 0,
                    title: o.lines[i].productName,
                    subtitle: [
                      for (final w in o.warehouses)
                        '${w.code ?? w.name} ${ErpFmt.qty(o.availability[o.lines[i].productId]?[w.id]?.available ?? 0)}',
                    ].join(' · '),
                  ),
              ],
            ),
          ),
        ],
        erpGap,
        VouchFlowPanel(
          title: 'sal.timeline'.tr,
          child: SalesTimeline(
            steps: [
              ('sal.step.created'.tr, o.createdAt, o.creator),
              ('sal.step.submitted'.tr, o.submittedAt, null),
              ('sal.step.approved'.tr, o.approvedAt, o.approver),
              if (o.isPrepayment) ('sal.step.paymentVerified'.tr, o.paymentVerifiedAt, null),
              for (final lo in o.loadingOrders.where((l) => l.loadedAt != null))
                ('${'sal.step.loaded'.tr} ${lo.number}', lo.loadedAt, null),
            ],
          ),
        ),
        if (o.invoices.isNotEmpty || o.loadingOrders.isNotEmpty) ...[
          erpGap,
          VouchFlowPanel(
            title: 'sal.related'.tr,
            padded: false,
            child: Column(
              children: [
                for (var i = 0; i < o.invoices.length; i++)
                  VouchFlowListRow(
                    divider: i > 0,
                    icon: PhosphorIconsRegular.receipt,
                    iconColor: t.infoStrong,
                    title: o.invoices[i].number,
                    subtitle: [
                      'sal.invoice'.tr,
                      if (o.invoices[i].invoiceDate != null) dashDate(o.invoices[i].invoiceDate),
                      '$currency ${ErpFmt.amount(o.invoices[i].totals.total)}',
                    ].join(' · '),
                    trailing: SalesStatusBadge(o.invoices[i].status),
                    onTap: () async {
                      await Get.toNamed(Routes.salesInvoice, arguments: o.invoices[i].id);
                      _load();
                    },
                  ),
                for (var i = 0; i < o.loadingOrders.length; i++)
                  VouchFlowListRow(
                    divider: i > 0 || o.invoices.isNotEmpty,
                    icon: PhosphorIconsRegular.truck,
                    iconColor: t.primary,
                    title: o.loadingOrders[i].number,
                    subtitle: [
                      'sal.loadingOrder'.tr,
                      ?o.loadingOrders[i].warehouse?.name,
                      ?o.loadingOrders[i].vehicleNumber,
                    ].join(' · '),
                    trailing: SalesStatusBadge(o.loadingOrders[i].status),
                    onTap: !_erp.has('dispatch') || !_erp.can('dispatch.view')
                        ? null
                        : () async {
                            await Get.toNamed(Routes.dispatchLoading, arguments: o.loadingOrders[i].id);
                            _load();
                          },
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  bool _settled(SalesOrder o) =>
      [SalesStatus.delivered, SalesStatus.cancelled, SalesStatus.rejected].contains(o.status);
}

/// An order line: the product, price and total, and the four quantities as
/// a quiet line of figures.
class _OrderLineRow extends StatelessWidget {
  const _OrderLineRow({required this.line, required this.divider});

  final SalesLine line;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final l = line;
    final unit = l.unitCode == null ? '' : ' ${l.unitCode}';
    String q(double? v) => v == null ? '-' : ErpFmt.qty(v);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: divider
          ? BoxDecoration(border: Border(top: BorderSide(color: t.isDark ? t.glassBorder : t.border)))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.productName, style: VfType.bodyStrong.copyWith(color: t.text, height: 1.3)),
                    Text(
                      [
                        '${ErpFmt.qty(l.quantity)}$unit × ${ErpFmt.amount(l.unitPrice)}',
                        if (l.discountPercent > 0) '-${ErpFmt.qty(l.discountPercent)}%',
                        '${'sal.vat'.tr} ${ErpFmt.qty(l.taxRate)}%',
                      ].join(' · '),
                      style: VfType.meta.copyWith(color: t.muted, fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              MoneyText(l.lineTotal, style: VfType.small.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final (label, value) in [
                ('sal.qtyApproved'.tr, q(l.quantityApproved)),
                ('sal.qtyLoaded'.tr, q(l.quantityLoaded)),
                ('sal.qtyReceived'.tr, q(l.quantityReceived)),
                ('sal.qtyInvoiced'.tr, q(l.quantityInvoiced)),
              ])
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: VfType.meta.copyWith(color: t.muted, fontSize: 11.5)),
                      Text(
                        value,
                        style: VfType.small.copyWith(
                          color: t.text,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
