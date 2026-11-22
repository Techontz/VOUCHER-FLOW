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

/// One quotation (the web's /erp/sales/quotations/[id]): its lines and
/// totals; Mark as sent, Declined by the customer, Cancel, and Convert to
/// an order. Opened with the quotation id as the argument.
class SalesQuotationPage extends StatefulWidget {
  const SalesQuotationPage({super.key, this.quotationId});

  final int? quotationId;

  @override
  State<SalesQuotationPage> createState() => _SalesQuotationPageState();
}

class _SalesQuotationPageState extends State<SalesQuotationPage> {
  late final int _id = widget.quotationId ?? (Get.arguments as int);
  final _repo = SalesRepository.to;
  final _erp = ErpService.to;
  SalesQuotation? _quote;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final q = await _repo.quotation(_id);
      if (mounted) setState(() { _quote = q; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'state.offline'.tr);
    }
  }

  List<VfSummaryRow> _summary(SalesQuotation q) => [
    VfSummaryRow('sal.customer'.tr, q.customer?.name ?? '-'),
    VfSummaryRow('sal.total'.tr, salesMoney(q.totals.total)),
  ];

  Future<void> _status(SalesQuotation q, String action) async {
    final (icon, title, label, danger) = switch (action) {
      'send' => (PhosphorIconsRegular.paperPlaneTilt, 'sal.sendQ', 'sal.markSent', false),
      'reject' => (PhosphorIconsRegular.thumbsDown, 'sal.declinedQ', 'sal.markDeclined', true),
      _ => (PhosphorIconsRegular.xCircle, 'sal.cancelQuotationQ', 'sal.cancelDoc', true),
    };
    final m = await confirmSalesAction(
      context,
      icon: icon,
      tone: danger ? VfTone.warn : VfTone.info,
      title: title.trParams({'number': q.number}),
      summary: _summary(q),
      confirmLabel: label.tr,
      backLabel: danger ? 'sal.keep'.tr : null,
      danger: danger,
      run: (_) => _repo.quotationAction(q.id, action),
    );
    if (m == null) return;
    showToast(m.isEmpty ? 'sal.done'.tr : m);
    _load();
  }

  Future<void> _convert(SalesQuotation q) async {
    SalesOrder? order;
    final m = await confirmSalesAction(
      context,
      icon: PhosphorIconsRegular.shoppingCart,
      title: 'sal.convertQ'.trParams({'number': q.number}),
      subtitle: 'sal.convertSub'.tr,
      summary: _summary(q),
      confirmLabel: 'sal.convert'.tr,
      run: (_) async {
        order = await _repo.convert(q.id);
        return 'sal.becameOrder'.trParams({'number': order!.number});
      },
    );
    if (m == null) return;
    showToast(m);
    if (order != null) {
      await Get.offNamed(Routes.salesOrder, arguments: order!.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _quote;
    return VouchFlowPushedScaffold(
      title: q?.number ?? 'sal.quotation'.tr,
      body: q == null
          ? (_error == null
                ? const VfLoadingView()
                : ErpPageBody(children: [VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)]))
          : _body(context, q),
      bottomBar: q == null ? null : _actions(q),
    );
  }

  Widget? _actions(SalesQuotation q) {
    final live = q.status == SalesStatus.draft || q.status == SalesStatus.sent;
    if (!live || !_erp.can('sales.quote')) return null;
    final quiet = <Widget>[
      SalesQuietAction(label: 'sal.cancelDoc'.tr, icon: PhosphorIconsRegular.xCircle, onPressed: () => _status(q, 'cancel')),
      if (q.status == SalesStatus.sent || q.status == SalesStatus.draft)
        SalesQuietAction(label: 'sal.markDeclined'.tr, icon: PhosphorIconsRegular.thumbsDown, onPressed: () => _status(q, 'reject')),
    ];
    final main = <Widget>[
      if (q.status == SalesStatus.draft)
        VouchFlowButton(
          label: 'sal.markSent'.tr,
          icon: PhosphorIconsRegular.paperPlaneTilt,
          variant: VfButtonVariant.secondary,
          onPressed: () => _status(q, 'send'),
        ),
      if (_erp.can('sales.order') && !q.isExpired)
        VouchFlowButton(label: 'sal.convert'.tr, icon: PhosphorIconsRegular.shoppingCart, onPressed: () => _convert(q)),
    ];
    return SalesActionBar(children: [...quiet, ...main]);
  }

  Widget _body(BuildContext context, SalesQuotation q) {
    final t = context.vf;
    return ErpPageBody(
      onRefresh: _load,
      children: [
        SalesDocHead(
          icon: PhosphorIconsRegular.notePencil,
          tint: t.primary,
          kind: 'sal.quotation'.tr,
          number: q.number,
          status: q.status,
          subtitle: [?q.customer?.name, if (q.quoteDate != null) dashDate(q.quoteDate)].join(' · '),
          extra: q.isExpired && (q.status == SalesStatus.draft || q.status == SalesStatus.sent)
              ? VouchFlowStatusBadge(label: 'sal.expired'.tr, tag: 'tag-warn', large: true)
              : null,
        ),
        VouchFlowPanel(
          title: 'sal.lines'.tr,
          padded: false,
          child: Column(
            children: [
              for (var n = 0; n < q.lines.length; n++)
                VouchFlowListRow(
                  divider: n > 0,
                  title: q.lines[n].productName,
                  titleMaxLines: 2,
                  subtitle: [
                    '${ErpFmt.qty(q.lines[n].quantity)}${q.lines[n].unitCode == null ? '' : ' ${q.lines[n].unitCode}'} × ${ErpFmt.amount(q.lines[n].unitPrice)}',
                    if (q.lines[n].discountPercent > 0) '-${ErpFmt.qty(q.lines[n].discountPercent)}%',
                  ].join(' · '),
                  trailing: MoneyText(q.lines[n].lineTotal, style: VfType.small.copyWith(fontWeight: FontWeight.w600)),
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
              SalesTotalsBlock(totals: q.totals),
              const SizedBox(height: 8),
              SalesFact(
                'sal.customer'.tr,
                q.customer?.name,
                onTap: q.customer == null || !_erp.can('customers.view')
                    ? null
                    : () => Get.toNamed(Routes.salesCustomer, arguments: q.customer!.id),
              ),
              SalesFact('sal.validUntilLabel'.tr, q.validUntil == null ? null : dashDate(q.validUntil)),
              SalesFact(
                'sal.order'.tr,
                q.order?.number,
                onTap: q.order == null ? null : () => Get.toNamed(Routes.salesOrder, arguments: q.order!.id),
              ),
              SalesFact('sal.prepared'.tr, [q.creator ?? '-', if (q.createdAt != null) dashDateTime(q.createdAt)].join(' · ')),
              SalesFact('sal.notes'.tr, q.notes),
            ],
          ),
        ),
      ],
    );
  }
}
