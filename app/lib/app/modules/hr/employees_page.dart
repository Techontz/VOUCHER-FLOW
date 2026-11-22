import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/models/hr_models.dart';
import '../../data/services/hr_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../erp/erp_widgets.dart';
import '../fleet/paged_list.dart';

/// The staff list, searchable by name, number, job or phone (the web's
/// /erp/hr/employees). A person opens on their file.
class EmployeesPage extends StatelessWidget {
  const EmployeesPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'hr',
    permission: 'hr.view',
    builder: (_) => PagedListBody<HrEmployee>(
      title: 'hr.nav.employees'.tr,
      subtitle: 'hr.employeesSub'.tr,
      searchPlaceholder: 'hr.searchEmployees'.tr,
      statuses: const [null, 'active', 'suspended', 'exited'],
      statusLabel: (s) => s == null ? 'hr.current'.tr : 'hr.status.$s'.tr,
      load: (q, status, page) => HrRepository.to.employees(q: q, status: status, page: page),
      emptyText: 'hr.noEmployees'.tr,
      emptyIcon: PhosphorIconsRegular.usersThree,
      row: (context, e, i, reload) => VouchFlowListRow(
        divider: i > 0,
        icon: PhosphorIconsRegular.user,
        title: e.name,
        subtitle: [?e.jobTitle, ?e.department, e.number].join(' · '),
        trailing: e.status == 'active'
            ? null
            : VouchFlowStatusBadge(label: 'hr.status.${e.status}'.tr, tag: e.status == 'suspended' ? 'tag-warn' : 'tag-neutral'),
        onTap: () async {
          await Get.toNamed(Routes.erpHrEmployee, arguments: e.id);
          reload();
        },
      ),
    ),
  );
}
