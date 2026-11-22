import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart' show ErpFmt;
import '../../data/models/hr_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/hr_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;
import '../erp/erp_widgets.dart';
import '../fleet/fleet_widgets.dart' show PanelEmpty;
import 'hr_widgets.dart';

/// The HR home for HR staff: headcount, leave waiting, who is in today and
/// the month's payroll, then who is on leave, contracts ending and the
/// staff by department (the web's /erp/hr).
class HrOverviewPage extends StatelessWidget {
  const HrOverviewPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'hr',
    permission: 'hr.view',
    builder: (_) => const _Overview(),
  );
}

class _Overview extends StatefulWidget {
  const _Overview();

  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  final _erp = ErpService.to;
  HrOverview? _d;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await HrRepository.to.overview();
      if (mounted) {
        setState(() {
          _d = d;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'state.offline'.tr);
    }
  }

  void _person(int? id) {
    if (id != null) Get.toNamed(Routes.erpHrEmployee, arguments: id);
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) {
      return _error == null
          ? const VfLoadingView()
          : ErpPageBody(
              onRefresh: _load,
              children: [
                VouchFlowErrorState(
                  message: _error!,
                  onRetry: _load,
                  retryLabel: 'action.retry'.tr,
                ),
              ],
            );
    }
    final t = context.vf;
    final currency = _erp.currency;
    final payrollStaff = [
      'hr.payroll.prepare',
      'hr.payroll.authorise',
      'hr.payroll.post',
    ].any(_erp.can);
    final peak = d.byDepartment.fold<int>(1, (a, b) => b.$2 > a ? b.$2 : a);

    return ErpPageBody(
      onRefresh: _load,
      children: [
        ErpPageTitle('area.hr'.tr, subtitle: 'hr.overviewSub'.tr),
        VouchFlowFigureGrid(
          children: [
            VouchFlowFigureCard(
              label: 'hr.headcount'.tr,
              value: '${d.headcount}',
              hint: d.suspended > 0
                  ? 'hr.suspendedN'.trParams({'n': '${d.suspended}'})
                  : 'hr.activeStaff'.tr,
              icon: PhosphorIconsRegular.usersThree,
              onTap: () => erpGo('/erp/hr/employees'),
            ),
            VouchFlowFigureCard(
              label: 'hr.leaveWaiting'.tr,
              value: '${d.pendingLeave}',
              hint: d.pendingLeave > 0
                  ? 'hr.leaveWaitingHint'.tr
                  : 'hr.nothingWaiting'.tr,
              icon: PhosphorIconsRegular.airplaneTilt,
              tone: d.pendingLeave > 0 ? VfTone.warn : VfTone.ok,
              onTap: _erp.can('hr.leave.approve')
                  ? () => erpGo('/erp/hr/leave')
                  : null,
            ),
            VouchFlowFigureCard(
              label: 'hr.inToday'.tr,
              value: '${d.inToday} / ${d.headcount}',
              hint: 'hr.lateAbsent'.trParams({
                'late': '${d.late}',
                'absent': '${d.absent}',
                'leave': '${d.onLeave}',
              }),
              icon: PhosphorIconsRegular.fingerprint,
              tone: VfTone.info,
              onTap: () => erpGo('/erp/hr/attendance'),
            ),
            if (d.payroll != null) ...[
              VouchFlowFigureCard(
                label: 'hr.payrollOf'.trParams({
                  'month': monthLabel(d.payroll!.period),
                }),
                value: ErpFmt.compactMoney(d.payroll!.net, currency),
                hint:
                    '${'hr.run.${d.payroll!.status}'.tr} · ${'hr.peopleN'.trParams({'n': '${d.payroll!.employees}'})}',
                icon: PhosphorIconsRegular.money,
                tone: VfTone.neutral,
                onTap: payrollStaff
                    ? () => Get.toNamed(
                        Routes.erpHrPayrollRun,
                        arguments: d.payroll!.id,
                      )
                    : null,
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        VouchFlowPanel(
          title: 'hr.onLeaveToday'.tr,
          padded: false,
          child: d.onLeaveToday.isEmpty
              ? PanelEmpty('hr.nobodyOnLeave'.tr)
              : Column(
                  children: [
                    for (var i = 0; i < d.onLeaveToday.length; i++)
                      VouchFlowListRow(
                        divider: i > 0,
                        icon: PhosphorIconsRegular.airplaneTilt,
                        iconColor: t.infoStrong,
                        title: d.onLeaveToday[i].name,
                        subtitle: [
                          ?d.onLeaveToday[i].detail,
                          'hr.backAfter'.trParams({
                            'date': dashDate(d.onLeaveToday[i].date),
                          }),
                        ].join(' · '),
                        onTap: () => _person(d.onLeaveToday[i].employeeId),
                      ),
                  ],
                ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'hr.contractsEnding'.tr,
          padded: false,
          child: d.contractsExpiring.isEmpty && d.probationEnding.isEmpty
              ? PanelEmpty('hr.nothingEnding'.tr)
              : Column(
                  children: [
                    for (final (i, c) in [
                      ...d.contractsExpiring,
                      ...d.probationEnding,
                    ].indexed)
                      VouchFlowListRow(
                        divider: i > 0,
                        icon: PhosphorIconsRegular.calendarBlank,
                        iconColor: t.warningStrong,
                        title: c.name,
                        subtitle: [
                          c.detail == null
                              ? 'hr.probationEnds'.tr
                              : 'hr.contract.${c.detail}'.tr,
                          dashDate(c.date),
                        ].join(' · '),
                        onTap: () => _person(c.employeeId),
                      ),
                  ],
                ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'hr.byDepartment'.tr,
          child: Column(
            children: [
              for (final (name, n) in d.byDepartment)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: VfType.small.copyWith(color: t.text),
                            ),
                          ),
                          Text(
                            '$n',
                            style: VfType.small.copyWith(
                              color: t.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(VfSize.radiusPill),
                        child: LinearProgressIndicator(
                          value: n / peak,
                          minHeight: 6,
                          color: t.primary,
                          backgroundColor: t.primary.withValues(alpha: .12),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
