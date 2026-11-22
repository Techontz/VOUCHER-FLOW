import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/hr_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/hr_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;
import '../erp/erp_widgets.dart';
import '../fleet/fleet_widgets.dart' show DetailHead, FactLine;
import 'hr_widgets.dart';

/// One payroll run, read only: its totals, the statutory deductions and
/// employer cost, and every payslip in it. Opened with the run's id.
class PayrollRunPage extends StatefulWidget {
  const PayrollRunPage({super.key, this.runId});

  final int? runId;

  @override
  State<PayrollRunPage> createState() => _PayrollRunPageState();
}

class _PayrollRunPageState extends State<PayrollRunPage> {
  late final int _id = widget.runId ?? (Get.arguments as int);
  HrPayrollRun? _run;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await HrRepository.to.payrollRun(_id);
      if (mounted) setState(() { _run = r; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'state.offline'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _run;
    return VouchFlowPushedScaffold(
      title: r == null ? 'hr.nav.payroll'.tr : monthLabel(r.period),
      body: ErpGate(
        module: 'hr',
        builder: (context) => r == null
            ? (_error == null
                  ? const VfLoadingView()
                  : ErpPageBody(children: [VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)]))
            : _body(context, r),
      ),
    );
  }

  Widget _body(BuildContext context, HrPayrollRun r) {
    final t = context.vf;
    final c = ErpService.to.currency;
    return ErpPageBody(
      onRefresh: _load,
      children: [
        DetailHead(
          icon: PhosphorIconsRegular.money,
          tint: t.successStrong,
          eyebrow: r.number,
          title: monthLabel(r.period),
          subtitle: 'hr.peopleN'.trParams({'n': '${r.employees}'}),
          badge: PayrollStatusBadge(r.status, large: true),
        ),
        VouchFlowPanel(
          title: 'hr.totals'.tr,
          child: Column(
            children: [
              FactLine('hr.gross'.tr, money(c, r.gross)),
              FactLine('hr.paye'.tr, money(c, r.v('paye'))),
              FactLine('hr.nssfEmployee'.tr, money(c, r.v('nssf_employee'))),
              if (r.v('heslb') > 0) FactLine('hr.heslb'.tr, money(c, r.v('heslb'))),
              if (r.v('loans') > 0) FactLine('hr.loans'.tr, money(c, r.v('loans'))),
              if (r.v('other_deductions') > 0) FactLine('hr.otherDeductions'.tr, money(c, r.v('other_deductions'))),
              FactLine('hr.totalDeductions'.tr, money(c, r.totalDeductions)),
              FactLine('hr.netPay'.tr, money(c, r.net), strong: true),
              FactLine('hr.employerCost'.tr, money(c, r.employerCost)),
              if (r.preparer != null) FactLine('hr.preparedBy'.tr, r.preparer!),
              if (r.authoriser != null) FactLine('hr.authorisedBy'.tr, r.authoriser!),
              if (r.paymentDate != null) FactLine('hr.paidOnLabel'.tr, dashDate(r.paymentDate)),
            ],
          ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'hr.payslipsN'.trParams({'n': '${r.payslips.length}'}),
          padded: false,
          child: Column(
            children: [
              for (var i = 0; i < r.payslips.length; i++)
                PayslipRow(
                  divider: i > 0,
                  title: r.payslips[i].employee,
                  slip: HrPayslipSummary(
                    id: r.payslips[i].id,
                    gross: r.payslips[i].gross,
                    deductions: r.payslips[i].totalDeductions,
                    net: r.payslips[i].net,
                    runNumber: [r.payslips[i].employeeNumber, ?r.payslips[i].department].join(' · '),
                  ),
                  currency: c,
                  onTap: () => Get.toNamed(Routes.erpHrPayslip, arguments: {'id': r.payslips[i].id, 'mine': false}),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text('hr.payrollWeb'.tr, textAlign: TextAlign.center, style: VfType.meta.copyWith(color: t.muted)),
      ],
    );
  }
}
