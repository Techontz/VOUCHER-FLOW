import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart' show ErpFmt;
import '../../data/models/hr_models.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/hr_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../erp/erp_widgets.dart';
import '../fleet/paged_list.dart';
import 'hr_widgets.dart';

/// Payroll runs, newest month first, read only on the phone: preparing,
/// authorising and posting stay on the web (the web's /erp/hr/payroll).
class PayrollPage extends StatelessWidget {
  const PayrollPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'hr',
    builder: (context) {
      final currency = ErpService.to.currency;
      return PagedListBody<HrPayrollRun>(
        title: 'hr.nav.payroll'.tr,
        subtitle: 'hr.payrollSub'.tr,
        load: (q, status, page) => HrRepository.to.payrollRuns(page: page),
        emptyText: 'hr.noRuns'.tr,
        emptyIcon: PhosphorIconsRegular.money,
        row: (context, run, i, reload) {
          final t = context.vf;
          return VouchFlowListRow(
            divider: i > 0,
            icon: PhosphorIconsRegular.money,
            iconColor: run.status == 'paid' ? t.successStrong : t.primary,
            title: monthLabel(run.period),
            subtitle: [
              run.number,
              'hr.peopleN'.trParams({'n': '${run.employees}'}),
              '${'hr.net'.tr} ${ErpFmt.compactMoney(run.net, currency)}',
            ].join(' · '),
            trailing: PayrollStatusBadge(run.status),
            onTap: () => Get.toNamed(Routes.erpHrPayrollRun, arguments: run.id),
          );
        },
      );
    },
  );
}
