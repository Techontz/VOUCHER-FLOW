import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/finance_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/finance_repository.dart';
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;
import '../erp/erp_widgets.dart';
import 'fin_widgets.dart';

/// The reports a phone can read (the web's /erp/finance/statements and the
/// trial balance): profit and loss for a period against the one before,
/// the balance sheet today, budget against actual for the year, and the
/// trial balance, each as a two-column statement rather than a wide table.
/// Which ones show follows the person's permissions.
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

enum _Report { pl, bs, budget, tb }

enum _Range { month, lastMonth, year }

class _ReportsPageState extends State<ReportsPage> {
  final _repo = FinanceRepository.to;
  _Report? _report;
  _Range _range = _Range.month;
  Object? _data;
  String? _error;
  bool _loading = true;
  int _generation = 0;

  List<_Report> get _available {
    final erp = ErpService.to;
    return [
      if (erp.can('finance.statements')) ...[_Report.pl, _Report.bs, _Report.budget],
      if (erp.can('accounting.view')) _Report.tb,
    ];
  }

  Future<void> _load() async {
    final report = _report ??= _available.firstOrNull;
    if (report == null) return;
    final generation = ++_generation;
    setState(() { _loading = _data == null || _data.runtimeType != _typeOf(report); _error = null; });
    final now = DateTime.now();
    try {
      final Object data = switch (report) {
        _Report.pl => await switch (_range) {
          _Range.month => _repo.profitAndLoss(from: DateTime(now.year, now.month), to: now),
          _Range.lastMonth => _repo.profitAndLoss(from: DateTime(now.year, now.month - 1), to: DateTime(now.year, now.month, 0)),
          _Range.year => _repo.profitAndLoss(from: DateTime(now.year), to: now),
        },
        _Report.bs => await _repo.balanceSheet(),
        _Report.budget => await _repo.budgetVsActual(year: now.year),
        _Report.tb => await _repo.trialBalance(),
      };
      if (mounted && generation == _generation) setState(() { _data = data; _loading = false; });
    } on ApiException catch (e) {
      if (mounted && generation == _generation) setState(() { _error = e.message; _data = null; _loading = false; });
    } catch (_) {
      if (mounted && generation == _generation) setState(() { _error = 'state.offline'.tr; _data = null; _loading = false; });
    }
  }

  static Type _typeOf(_Report r) => switch (r) {
    _Report.pl => ProfitAndLoss,
    _Report.bs => BalanceSheet,
    _Report.budget => BudgetVsActual,
    _Report.tb => TrialBalance,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) => ErpGate(module: 'accounting', builder: _page);

