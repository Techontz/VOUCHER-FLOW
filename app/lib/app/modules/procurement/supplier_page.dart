import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/finance_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/procurement_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;
import '../erp/erp_widgets.dart';
import '../finance/fin_widgets.dart';
import '../inventory/inventory_widgets.dart' show ErpFact;

/// One supplier: who to call, where to pay, and their statement for a
/// period, opening balance to closing, each invoice and payment a tap from
/// its record (the web's /erp/suppliers and /erp/procurement/statement).
class SupplierPage extends StatefulWidget {
  const SupplierPage({super.key, this.supplierId});

  final int? supplierId;

  @override
  State<SupplierPage> createState() => _SupplierPageState();
}

/// The statement's period choices: the API's default (the last 90 days),
/// this year, or last month.
enum _Span { recent, year, lastMonth }

class _SupplierPageState extends State<SupplierPage> {
  late final int _id = widget.supplierId ?? finArgId();
  final _repo = ProcurementRepository.to;

  Supplier? _supplier;
  SupplierStatement? _statement;
  String? _error, _statementError;
  bool _statementLoading = true;
  _Span _span = _Span.recent;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await _repo.supplier(_id);
      if (mounted) setState(() { _supplier = s; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'state.offline'.tr);
    }
    await _loadStatement();
  }

  Future<void> _loadStatement() async {
    if (!ErpService.to.can('procurement.view')) {
      setState(() => _statementLoading = false);
      return;
    }
    setState(() { _statementLoading = true; _statementError = null; });
    final now = DateTime.now();
    final (from, to) = switch (_span) {
      _Span.recent => (null, null),
      _Span.year => (DateTime(now.year), now),
      _Span.lastMonth => (DateTime(now.year, now.month - 1), DateTime(now.year, now.month, 0)),
    };
    try {
      final st = await _repo.statement(_id, from: from, to: to);
      if (mounted) setState(() { _statement = st; _statementLoading = false; });
    } on ApiException catch (e) {
      if (mounted) setState(() { _statementError = e.message; _statementLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _statementError = 'state.offline'.tr; _statementLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _supplier ?? _statement?.supplier;
    return VouchFlowPushedScaffold(
      title: s?.name ?? 'prc.supplier'.tr,
      body: s == null
          ? (_error == null
                ? const VfLoadingView()
                : ErpPageBody(children: [VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)]))
          : ErpPageBody(onRefresh: _load, children: _body(context, s)),
    );
  }

  List<Widget> _body(BuildContext context, Supplier s) {
    return [
      FinHead(
        icon: PhosphorIconsRegular.truck,
        kicker: 'prc.supplier'.tr,
        title: s.name,
        subtitle: [s.code, ?s.category, ?s.city].join(' · '),
        badges: [if (!s.isActive) VouchFlowStatusBadge(label: 'prc.inactive'.tr, large: true)],
      ),
      if (ErpService.to.can('procurement.view')) ...[
        VouchFlowPanel(
          title: 'prc.statement'.tr,
          subtitle: _statement == null || _statement!.from == null
              ? null
              : '${dashDate(_statement!.from)} - ${dashDate(_statement!.to)}',
          padded: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 44,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final span in _Span.values) ...[
                      VouchFlowFilterChip(
                        label: 'prc.span.${span.name}'.tr,
                        selected: _span == span,
                        onTap: () {
                          setState(() => _span = span);
                          _loadStatement();
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              ..._statementRows(context),
            ],
          ),
        ),
        erpGap,
      ],
      VouchFlowPanel(
        title: 'prc.contact'.tr,
        child: Column(
          children: [
            if (s.contactPerson != null) ErpFact('prc.contactPerson'.tr, s.contactPerson!),
            if (s.phone != null) ErpFact('prc.phone'.tr, s.phone!),
            if (s.email != null) ErpFact('prc.email'.tr, s.email!),
            if (s.address != null || s.city != null) ErpFact('prc.address'.tr, [?s.address, ?s.city].join(', ')),
            if (s.tin != null) ErpFact('prc.tin'.tr, s.tin!),
            ErpFact('prc.terms'.tr, s.paymentTermsDays == null ? '-' : 'prc.termsDays'.trParams({'n': '${s.paymentTermsDays}'})),
          ],
        ),
      ),
      if (s.bankName != null || s.bankAccountNumber != null) ...[
        erpGap,
        VouchFlowPanel(
          title: 'prc.bankDetails'.tr,
          child: Column(
            children: [
              if (s.bankName != null) ErpFact('prc.bank'.tr, s.bankName!),
              if (s.bankAccountName != null) ErpFact('prc.accountName'.tr, s.bankAccountName!),
              if (s.bankAccountNumber != null) ErpFact('prc.accountNumber'.tr, s.bankAccountNumber!),
            ],
          ),
        ),
      ],
    ];
  }

  List<Widget> _statementRows(BuildContext context) {
    final t = context.vf;
    if (_statementLoading) return const [Padding(padding: EdgeInsets.all(20), child: VfLoader(size: 32))];
    if (_statementError != null) return [FinPanelEmpty(_statementError!)];
    final st = _statement;
    if (st == null) return const [];
    return [
      FinAmountRow(label: 'prc.openingBalance'.tr, amount: finMoney(st.openingBalance), weight: FinRowWeight.subtotal),
      if (st.entries.isEmpty) FinPanelEmpty('prc.noActivity'.tr),
      for (final e in st.entries)
        VouchFlowListRow(
          icon: e.type == 'payment' ? PhosphorIconsRegular.handCoins : PhosphorIconsRegular.receipt,
          iconColor: e.type == 'payment' ? t.successStrong : t.warningStrong,
          title: e.reference ?? e.number,
          subtitle: [
            if (e.date != null) dashDate(e.date),
            e.type == 'payment' ? 'prc.payment'.tr : 'prc.invoice'.tr,
            'prc.balanceAmount'.trParams({'amount': finMoney(e.balance)}),
          ].join(' · '),
          trailing: FinTrailing(
            amount: e.type == 'payment' ? '-${finMoney(e.debit)}' : '+${finMoney(e.credit)}',
            tone: e.type == 'payment' ? t.successStrong : null,
          ),
          onTap: () => Get.toNamed(e.type == 'payment' ? Routes.prcPayment : Routes.prcInvoice, arguments: e.id),
        ),
      FinAmountRow(label: 'prc.invoiced'.tr, amount: finMoney(st.totalInvoiced)),
      FinAmountRow(label: 'prc.paid'.tr, amount: finMoney(st.totalPaid)),
      FinAmountRow(label: 'prc.closingBalance'.tr, amount: finMoney(st.closingBalance), weight: FinRowWeight.total),
    ];
  }
}
