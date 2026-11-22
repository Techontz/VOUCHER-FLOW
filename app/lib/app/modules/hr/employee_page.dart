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
import '../fleet/fleet_widgets.dart' show FactLine, PanelEmpty;
import 'hr_widgets.dart';

/// One person's file as HR reads it: contact, job, pay (only with
/// hr.salary), leave balances and requests, the last days of attendance and
/// payslips (the web's /erp/hr/employees/[id]). Opened with the employee id.
class EmployeePage extends StatefulWidget {
  const EmployeePage({super.key, this.employeeId});

  final int? employeeId;

  @override
  State<EmployeePage> createState() => _EmployeePageState();
}

class _EmployeePageState extends State<EmployeePage> {
  late final int _id = widget.employeeId ?? (Get.arguments as int);
  HrPersonFile? _file;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final f = await HrRepository.to.employee(_id);
      if (mounted) setState(() { _file = f; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'state.offline'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _file;
    return VouchFlowPushedScaffold(
      title: f?.employee.name ?? 'hr.employee'.tr,
      body: ErpGate(
        module: 'hr',
        permission: 'hr.view',
        builder: (context) => f == null
            ? (_error == null
                  ? const VfLoadingView()
                  : ErpPageBody(children: [VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)]))
            : ErpPageBody(onRefresh: _load, children: personFile(context, f, mine: false)),
      ),
    );
  }
}

/// The panels of a person's file, shared by HR's employee page and an
/// employee's own "My HR".
List<Widget> personFile(BuildContext context, HrPersonFile f, {required bool mine, VoidCallback? onEdit}) {
  final t = context.vf;
  final e = f.employee;
  final c = ErpService.to.currency;
  final contract = e.contract;
  final payrollStaff = ['hr.payroll.prepare', 'hr.payroll.authorise', 'hr.payroll.post'].any(ErpService.to.can);
  return [
    Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 18),
      child: Row(
        children: [
          VouchFlowAvatar(initials: e.initials, size: 60),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.name, style: VfType.pageTitle.copyWith(color: t.text, fontSize: 19, letterSpacing: -.3)),
                Text([?e.jobTitle, ?e.department].join(' · '), style: VfType.small.copyWith(color: t.text2)),
                const SizedBox(height: 6),
                VouchFlowStatusBadge(
                  label: 'hr.status.${e.status}'.tr,
                  tag: e.status == 'active' ? 'tag-accent' : e.status == 'suspended' ? 'tag-warn' : 'tag-neutral',
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    VouchFlowPanel(
      title: 'hr.contact'.tr,
      actionLabel: onEdit == null ? null : 'hr.edit'.tr,
      onAction: onEdit,
      child: Column(
        children: [
          FactLine('hr.phone'.tr, e.phone ?? '-'),
          FactLine('hr.email'.tr, e.email ?? '-'),
          FactLine('hr.address'.tr, e.address ?? '-'),
          FactLine(
            'hr.nextOfKin'.tr,
            e.nextOfKinName == null ? '-' : [e.nextOfKinName!, ?e.nextOfKinRelation, ?e.nextOfKinPhone].join(' · '),
          ),
        ],
      ),
    ),
    erpGap,
    VouchFlowPanel(
      title: 'hr.job'.tr,
      child: Column(
        children: [
          FactLine('hr.employeeNumber'.tr, e.number),
          if (e.employmentType != null) FactLine('hr.employment'.tr, 'hr.contract.${e.employmentType}'.tr),
          if (e.grade != null) FactLine('hr.grade'.tr, e.grade!),
          if (e.manager != null) FactLine('hr.manager'.tr, e.manager!),
          if (e.hireDate != null) FactLine('hr.hired'.tr, dashDate(e.hireDate)),
          if (e.probationEnd != null) FactLine('hr.probationEnd'.tr, dashDate(e.probationEnd)),
          if (e.shift != null && e.shift!.isNotEmpty) FactLine('hr.shift'.tr, e.shift!),
        ],
      ),
    ),
    if (contract != null && contract.hasPay) ...[
      erpGap,
      VouchFlowPanel(
        title: 'hr.pay'.tr,
        subtitle: [
          'hr.contract.${contract.type}'.tr,
          if (contract.start != null) '${'hr.since'.tr} ${dashDate(contract.start)}',
          if (contract.end != null) '${'hr.until'.tr} ${dashDate(contract.end)}',
        ].join(' · '),
        child: Column(
          children: [
            FactLine('hr.basic'.tr, money(c, contract.basic ?? 0)),
            if ((contract.housing ?? 0) > 0) FactLine('hr.housing'.tr, money(c, contract.housing!)),
            if ((contract.transport ?? 0) > 0) FactLine('hr.transport'.tr, money(c, contract.transport!)),
            if ((contract.other ?? 0) > 0) FactLine('hr.otherAllowance'.tr, money(c, contract.other!)),
            FactLine('hr.grossMonth'.tr, money(c, contract.gross), strong: true),
            if (e.bank != null) FactLine('hr.bank'.tr, '${e.bank} ${e.bankAccount ?? ''}'.trim()),
          ],
        ),
      ),
    ],
    if (f.balances.isNotEmpty) ...[
      erpGap,
      VouchFlowPanel(
        title: 'hr.leaveBalances'.tr,
        padded: false,
        child: Column(
          children: [
            for (var i = 0; i < f.balances.length; i++)
              VouchFlowListRow(
                divider: i > 0,
                icon: PhosphorIconsRegular.calendarCheck,
                iconColor: t.infoStrong,
                title: f.balances[i].type,
                subtitle: f.balances[i].limited
                    ? 'hr.takenOf'.trParams({'taken': '${f.balances[i].taken}', 'of': f.balances[i].accrued.toStringAsFixed(1)})
                    : 'hr.noLimit'.tr,
                trailing: Text(
                  f.balances[i].available == null ? '-' : daysLabel(double.parse(f.balances[i].available!.toStringAsFixed(1))),
                  style: VfType.small.copyWith(color: t.text, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    ],
    if (!mine) ...[
      erpGap,
      VouchFlowPanel(
        title: 'hr.leaveRequests'.tr,
        padded: false,
        child: f.leave.isEmpty
            ? PanelEmpty('hr.noLeave'.tr)
            : Column(children: [for (var i = 0; i < f.leave.length; i++) LeaveRow(request: f.leave[i], divider: i > 0)]),
      ),
      erpGap,
      VouchFlowPanel(
        title: 'hr.recentAttendance'.tr,
        padded: false,
        child: f.attendance.isEmpty
            ? PanelEmpty('hr.noAttendance'.tr)
            : Column(
                children: [
                  for (var i = 0; i < f.attendance.length && i < 10; i++) AttendanceDayRow(record: f.attendance[i], divider: i > 0),
                ],
              ),
      ),
      if (f.payslips.isNotEmpty) ...[
        erpGap,
        VouchFlowPanel(
          title: 'hr.nav.payslips'.tr,
          padded: false,
          child: Column(
            children: [
              for (var i = 0; i < f.payslips.length && i < 12; i++)
                PayslipRow(
                  slip: f.payslips[i],
                  currency: c,
                  divider: i > 0,
                  onTap: payrollStaff
                      ? () => Get.toNamed(Routes.erpHrPayslip, arguments: {'id': f.payslips[i].id, 'mine': false})
                      : () {},
                ),
            ],
          ),
        ),
      ],
    ],
  ];
}
