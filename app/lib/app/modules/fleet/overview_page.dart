import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/fleet_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/fleet_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../erp/erp_widgets.dart';
import 'fleet_app.dart';
import 'fleet_widgets.dart';

/// The Fleet home for fleet staff: vehicles on the road, entries waiting
/// for approval, the month's fuel and maintenance due, then today's trips,
/// papers running out and trips over their fuel standard (the web's
/// /erp/fleet).
class FleetOverviewPage extends StatelessWidget {
  const FleetOverviewPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'fleet',
    permission: 'fleet.view',
    builder: (_) => const _Overview(),
  );
}

class _Overview extends StatefulWidget {
  const _Overview();

  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  final _repo = FleetRepository.to;
  final _erp = ErpService.to;
  FleetOverview? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _repo.overview();
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'state.offline'.tr);
    }
  }

  Future<void> _trip(FleetTrip t) async {
    await Get.toNamed(
      Routes.erpFleetTrip,
      arguments: {'id': t.id, 'mine': false},
    );
    _load();
  }

  Future<void> _vehicle(int id) async {
    await Get.toNamed(Routes.erpFleetVehicle, arguments: id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
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
    final actions = fleetCreateActions
        .where((a) => a.permission == null || _erp.can(a.permission!))
        .toList();
    final due = d.maintenanceDue;
    final overdue = due.where((s) => s.state == 'overdue').length;

    final figures = [
      VouchFlowFigureGrid(
        children: [
          VouchFlowFigureCard(
            label: 'flt.onTheRoad'.tr,
            value: '${d.onTrip} / ${d.vehicles}',
            hint: 'flt.vehiclesHint'.trParams({
              'n': '${d.byStatus[FleetVehicleStatus.available] ?? 0}',
            }),
            icon: PhosphorIconsRegular.truck,
            onTap: () => erpGo('/erp/fleet/vehicles'),
          ),
          VouchFlowFigureCard(
            label: 'flt.waitingApproval'.tr,
            value: '${d.pendingEntries}',
            hint: d.pendingEntries > 0
                ? 'flt.waitingHint'.tr
                : 'flt.nothingWaiting'.tr,
            icon: PhosphorIconsRegular.hourglassMedium,
            tone: d.pendingEntries > 0 ? VfTone.warn : VfTone.ok,
            onTap: () => erpGo('/erp/fleet/fuel'),
          ),
          VouchFlowFigureCard(
            label: 'flt.fuelMonth'.tr,
            value: litresLabel(d.litres),
            hint: 'flt.tripsClosed'.trParams({'n': '${d.tripsClosed}'}),
            icon: PhosphorIconsRegular.gasPump,
            tone: VfTone.info,
            onTap: () => erpGo('/erp/fleet/fuel'),
          ),
          VouchFlowFigureCard(
            label: 'flt.maintenanceDue'.tr,
            value: '${due.length}',
            hint: overdue > 0
                ? 'flt.overdueCount'.trParams({'n': '$overdue'})
                : 'flt.nothingOverdue'.tr,
            icon: PhosphorIconsRegular.wrench,
            tone: overdue > 0
                ? VfTone.bad
                : due.isNotEmpty
                ? VfTone.warn
                : VfTone.ok,
            onTap: () => erpGo('/erp/fleet/maintenance'),
          ),
        ],
      ),
    ];

    return ErpPageBody(
      onRefresh: _load,
      children: [
        ErpPageTitle('area.fleet'.tr, subtitle: 'flt.overviewSub'.tr),
        for (final f in figures) ...[f, const SizedBox(height: 12)],
        const SizedBox(height: 2),
        if (actions.isNotEmpty) ...[
          VouchFlowPanel(
            title: 'flt.quickActions'.tr,
            padded: false,
            child: Column(
              children: [
                for (var i = 0; i < actions.length; i++)
                  VouchFlowListRow(
                    divider: i > 0,
                    icon: actions[i].icon,
                    title: actions[i].label.tr,
                    subtitle: actions[i].hint?.tr,
                    trailing: Icon(
                      PhosphorIconsBold.caretRight,
                      size: 14,
                      color: t.faint,
                    ),
                    onTap: () async {
                      await erpCreate(actions[i]);
                      _load();
                    },
                  ),
              ],
            ),
          ),
          erpGap,
        ],
        VouchFlowPanel(
          title: 'flt.tripsToday'.tr,
          padded: false,
          actionLabel: 'erp.viewAll'.tr,
          onAction: () => erpGo('/erp/fleet/trips'),
          child: d.tripsToday.isEmpty
              ? PanelEmpty('flt.noTripsToday'.tr)
              : Column(
                  children: [
                    for (var i = 0; i < d.tripsToday.length; i++)
                      TripRow(
                        trip: d.tripsToday[i],
                        divider: i > 0,
                        onTap: () => _trip(d.tripsToday[i]),
                      ),
                  ],
                ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'flt.expiring'.tr,
          padded: false,
          child: d.expiring.isEmpty
              ? PanelEmpty('flt.nothingExpiring'.tr)
              : Column(
                  children: [
                    for (var i = 0; i < d.expiring.length; i++)
                      PaperRow(
                        divider: i > 0,
                        label: d.expiring[i].subject,
                        number: 'flt.paper.${d.expiring[i].kind}'.tr,
                        date: d.expiring[i].date,
                        onTap: d.expiring[i].vehicleId == null
                            ? null
                            : () => _vehicle(d.expiring[i].vehicleId!),
                      ),
                  ],
                ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'flt.maintenanceDue'.tr,
          padded: false,
          actionLabel: 'erp.viewAll'.tr,
          onAction: () => erpGo('/erp/fleet/maintenance'),
          child: due.isEmpty
              ? PanelEmpty('flt.nothingDue'.tr)
              : Column(
                  children: [
                    for (var i = 0; i < due.length; i++)
                      ScheduleRow(
                        schedule: due[i],
                        divider: i > 0,
                        onTap: due[i].vehicleId == null
                            ? null
                            : () => _vehicle(due[i].vehicleId!),
                      ),
                  ],
                ),
        ),
        if (d.fuelAlerts.isNotEmpty) ...[
          erpGap,
          VouchFlowPanel(
            title: 'flt.overStandard'.tr,
            padded: false,
            child: Column(
              children: [
                for (var i = 0; i < d.fuelAlerts.length; i++)
                  TripRow(
                    trip: d.fuelAlerts[i],
                    divider: i > 0,
                    onTap: () => _trip(d.fuelAlerts[i]),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
