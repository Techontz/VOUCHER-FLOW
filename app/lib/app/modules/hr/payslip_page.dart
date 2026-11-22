import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart' show ErpFmt;
import '../../data/models/hr_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/hr_repository.dart';
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;
import '../erp/erp_widgets.dart';
import '../fleet/fleet_widgets.dart' show FactLine;
import 'hr_widgets.dart';

/// One payslip: net pay large, then what was earned, what was deducted and
/// what the employer paid on top (the web's /erp/hr/me/payslips/[id]).
/// Opened with {'id': int, 'mine': bool}: an employee reads their own
/// through /hr/me, payroll staff anyone's.
class PayslipPage extends StatefulWidget {
  const PayslipPage({super.key, this.slipId, this.mine});

  final int? slipId;
  final bool? mine;

  @override
  State<PayslipPage> createState() => _PayslipPageState();
}

class _PayslipPageState extends State<PayslipPage> {
  late final Map? _args = Get.arguments is Map ? Get.arguments as Map : null;
  late final int _id = widget.slipId ?? (_args?['id'] as int? ?? (Get.arguments is int ? Get.arguments as int : 0));
  late final bool _mine = widget.mine ?? (_args?['mine'] != false);
  HrPayslip? _slip;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await HrRepository.to.payslip(_id, mine: _mine);
      if (mounted) setState(() { _slip = s; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'state.offline'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _slip;
    return VouchFlowPushedScaffold(
      title: s == null ? 'hr.payslip'.tr : monthLabel(s.period),
      body: ErpGate(
        module: 'hr',
        permission: _mine ? 'hr.self' : null,
        builder: (context) => s == null
            ? (_error == null
                  ? const VfLoadingView()
                  : ErpPageBody(children: [VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)]))
            : _body(context, s),
      ),
    );
  }

  Widget _line(String label, double v, String c, {bool minus = false, bool strong = false}) =>
      FactLine(label, '${minus && v > 0 ? '- ' : ''}${money(c, v)}', strong: strong, alignEnd: true);

  Widget _body(BuildContext context, HrPayslip s) {
    final t = context.vf;
    final c = ErpService.to.currency;
    return ErpPageBody(
      onRefresh: _load,
      children: [
        DecoratedBox(
          decoration: vfCardDecoration(t),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(s.employee, style: VfType.label.copyWith(color: t.muted))),
                    if (s.runStatus != null) PayrollStatusBadge(s.runStatus!),
                  ],
                ),
                const SizedBox(height: 8),
                Text('hr.netPay'.tr, style: VfType.small.copyWith(color: t.text2)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    money(c, s.net),
                    style: VfType.display.copyWith(color: t.text, fontSize: 24, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    monthLabel(s.period),
                    if (s.paymentDate != null) 'hr.paidOn'.trParams({'date': dashDate(s.paymentDate)}),
                    if (s.bank != null) '${s.bank} ${s.bankAccount ?? ''}'.trim(),
                  ].join(' · '),
                  style: VfType.meta.copyWith(color: t.muted),
                ),
              ],
            ),
          ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'hr.earnings'.tr,
          trailing: Text(money(c, s.gross), style: VfType.small.copyWith(color: t.text, fontWeight: FontWeight.w700)),
          child: Column(
            children: [
              _line('hr.basic'.tr, s.v('basic'), c),
              if (s.v('housing_allowance') > 0) _line('hr.housing'.tr, s.v('housing_allowance'), c),
              if (s.v('transport_allowance') > 0) _line('hr.transport'.tr, s.v('transport_allowance'), c),
              if (s.v('other_allowance') > 0) _line('hr.otherAllowance'.tr, s.v('other_allowance'), c),
              if (s.v('overtime') > 0) _line('hr.overtimeHours'.trParams({'n': ErpFmt.qty(s.v('overtime_hours'))}), s.v('overtime'), c),
              for (final l in s.earnings) _line(l.label, l.amount, c),
              if (s.earnings.isEmpty && s.v('other_earnings') > 0) _line('hr.otherEarnings'.tr, s.v('other_earnings'), c),
              if (s.v('absence_deduction') > 0)
                _line('hr.absence'.trParams({'n': ErpFmt.qty(s.v('unpaid_days'))}), s.v('absence_deduction'), c, minus: true),
              _line('hr.gross'.tr, s.gross, c, strong: true),
            ],
          ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'hr.deductions'.tr,
          trailing: Text(money(c, s.totalDeductions), style: VfType.small.copyWith(color: t.dangerStrong, fontWeight: FontWeight.w700)),
          child: Column(
            children: [
              _line('hr.nssfEmployee'.tr, s.v('nssf_employee'), c, minus: true),
              _line('hr.paye'.tr, s.v('paye'), c, minus: true),
              if (s.v('heslb') > 0) _line('hr.heslb'.tr, s.v('heslb'), c, minus: true),
              for (final l in s.loans) _line('${'hr.loan'.tr} ${l.label}', l.amount, c, minus: true),
              if (s.loans.isEmpty && s.v('loans') > 0) _line('hr.loans'.tr, s.v('loans'), c, minus: true),
              for (final l in s.deductions) _line(l.label, l.amount, c, minus: true),
              if (s.deductions.isEmpty && s.v('other_deductions') > 0) _line('hr.otherDeductions'.tr, s.v('other_deductions'), c, minus: true),
              _line('hr.totalDeductions'.tr, s.totalDeductions, c, strong: true),
            ],
          ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'hr.employerPaid'.tr,
          subtitle: 'hr.employerPaidSub'.tr,
          child: Column(
            children: [
              _line('hr.nssfEmployer'.tr, s.v('nssf_employer'), c),
              _line('hr.wcf'.tr, s.v('wcf'), c),
              if (s.v('sdl') > 0) _line('hr.sdl'.tr, s.v('sdl'), c),
            ],
          ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'hr.details'.tr,
          child: Column(
            children: [
              FactLine('hr.employeeNumber'.tr, s.employeeNumber),
              if (s.jobTitle != null) FactLine('hr.jobTitle'.tr, s.jobTitle!),
              if (s.department != null) FactLine('hr.department'.tr, s.department!),
              FactLine('hr.daysPaid'.tr, ErpFmt.qty(s.v('days_paid'))),
              FactLine('hr.taxable'.tr, money(c, s.v('taxable'))),
              if (s.runNumber != null) FactLine('hr.run'.tr, s.runNumber!),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(PhosphorIconsRegular.filePdf, size: 15, color: t.muted),
            const SizedBox(width: 6),
            Flexible(child: Text('hr.pdfOnWeb'.tr, style: VfType.meta.copyWith(color: t.muted))),
          ],
        ),
      ],
    );
  }
}
