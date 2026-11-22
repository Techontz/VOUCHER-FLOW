import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart' show ErpFmt;
import '../../data/models/fleet_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/fleet_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDateTime;
import '../erp/erp_widgets.dart';
import 'fleet_widgets.dart';
import 'maintenance_page.dart' show ServiceRow;

/// One vehicle: its status and reading, its papers and when they run out,
/// the service it is due, and its latest trips, fuel and service history
/// (the web's /erp/fleet/vehicles/[id]). Opened with the vehicle's id.
class VehiclePage extends StatefulWidget {
  const VehiclePage({super.key, this.vehicleId});

  final int? vehicleId;

  @override
  State<VehiclePage> createState() => _VehiclePageState();
}

class _VehiclePageState extends State<VehiclePage> {
  late final int _id = widget.vehicleId ?? (Get.arguments as int);
  final _repo = FleetRepository.to;
  FleetVehicle? _v;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await _repo.vehicle(_id);
      if (mounted) setState(() { _v = v; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'state.offline'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    return VouchFlowPushedScaffold(
      title: v?.registration ?? 'flt.vehicle'.tr,
      body: ErpGate(
        module: 'fleet',
        permission: 'fleet.view',
        builder: (context) => v == null
            ? (_error == null
                  ? const VfLoadingView()
                  : ErpPageBody(children: [VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)]))
            : _body(context, v),
      ),
    );
  }

  Widget _body(BuildContext context, FleetVehicle v) {
    final t = context.vf;
    final currency = ErpService.to.currency;
    return ErpPageBody(
      onRefresh: _load,
      children: [
        DetailHead(
          icon: PhosphorIconsRegular.truck,
          tint: t.primary,
          eyebrow: ['flt.type.${v.type}'.tr, v.isHired ? 'flt.hired'.tr : 'flt.owned'.tr].join(' · '),
          title: v.registration,
          subtitle: [v.title, if (v.year != null) '${v.year}'].where((s) => s.isNotEmpty).join(' · '),
          badge: VehicleStatusBadge(v.status, large: true),
        ),
        if (v.offRoadSince != null) ...[
          VouchFlowAlert(
            tone: VfTone.warn,
            icon: PhosphorIconsRegular.warning,
            message: 'flt.offRoadSince'.trParams({'time': dashDateTime(v.offRoadSince)}),
          ),
          erpGap,
        ],
        VouchFlowPanel(
          title: 'flt.vehicle'.tr,
          child: Column(
            children: [
              FactLine('flt.odometer'.tr, kmLabel(v.odometer), strong: true),
              FactLine('flt.driver'.tr, v.driver ?? 'flt.noDriver'.tr),
              if (v.capacity != null) FactLine('flt.capacity'.tr, '${ErpFmt.qty(v.capacity)} ${v.capacityUnit ?? ''}'.trim()),
              if (v.isHired && v.owner != null) FactLine('flt.owner'.tr, v.owner!),
              if (v.isHired && v.hireIncludesFuel) FactLine('flt.fuel'.tr, 'flt.wetHire'.tr),
              if (!v.isHired && (v.monthlyFixedCost ?? 0) > 0)
                FactLine('flt.fixedMonth'.tr, '$currency ${ErpFmt.amount(v.monthlyFixedCost)}'),
            ],
          ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'flt.papers'.tr,
          padded: false,
          child: Column(
            children: [
              PaperRow(
                divider: false,
                label: 'flt.paper.insurance'.tr,
                number: [?v.insurer, ?v.policyNumber].join(' · '),
                date: v.insuranceExpiry,
              ),
              PaperRow(label: 'flt.paper.road_licence'.tr, number: v.roadLicenceNumber, date: v.roadLicenceExpiry),
            ],
          ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'flt.serviceDue'.tr,
          padded: false,
          child: v.schedules.isEmpty
              ? PanelEmpty('flt.noSchedules'.tr)
              : Column(
                  children: [
                    for (var i = 0; i < v.schedules.length; i++)
                      ScheduleRow(schedule: v.schedules[i], divider: i > 0, showVehicle: false),
                  ],
                ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'flt.recentTrips'.tr,
          padded: false,
          child: v.trips.isEmpty
              ? PanelEmpty('flt.noTrips'.tr)
              : Column(
                  children: [
                    for (var i = 0; i < v.trips.length && i < 10; i++)
                      TripRow(
                        trip: v.trips[i],
                        divider: i > 0,
                        onTap: () => Get.toNamed(Routes.erpFleetTrip, arguments: {'id': v.trips[i].id, 'mine': false}),
                      ),
                  ],
                ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'flt.recentFuel'.tr,
          padded: false,
          child: v.fuel.isEmpty
              ? PanelEmpty('flt.noFuel'.tr)
              : Column(
                  children: [
                    for (var i = 0; i < v.fuel.length && i < 10; i++) FuelRow(fuel: v.fuel[i], currency: currency, divider: i > 0),
                  ],
                ),
        ),
        if (v.services.isNotEmpty) ...[
          erpGap,
          VouchFlowPanel(
            title: 'flt.serviceRecords'.tr,
            padded: false,
            child: Column(
              children: [
                for (var i = 0; i < v.services.length && i < 10; i++)
                  ServiceRow(service: v.services[i], currency: currency, divider: i > 0, showVehicle: false),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
