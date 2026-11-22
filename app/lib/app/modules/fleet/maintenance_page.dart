import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart' show ErpFmt, ErpPage;
import '../../data/models/fleet_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/fleet_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;
import '../erp/erp_widgets.dart';
import 'fleet_widgets.dart';

/// Maintenance at a glance: what is overdue or due soon, every schedule, and
/// the latest service records (the web's /erp/fleet/maintenance, read only
/// on the phone). A row opens its vehicle.
class MaintenancePage extends StatelessWidget {
  const MaintenancePage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'fleet',
    permission: 'fleet.view',
    builder: (_) => const _Maintenance(),
  );
}

class _Maintenance extends StatefulWidget {
  const _Maintenance();

  @override
  State<_Maintenance> createState() => _MaintenanceState();
}

class _MaintenanceState extends State<_Maintenance> {
  final _repo = FleetRepository.to;
  List<FleetSchedule>? _schedules;
  List<FleetService> _services = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([_repo.schedules(), _repo.services()]);
      if (!mounted) return;
      setState(() {
        _schedules = results[0] as List<FleetSchedule>;
        _services = (results[1] as ErpPage<FleetService>).data;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'state.offline'.tr);
    }
  }

  void _vehicle(int? id) {
    if (id != null) Get.toNamed(Routes.erpFleetVehicle, arguments: id);
  }

  @override
  Widget build(BuildContext context) {
    final schedules = _schedules;
    if (schedules == null) {
      return _error == null
          ? const VfLoadingView()
          : ErpPageBody(onRefresh: _load, children: [VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)]);
    }
    final t = context.vf;
    final currency = ErpService.to.currency;
    final due = schedules.where((s) => s.state != 'ok').toList()
      ..sort((a, b) => (a.state == 'overdue' ? 0 : 1).compareTo(b.state == 'overdue' ? 0 : 1));
    final rest = schedules.where((s) => s.state == 'ok').toList();

    return ErpPageBody(
      onRefresh: _load,
      children: [
        ErpPageTitle('flt.nav.maintenance'.tr, subtitle: 'flt.maintenanceSub'.tr),
        VouchFlowPanel(
          title: 'flt.dueNow'.tr,
          subtitle: due.isEmpty ? null : 'flt.scheduleCount'.trParams({'n': '${due.length}'}),
          padded: false,
          child: due.isEmpty
              ? PanelEmpty('flt.nothingDue'.tr)
              : Column(
                  children: [
                    for (var i = 0; i < due.length; i++)
                      ScheduleRow(schedule: due[i], divider: i > 0, onTap: () => _vehicle(due[i].vehicleId)),
                  ],
                ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'flt.serviceRecords'.tr,
          padded: false,
          child: _services.isEmpty
              ? PanelEmpty('flt.noServices'.tr)
              : Column(
                  children: [
                    for (var i = 0; i < _services.length; i++)
                      ServiceRow(service: _services[i], currency: currency, divider: i > 0),
                  ],
                ),
        ),
        if (rest.isNotEmpty) ...[
          erpGap,
          VouchFlowPanel(
            title: 'flt.onSchedule'.tr,
            padded: false,
            child: Column(
              children: [
                for (var i = 0; i < rest.length; i++)
                  ScheduleRow(schedule: rest[i], divider: i > 0, onTap: () => _vehicle(rest[i].vehicleId)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 4),
        Text('flt.maintenanceWeb'.tr, textAlign: TextAlign.center, style: VfType.meta.copyWith(color: t.muted)),
      ],
    );
  }
}

/// A service record: the work, the vehicle and garage, cost and state.
class ServiceRow extends StatelessWidget {
  const ServiceRow({super.key, required this.service, required this.currency, this.divider = true, this.showVehicle = true});

  final FleetService service;
  final String currency;
  final bool divider, showVehicle;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final s = service;
    return VouchFlowListRow(
      divider: divider,
      icon: PhosphorIconsRegular.wrench,
      iconColor: s.status == 'posted' ? t.successStrong : t.infoStrong,
      title: s.workDone,
      titleMaxLines: 2,
      subtitle: [
        if (showVehicle) ?s.vehicle,
        ?s.garage,
        '$currency ${ErpFmt.amount(s.cost)}',
        if (s.date != null) dashDate(s.date),
      ].join(' · '),
      trailing: VouchFlowStatusBadge(
        label: 'flt.service.${s.status}'.tr,
        tag: switch (s.status) {
          'posted' => 'tag-accent',
          'draft' => 'tag-info',
          _ => 'tag-neutral',
        },
      ),
    );
  }
}
