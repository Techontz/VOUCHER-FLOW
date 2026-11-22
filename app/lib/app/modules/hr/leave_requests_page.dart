import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/models/hr_models.dart';
import '../../data/services/hr_repository.dart';
import '../../widgets/common.dart' show showToast;
import '../../widgets/vf/vf.dart';
import '../erp/erp_widgets.dart';
import '../fleet/fleet_widgets.dart' show ConfirmActions;
import '../fleet/paged_list.dart';
import 'hr_widgets.dart';

/// Leave requests to decide: HR sees every one, a department head their own
/// team (the API decides), waiting ones first. Tapping one the caller may
/// decide opens Approve and Reject (the web's /erp/hr/leave).
class LeaveRequestsPage extends StatelessWidget {
  const LeaveRequestsPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'hr',
    permission: 'hr.leave.approve',
    builder: (_) => PagedListBody<HrLeaveRequest>(
      title: 'hr.nav.leave'.tr,
      subtitle: 'hr.leaveSub'.tr,
      statuses: const [null, ...HrLeaveStatus.all],
      statusLabel: (s) => s == null ? 'hr.all'.tr : 'hr.leave.$s'.tr,
      load: (q, status, page) => HrRepository.to.leaveRequests(status: status, page: page),
      emptyText: 'hr.noLeaveRequests'.tr,
      emptyIcon: PhosphorIconsRegular.airplaneTilt,
      row: (context, r, i, reload) => LeaveRow(
        request: r,
        divider: i > 0,
        showEmployee: true,
        onTap: r.canDecide
            ? () async {
                if (await decideLeave(context, r)) reload();
              }
            : null,
      ),
    ),
  );
}

/// Approve or reject a leave request; true once decided.
Future<bool> decideLeave(BuildContext context, HrLeaveRequest r) async {
  final repo = HrRepository.to;
  final summary = [
    VfSummaryRow('hr.employee'.tr, [?r.employee, ?r.department].join(' · ')),
    VfSummaryRow('hr.leaveType'.tr, r.type),
    VfSummaryRow('hr.dates'.tr, dateRange(r.start, r.end)),
    VfSummaryRow('hr.days'.tr, daysLabel(r.days)),
    if (r.reason != null) VfSummaryRow('hr.reason'.tr, r.reason!),
  ];
  final choice = await showVouchFlowDialog<String>(
    context,
    dialog: VouchFlowDialog(
      icon: PhosphorIconsRegular.airplaneTilt,
      tone: VfTone.info,
      title: 'hr.decideQ'.trParams({'name': r.employee ?? ''}),
      summary: summary,
      child: Builder(
        builder: (ctx) => Padding(
          padding: const EdgeInsets.only(top: 14),
          child: VouchFlowActions(
            children: [
              VouchFlowButton(label: 'hr.reject'.tr, variant: VfButtonVariant.danger, onPressed: () => Navigator.of(ctx).pop('reject')),
              VouchFlowButton(label: 'hr.approve'.tr, icon: PhosphorIconsRegular.check, onPressed: () => Navigator.of(ctx).pop('approve')),
            ],
          ),
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return false;
  final approve = choice == 'approve';
  final message = await showVouchFlowDialog<String>(
    context,
    dialog: VouchFlowDialog(
      icon: approve ? PhosphorIconsRegular.checkCircle : PhosphorIconsRegular.xCircle,
      tone: approve ? VfTone.ok : VfTone.bad,
      title: approve ? 'hr.approveQ'.tr : 'hr.rejectQ'.tr,
      summary: summary.take(3).toList(),
      child: ConfirmActions(
        confirmLabel: approve ? 'hr.approve'.tr : 'hr.reject'.tr,
        danger: !approve,
        fieldLabel: approve ? 'hr.noteOptional'.tr : 'hr.rejectReason'.tr,
        fieldRequired: !approve,
        errorField: 'note',
        run: (note) => approve ? repo.approveLeave(r.id, note: note) : repo.rejectLeave(r.id, note),
      ),
    ),
  );
  if (message == null) return false;
  showToast(message.isEmpty ? 'hr.leave.${approve ? 'approved' : 'rejected'}'.tr : message);
  return true;
}