  Widget _page(BuildContext context) {
    final reports = _available;
    if (reports.isEmpty) return ErpEmpty(icon: PhosphorIconsRegular.lockSimple, title: 'erp.noAccess'.tr);
    final report = _report ?? reports.first;
    final data = _data;
    return ErpPageBody(
      onRefresh: _load,
      children: [
        ErpPageTitle('fin.nav.reports'.tr),
        if (reports.length > 1) ...[
          VouchFlowTabs(
            labels: [for (final r in reports) 'fin.report.${r.name}'.tr],
            current: reports.indexOf(report),
            onChanged: (i) {
              setState(() { _report = reports[i]; _data = null; });
              _load();
            },
          ),
          const SizedBox(height: 14),
        ],
        if (report == _Report.pl) ...[
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final r in _Range.values) ...[
                  VouchFlowFilterChip(
                    label: 'fin.range.${r.name}'.tr,
                    selected: _range == r,
                    onTap: () {
                      setState(() => _range = r);
                      _load();
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (_loading)
          const VfLoadingView(inline: true)
        else if (_error != null)
          VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)
        else if (data is ProfitAndLoss)
          ..._profitAndLoss(context, data)
        else if (data is BalanceSheet)
          ..._balanceSheet(context, data)
        else if (data is BudgetVsActual)
          ..._budget(context, data)
        else if (data is TrialBalance)
          ..._trialBalance(context, data),
        const SizedBox(height: 8),
      ],
    );
  }

  List<Widget> _profitAndLoss(BuildContext context, ProfitAndLoss p) {
    final t = context.vf;
    String prior(double? v) => finMoney(v ?? 0);
    Widget section(String key, double total, double priorTotal) {
      final rows = p.section(key);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FinSectionLabel('fin.pl.$key'.tr, first: key == 'income'),
          for (var i = 0; i < rows.length; i++)
            FinAmountRow(
              divider: i > 0,
              label: rows[i].name,
              code: rows[i].code,
              amount: finMoney(rows[i].amount),
              secondary: prior(rows[i].prior),
            ),
          FinAmountRow(label: 'fin.totalOf'.trParams({'what': 'fin.pl.$key'.tr.toLowerCase()}), amount: finMoney(total), secondary: prior(priorTotal), weight: FinRowWeight.subtotal),
        ],
      );
    }

    final net = p.totals.netProfit;
    return [
      Text(
        'fin.comparedWith'.trParams({
          'from': dashDate(p.from),
          'to': dashDate(p.to),
          'pfrom': dashDate(p.priorFrom),
          'pto': dashDate(p.priorTo),
        }),
        style: VfType.meta.copyWith(color: t.muted),
      ),
      const SizedBox(height: 10),
      VouchFlowPanel(
        padded: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            section('income', p.totals.income, p.prior.income),
            section('cost_of_sales', p.totals.costOfSales, p.prior.costOfSales),
            FinAmountRow(label: 'fin.pl.gross_profit'.tr, amount: finMoney(p.totals.grossProfit), secondary: prior(p.prior.grossProfit), weight: FinRowWeight.total),
            section('operating_expenses', p.totals.operatingExpenses, p.prior.operatingExpenses),
            FinAmountRow(
              label: 'fin.pl.net_profit'.tr,
              amount: finMoney(net),
              secondary: prior(p.prior.netProfit),
              weight: FinRowWeight.total,
              tone: net < 0 ? t.dangerStrong : t.successStrong,
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _balanceSheet(BuildContext context, BalanceSheet b) {
    final t = context.vf;
    Widget section(String key) {
      final rows = b.section(key);
      if (rows.isEmpty && (b.totals[key] ?? 0) == 0) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FinSectionLabel('fin.bs.$key'.tr),
          for (var i = 0; i < rows.length; i++)
            FinAmountRow(divider: i > 0, label: rows[i].name, code: rows[i].code, amount: finMoney(rows[i].amount)),
          if (key == 'equity')
            FinAmountRow(label: 'fin.bs.currentEarnings'.tr, amount: finMoney(b.currentEarnings), tone: b.currentEarnings < 0 ? t.dangerStrong : null),
          FinAmountRow(label: 'fin.totalOf'.trParams({'what': 'fin.bs.$key'.tr.toLowerCase()}), amount: finMoney(b.totals[key] ?? 0), weight: FinRowWeight.subtotal),
        ],
      );
    }

    return [
      Row(
        children: [
          Expanded(child: Text('fin.asOf'.trParams({'date': dashDate(b.asOf)}), style: VfType.meta.copyWith(color: t.muted))),
          FinStatusBadge(b.balanced ? 'balanced' : 'unbalanced'),
        ],
      ),
      const SizedBox(height: 10),
      VouchFlowPanel(
        title: 'fin.bs.assets'.tr,
        padded: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            section('current_assets'),
            section('non_current_assets'),
            FinAmountRow(label: 'fin.bs.totalAssets'.tr, amount: finMoney(b.totals['assets'] ?? 0), weight: FinRowWeight.total),
          ],
        ),
      ),
      erpGap,
      VouchFlowPanel(
        title: 'fin.bs.liabilitiesEquity'.tr,
        padded: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            section('current_liabilities'),
            section('non_current_liabilities'),
            section('equity'),
            FinAmountRow(label: 'fin.bs.totalLiabilitiesEquity'.tr, amount: finMoney(b.totals['liabilities_and_equity'] ?? 0), weight: FinRowWeight.total),
          ],
        ),
      ),
    ];
  }

  List<Widget> _budget(BuildContext context, BudgetVsActual b) {
    final t = context.vf;
    if (!b.hasBudget) {
      return [VouchFlowEmptyState(icon: PhosphorIconsRegular.target, title: 'fin.noBudget'.trParams({'year': '${b.year}'}), body: 'fin.noBudgetBody'.tr)];
    }
    Widget row(BudgetRow r, bool divider) {
      final used = r.usedPercent;
      final over = used != null && used > 100 && r.type == 'expense';
      return Container(
        decoration: BoxDecoration(border: divider ? Border(top: BorderSide(color: t.border.withValues(alpha: .7), width: .6)) : null),
        padding: const EdgeInsets.fromLTRB(16, 11, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(r.name, style: VfType.small.copyWith(color: t.text, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 10),
                Text(
                  used == null ? '-' : '${used.toStringAsFixed(used < 10 ? 1 : 0)}%',
                  style: VfType.small.copyWith(color: over ? t.dangerStrong : t.text2, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FinProgress(value: (used ?? 0) / 100, color: over ? t.dangerStrong : (r.type == 'income' ? t.successStrong : t.primary), height: 5),
            const SizedBox(height: 6),
            Text(
              'fin.actualOfBudget'.trParams({'actual': finCompact(r.actual), 'budget': finCompact(r.budget)}),
              style: VfType.meta.copyWith(color: t.muted, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ],
        ),
      );
    }

    final income = b.rows.where((r) => r.type == 'income' && (r.budget != 0 || r.actual != 0)).toList();
    final expense = b.rows.where((r) => r.type != 'income' && (r.budget != 0 || r.actual != 0)).toList();
    return [
      Text('fin.budgetYear'.trParams({'year': '${b.year}'}), style: VfType.meta.copyWith(color: t.muted)),
      const SizedBox(height: 10),
      VouchFlowPanel(
        padded: false,
        child: Column(
          children: [
            FinAmountRow(label: 'fin.budgetIncome'.tr, amount: finMoney(b.totals['income_actual']), secondary: 'fin.ofAmount'.trParams({'amount': finMoney(b.totals['income_budget'])}), divider: false),
            FinAmountRow(label: 'fin.budgetExpense'.tr, amount: finMoney(b.totals['expense_actual']), secondary: 'fin.ofAmount'.trParams({'amount': finMoney(b.totals['expense_budget'])})),
            FinAmountRow(
              label: 'fin.budgetNet'.tr,
              amount: finMoney(b.totals['net_actual']),
              secondary: 'fin.ofAmount'.trParams({'amount': finMoney(b.totals['net_budget'])}),
              weight: FinRowWeight.total,
              tone: (b.totals['net_actual'] ?? 0) < 0 ? t.dangerStrong : null,
            ),
          ],
        ),
      ),
      erpGap,
      VouchFlowPanel(
        title: 'fin.acct.income'.tr,
        padded: false,
        child: income.isEmpty ? FinPanelEmpty('fin.nothingHere'.tr) : Column(children: [for (var i = 0; i < income.length; i++) row(income[i], i > 0)]),
      ),
      erpGap,
      VouchFlowPanel(
        title: 'fin.acct.expense'.tr,
        padded: false,
        child: expense.isEmpty ? FinPanelEmpty('fin.nothingHere'.tr) : Column(children: [for (var i = 0; i < expense.length; i++) row(expense[i], i > 0)]),
      ),
    ];
  }

  List<Widget> _trialBalance(BuildContext context, TrialBalance tb) {
    final t = context.vf;
    final rows = tb.rows.where((r) => r.debit != 0 || r.credit != 0).toList();
    return [
      Row(
        children: [
          Expanded(child: Text('fin.tbSub'.tr, style: VfType.meta.copyWith(color: t.muted))),
          FinStatusBadge(tb.balanced ? 'balanced' : 'unbalanced'),
        ],
      ),
      const SizedBox(height: 10),
      VouchFlowPanel(
        padded: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(child: Text('fin.account'.tr.toUpperCase(), style: VfType.eyebrow.copyWith(color: t.muted, fontSize: 11))),
                  Text('fin.balance'.tr.toUpperCase(), style: VfType.eyebrow.copyWith(color: t.muted, fontSize: 11)),
                ],
              ),
            ),
            for (final r in rows)
              FinAmountRow(
                label: r.name,
                code: '${r.code} · ${'fin.acct.${r.type}'.tr}',
                amount: r.balance >= 0 ? '${'fin.dr'.tr} ${ErpFmtX.whole(r.balance)}' : '${'fin.cr'.tr} ${ErpFmtX.whole(-r.balance)}',
                secondary: '${ErpFmtX.whole(r.debit)} / ${ErpFmtX.whole(r.credit)}',
              ),
            FinAmountRow(label: 'fin.totalDebit'.tr, amount: finMoney(tb.totalDebit), weight: FinRowWeight.total),
            FinAmountRow(label: 'fin.totalCredit'.tr, amount: finMoney(tb.totalCredit), weight: FinRowWeight.total, divider: false),
          ],
        ),
      ),
    ];
  }
}

/// Whole figures for a dense column.
abstract class ErpFmtX {
  static String whole(double v) => finMoney(v).split(' ').last;
}
