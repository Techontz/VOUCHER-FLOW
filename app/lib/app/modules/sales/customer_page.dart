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
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;
import '../erp/erp_widgets.dart';
import 'sales_widgets.dart';

/// One customer: who they are and their terms, what they owe by age, and
/// their statement for a period (the web's /erp/sales/statement), with a
/// new order and a payment one tap away. Opened with the customer id.
class SalesCustomerPage extends StatefulWidget {
  const SalesCustomerPage({super.key, this.customerId});

  final int? customerId;

  @override
  State<SalesCustomerPage> createState() => _SalesCustomerPageState();
}

class _SalesCustomerPageState extends State<SalesCustomerPage> {
  late final int _id = widget.customerId ?? (Get.arguments as int);
  final _repo = SalesRepository.to;
  final _erp = ErpService.to;
  SalesCustomer? _customer;
  CustomerStatement? _statement;
  String? _error, _statementError;

  /// The statement's span in months.
  int _months = 3;

  bool get _seesSales => _erp.has('sales') && _erp.can('sales.view');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await _repo.customer(_id);
      if (mounted) setState(() { _customer = c; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return;
    } catch (_) {
      if (mounted) setState(() => _error = 'state.offline'.tr);
      return;
    }
    await _loadStatement();
  }

  Future<void> _loadStatement() async {
    if (!_seesSales) return;
    final now = DateTime.now();
    try {
      final s = await _repo.statement(_id, from: DateTime(now.year, now.month - _months + 1), to: now);
      if (mounted) setState(() { _statement = s; _statementError = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _statementError = e.message);
    } catch (_) {
      if (mounted) setState(() => _statementError = 'state.offline'.tr);
    }
  }

  Future<void> _push(String route, Object arguments) async {
    await Get.toNamed(route, arguments: arguments);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = _customer;
    return VouchFlowPushedScaffold(
      title: c?.name ?? 'sal.customer'.tr,
      body: c == null
          ? (_error == null
                ? const VfLoadingView()
                : ErpPageBody(children: [VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)]))
          : _body(context, c),
      bottomBar: c == null ? null : _actions(c),
    );
  }

  Widget? _actions(SalesCustomer c) {
    final buttons = <Widget>[
      if (_erp.can('sales.receipt') && (_statement?.closingBalance ?? 0) > 0)
        VouchFlowButton(
          label: 'sal.receivePayment'.tr,
          icon: PhosphorIconsRegular.handCoins,
          variant: VfButtonVariant.secondary,
          onPressed: () => _push(Routes.salesReceiptNew, {'customerId': c.id}),
        ),
      if (_erp.can('sales.order') && c.isActive)
        VouchFlowButton(
          label: 'sal.newOrder'.tr,
          icon: PhosphorIconsRegular.shoppingCart,
          onPressed: () => _push(Routes.salesDocumentNew, {'quotation': false, 'customerId': c.id}),
        ),
    ];
    return buttons.isEmpty ? null : SalesActionBar(children: buttons);
  }

