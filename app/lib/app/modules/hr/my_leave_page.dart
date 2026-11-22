import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/hr_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/hr_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart' show showToast;
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;
import '../erp/erp_widgets.dart';
import '../fleet/fleet_widgets.dart' show ConfirmActions, PanelEmpty;
import 'hr_widgets.dart';

/// An employee's leave: what is left of each kind, one big "Apply for
/// leave", and every request with its state; a waiting or approved one
/// still to come can be cancelled.
class MyLeavePage extends StatelessWidget {
  const MyLeavePage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(module: 'hr', permission: 'hr.self', builder: (_) => const _MyLeave());
}

class _MyLeave extends StatefulWidget {
  const _MyLeave();

  @override
  State<_MyLeave> createState() => _MyLeaveState();
}

class _MyLeaveState extends State<_MyLeave> {
  final _repo = HrRepository.to;
  List<HrLeaveRequest>? _requests;
  List<HrLeaveBalance> _balances = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (requests, balances) = await _repo.myLeave();
      if (mounted) setState(() { _requests = requests; _balances = balances; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'state.offline'.tr);
    }
  }

  Future<void> _apply([int? typeId]) async {
    final done = await Get.toNamed(Routes.erpHrLeaveNew, arguments: {'typeId': ?typeId});
    if (done == true) _load();
  }

  bool _cancellable(HrLeaveRequest r) {
    if (r.status == HrLeaveStatus.pending) return true;
    final start = r.start;
    return r.status == HrLeaveStatus.approved && start != null && start.isAfter(DateTime.now());
  }

  Future<void> _open(HrLeaveRequest r) async {
    final message = await showVouchFlowDialog<String>(
      context,
      dialog: VouchFlowDialog(
        icon: PhosphorIconsRegular.airplaneTilt,
        tone: VfTone.info,
        title: r.type,
        subtitle: 'hr.leave.${r.status}'.tr,
        summary: [
          VfSummaryRow('hr.dates'.tr, dateRange(r.start, r.end)),
          VfSummaryRow('hr.days'.tr, daysLabel(r.days)),
          if (r.reason != null) VfSummaryRow('hr.reason'.tr, r.reason!),
          if (r.decider != null) VfSummaryRow('hr.decidedBy'.tr, r.decider!),
          if (r.decisionNote != null) VfSummaryRow('hr.note'.tr, r.decisionNote!),
        ],
        child: _cancellable(r)
            ? ConfirmActions(
                confirmLabel: 'hr.cancelLeave'.tr,
                backLabel: 'hr.keep'.tr,
                danger: true,
                run: (_) => _repo.cancelMyLeave(r.id),
              )
            : null,
      ),
    );
    if (message == null) return;
    showToast(message.isEmpty ? 'hr.leave.cancelled'.tr : message);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final requests = _requests;
    if (requests == null) {
      return _error == null
          ? const VfLoadingView()
          : ErpPageBody(onRefresh: _load, children: [VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)]);
    }
    final t = context.vf;
    final shown = _balances.where((b) => b.limited).toList();
    final upcoming = requests.where((r) => r.status == HrLeaveStatus.approved && r.end != null && !r.end!.isBefore(DateTime.now())).firstOrNull;
    return ErpPageBody(
      onRefresh: _load,
      children: [
        ErpPageTitle('hr.nav.myLeave'.tr, subtitle: 'hr.myLeaveSub'.trParams({'year': '${DateTime.now().year}'})),
        if (upcoming != null) ...[
          VouchFlowAlert(
            tone: VfTone.ok,
            icon: PhosphorIconsRegular.airplaneTilt,
            message: 'hr.upcomingLeave'.trParams({'type': upcoming.type, 'date': dashDate(upcoming.start)}),
          ),
          erpGap,
        ],
        LayoutBuilder(
          builder: (context, box) {
            final w = (box.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [for (final b in shown) SizedBox(width: w, child: BalanceTile(balance: b, onTap: () => _apply(b.typeId)))],
            );
          },
        ),
        const SizedBox(height: 14),
        VouchFlowButton(label: 'hr.applyLeave'.tr, icon: PhosphorIconsRegular.calendarPlus, expand: true, height: 56, onPressed: _apply),
        const SizedBox(height: 14),
        VouchFlowPanel(
          title: 'hr.myRequests'.tr,
          padded: false,
          child: requests.isEmpty
              ? PanelEmpty('hr.noLeave'.tr)
              : Column(
                  children: [
                    for (var i = 0; i < requests.length; i++) LeaveRow(request: requests[i], divider: i > 0, onTap: () => _open(requests[i])),
                  ],
                ),
        ),
        const SizedBox(height: 10),
        Text('hr.leaveNote'.tr, textAlign: TextAlign.center, style: VfType.meta.copyWith(color: t.muted)),
      ],
    );
  }
}