  Widget _body(BuildContext context, SalesCustomer c) {
    final t = context.vf;
    final s = _statement;
    return ErpPageBody(
      onRefresh: _load,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 18),
          child: Row(
            children: [
              VouchFlowAvatar(
                initials: c.name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join().toUpperCase(),
                size: 52,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name, style: VfType.pageTitle.copyWith(color: t.text, fontSize: 19, letterSpacing: -.3)),
                    const SizedBox(height: 2),
                    Text([c.code, ?c.group, ?c.city].join(' · '), style: VfType.small.copyWith(color: t.text2)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        VouchFlowStatusBadge(
                          label: c.requiresPrepayment
                              ? 'sal.prepayment'.tr
                              : 'sal.creditDays'.trParams({'n': '${c.paymentTermsDays}'}),
                          tag: c.requiresPrepayment ? 'tag-info' : 'tag-neutral',
                          large: true,
                        ),
                        if (!c.isActive) VouchFlowStatusBadge(label: 'sal.inactive'.tr, tag: 'tag-warn', large: true),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_seesSales) ...[
          if (s == null && _statementError == null)
            const VfLoadingView(inline: true)
          else if (s == null)
            VouchFlowErrorState(message: _statementError!, onRetry: _loadStatement, retryLabel: 'action.retry'.tr)
          else ...[
            VouchFlowFigureCard(
              label: 'sal.balanceDue'.tr,
              value: salesMoney(s.aged.total),
              hint: s.aged.overdue > 0
                  ? 'sal.overdueAmount'.trParams({'amount': salesMoney(s.aged.overdue)})
                  : 'sal.nothingOverdue'.tr,
              icon: PhosphorIconsRegular.scales,
              tone: s.aged.overdue > 0 ? VfTone.bad : (s.aged.total > 0 ? VfTone.info : VfTone.ok),
            ),
            erpGap,
            VouchFlowPanel(
              title: 'sal.aged'.tr,
              child: Column(
                children: [
                  for (final (key, value) in s.aged.buckets)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Expanded(child: Text('sal.age.$key'.tr, style: VfType.small.copyWith(color: t.text2))),
                          MoneyText(
                            value,
                            style: VfType.small.copyWith(fontWeight: FontWeight.w600),
                            color: value > 0 && key != 'current' ? t.dangerStrong : (value > 0 ? t.text : t.muted),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            erpGap,
            VouchFlowPanel(
              title: 'sal.statement'.tr,
              subtitle: s.from == null ? null : '${dashDate(s.from)} - ${dashDate(s.to)}',
              padded: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final m in const [3, 6, 12])
                          VouchFlowFilterChip(
                            label: 'sal.months'.trParams({'n': '$m'}),
                            selected: _months == m,
                            onTap: () {
                              setState(() {
                                _months = m;
                                _statement = null;
                              });
                              _loadStatement();
                            },
                          ),
                      ],
                    ),
                  ),
                  VouchFlowListRow(
                    title: 'sal.openingBalance'.tr,
                    trailing: MoneyText(s.openingBalance, style: VfType.small.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  for (final l in s.lines)
                    VouchFlowListRow(
                      icon: switch (l.type) {
                        'invoice' => PhosphorIconsRegular.receipt,
                        'receipt' => PhosphorIconsRegular.handCoins,
                        _ => PhosphorIconsRegular.arrowUUpLeft,
                      },
                      iconColor: l.type == 'invoice' ? t.infoStrong : t.successStrong,
                      title: l.number,
                      subtitle: [if (l.date != null) dashDate(l.date), ?l.detail].join(' · '),
                      trailing: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            l.debit > 0 ? '+${ErpFmt.amount(l.debit)}' : '-${ErpFmt.amount(l.credit)}',
                            style: VfType.small.copyWith(
                              fontWeight: FontWeight.w600,
                              color: l.debit > 0 ? t.text : t.successStrong,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          Text(
                            ErpFmt.amount(l.balance),
                            style: VfType.meta.copyWith(color: t.muted, fontFeatures: const [FontFeature.tabularFigures()]),
                          ),
                        ],
                      ),
                      onTap: switch (l.type) {
                        'invoice' => () => Get.toNamed(Routes.salesInvoice, arguments: l.id),
                        'receipt' => () => Get.toNamed(Routes.salesReceipt, arguments: l.id),
                        _ => null,
                      },
                    ),
                  VouchFlowListRow(
                    title: 'sal.closingBalance'.tr,
                    trailing: MoneyText(s.closingBalance, style: VfType.bodyStrong.copyWith(fontSize: 15)),
                  ),
                ],
              ),
            ),
            erpGap,
          ],
        ],
        VouchFlowPanel(
          title: 'sal.details'.tr,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SalesFact('sal.contact'.tr, c.contactPerson),
              SalesFact('sal.phone'.tr, c.phone),
              SalesFact('sal.email'.tr, c.email),
              SalesFact('sal.address'.tr, c.place),
              SalesFact('sal.tin'.tr, c.tin),
              SalesFact('sal.creditLimit'.tr, c.requiresPrepayment ? null : salesMoney(c.creditLimit)),
              SalesFact('sal.paymentTerms'.tr, c.requiresPrepayment ? 'sal.prepayment'.tr : 'sal.creditDays'.trParams({'n': '${c.paymentTermsDays}'})),
              SalesFact('sal.priceList'.tr, c.priceList),
            ],
          ),
        ),
      ],
    );
  }
}
