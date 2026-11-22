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
import '../../widgets/common.dart' show showToast;
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate, dashDateTime;
import '../erp/erp_widgets.dart';
import 'fleet_widgets.dart';

/// One trip: where it goes, the vehicle and driver, odometer out and in,
/// the fuel on it and, for fleet staff, what it cost. Its foot carries
/// the next step: Start trip and End trip (fleet.trips, each asking for the
/// odometer), and Log fuel. Opened with {'id': int, 'mine': bool}; a driver
/// reads their own trip through /fleet/my-trips.
class TripPage extends StatefulWidget {
  const TripPage({super.key, this.tripId, this.mine});

  final int? tripId;
  final bool? mine;

  @override
  State<TripPage> createState() => _TripPageState();
}

class _TripPageState extends State<TripPage> {
  late final Map? _args = Get.arguments is Map ? Get.arguments as Map : null;
  late final int _id = widget.tripId ?? (_args?['id'] as int? ?? (Get.arguments is int ? Get.arguments as int : 0));
  late final bool _mine = widget.mine ?? (_args?['mine'] == true);

  final _repo = FleetRepository.to;
  final _erp = ErpService.to;
  FleetTrip? _trip;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await _repo.trip(_id, mine: _mine);
      if (mounted) setState(() { _trip = t; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'state.offline'.tr);
    }
  }

  Future<void> _fuel(FleetTrip t) async {
    final saved = await Get.toNamed(Routes.erpFleetFuelNew, arguments: {'mine': _mine, 'tripId': t.id});
    if (saved == true) _load();
  }

  Future<void> _start(FleetTrip t) async {
    final message = await showVouchFlowDialog<String>(
      context,
      dialog: VouchFlowDialog(
        icon: PhosphorIconsRegular.playCircle,
        tone: VfTone.info,
        title: 'flt.startQ'.trParams({'number': t.number}),
        subtitle: 'flt.startSub'.tr,
        summary: [VfSummaryRow('flt.route'.tr, t.route), VfSummaryRow('flt.vehicle'.tr, t.vehicleLabel)],
        child: ConfirmActions(
          confirmLabel: 'flt.startTrip'.tr,
          fieldLabel: 'flt.odometerOut'.tr,
          fieldHint: 'flt.odometerOutHint'.tr,
          numeric: true,
          errorField: 'odometer_out',
          run: (v) => _repo.dispatch(t.id, odometerOut: double.tryParse(v.replaceAll(',', ''))),
        ),
      ),
    );
    if (message == null) return;
    showToast(message.isEmpty ? 'flt.trip.dispatched'.tr : message);
    _load();
  }

  Future<void> _end(FleetTrip t) async {
    final message = await showVouchFlowDialog<String>(
      context,
      dialog: VouchFlowDialog(
        icon: PhosphorIconsRegular.flagCheckered,
        tone: VfTone.ok,
        title: 'flt.endQ'.trParams({'number': t.number}),
        subtitle: 'flt.endSub'.tr,
        summary: [
          VfSummaryRow('flt.route'.tr, t.route),
          if (t.odometerOut != null) VfSummaryRow('flt.odometerOut'.tr, kmLabel(t.odometerOut)),
        ],
        child: ConfirmActions(
          confirmLabel: 'flt.endTrip'.tr,
          fieldLabel: 'flt.odometerIn'.tr,
          fieldRequired: t.vehicleId != null,
          numeric: true,
          errorField: 'odometer_in',
          run: (v) => _repo.complete(t.id, odometerIn: double.tryParse(v.replaceAll(',', ''))),
        ),
      ),
    );
    if (message == null) return;
    showToast(message.isEmpty ? 'flt.trip.completed'.tr : message);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = _trip;
    return VouchFlowPushedScaffold(
      title: t?.number ?? 'flt.trip'.tr,
      body: ErpGate(
        module: 'fleet',
        permission: _mine ? 'fleet.own' : 'fleet.view',
        builder: (context) => t == null
            ? (_error == null
                  ? const VfLoadingView()
                  : ErpPageBody(children: [VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)]))
            : _body(context, t),
      ),
      bottomBar: t == null ? null : _actions(t),
    );
  }

  Widget? _actions(FleetTrip t) {
    final buttons = <Widget>[
      if (!_mine && t.status == FleetTripStatus.planned && _erp.can('fleet.trips'))
        VouchFlowButton(label: 'flt.startTrip'.tr, icon: PhosphorIconsRegular.playCircle, onPressed: () => _start(t)),
      if (!_mine && t.status == FleetTripStatus.dispatched && _erp.can('fleet.trips'))
        VouchFlowButton(label: 'flt.endTrip'.tr, icon: PhosphorIconsRegular.flagCheckered, onPressed: () => _end(t)),
      if (t.takesFuel && (_mine ? _erp.can('fleet.own') : _erp.can('fleet.fuel')))
        VouchFlowButton(
          label: _mine ? 'flt.logFuel'.tr : 'flt.recordFuel'.tr,
          icon: PhosphorIconsRegular.gasPump,
          variant: !_mine && (t.status == FleetTripStatus.planned || t.status == FleetTripStatus.dispatched) && _erp.can('fleet.trips')
              ? VfButtonVariant.secondary
              : VfButtonVariant.primary,
          onPressed: () => _fuel(t),
        ),
    ];
    if (buttons.isEmpty) return null;
    return BottomActionBar(children: buttons.reversed.toList());
  }

  Widget _body(BuildContext context, FleetTrip t) {
    final vf = context.vf;
    final currency = _erp.currency;
    final costs = t.costs;
    final litres = t.fuel.where((f) => f.status != FleetEntryStatus.rejected).fold<double>(0, (s, f) => s + f.litres);

    return ErpPageBody(
      onRefresh: _load,
      children: [
        DetailHead(
          icon: PhosphorIconsRegular.path,
          tint: t.status == FleetTripStatus.dispatched ? vf.warningStrong : vf.primary,
          eyebrow: t.number,
          title: t.route,
          subtitle: [t.vehicleLabel, ?t.driver].where((s) => s.isNotEmpty).join(' · '),
          badge: TripStatusBadge(t.status, large: true),
        ),
        if (t.fuelOverStandard) ...[
          VouchFlowAlert(
            tone: VfTone.warn,
            icon: PhosphorIconsRegular.warning,
            title: 'flt.overStandard'.tr,
            message: 'flt.overStandardBody'.trParams({
              'actual': ErpFmt.qty(t.actualLitres ?? litres),
              'standard': ErpFmt.qty(t.standardLitres ?? 0),
            }),
          ),
          erpGap,
        ],
        VouchFlowPanel(
          title: 'flt.tripDetails'.tr,
          child: Column(
            children: [
              if (t.vehicleLabel.isNotEmpty) FactLine('flt.vehicle'.tr, t.vehicleLabel),
              if (t.driver != null) FactLine('flt.driver'.tr, t.driver!),
              if (t.customer != null) FactLine('flt.customer'.tr, t.customer!),
              if (t.cargo != null) FactLine('flt.cargo'.tr, t.cargo!),
              if (t.sourceReference != null) FactLine('flt.document'.tr, t.sourceReference!),
              if (t.distanceKm != null) FactLine('flt.distance'.tr, kmLabel(t.distanceKm)),
              FactLine('flt.plannedStart'.tr, dashDateTime(t.plannedStart)),
              if (t.actualStart != null) FactLine('flt.departed'.tr, dashDateTime(t.actualStart)),
              if (t.actualEnd != null) FactLine('flt.returned'.tr, dashDateTime(t.actualEnd)),
              if (t.odometerOut != null) FactLine('flt.odometerOut'.tr, kmLabel(t.odometerOut)),
              if (t.odometerIn != null) FactLine('flt.odometerIn'.tr, kmLabel(t.odometerIn)),
              if (t.kmDriven != null) FactLine('flt.kmDriven'.tr, kmLabel(t.kmDriven), strong: true),
            ],
          ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'flt.fuel'.tr,
          subtitle: t.fuel.isEmpty ? null : '${litresLabel(litres)}${t.standardLitres != null ? ' · ${'flt.standard'.tr} ${litresLabel(t.standardLitres!)}' : ''}',
          padded: false,
          child: t.fuel.isEmpty
              ? PanelEmpty(t.takesFuel ? 'flt.noFuel'.tr : 'flt.noFuelCustomer'.tr)
              : Column(
                  children: [
                    for (var i = 0; i < t.fuel.length; i++)
                      FuelRow(fuel: t.fuel[i], currency: currency, divider: i > 0, showTrip: false),
                  ],
                ),
        ),
        if (t.expenses.isNotEmpty) ...[
          erpGap,
          VouchFlowPanel(
            title: 'flt.expenses'.tr,
            padded: false,
            child: Column(
              children: [
                for (var i = 0; i < t.expenses.length; i++)
                  VouchFlowListRow(
                    divider: i > 0,
                    icon: PhosphorIconsRegular.receipt,
                    title: t.expenses[i].description ?? 'flt.exp.${t.expenses[i].type}'.tr,
                    subtitle: [
                      '$currency ${ErpFmt.amount(t.expenses[i].amount)}',
                      if (t.expenses[i].date != null) dashDate(t.expenses[i].date),
                    ].join(' · '),
                    trailing: EntryStatusBadge(t.expenses[i].status),
                  ),
              ],
            ),
          ),
        ],
        if (!_mine && costs != null) ...[
          erpGap,
          VouchFlowPanel(
            title: 'flt.costs'.tr,
            child: Column(
              children: [
                if (costs.revenue > 0) FactLine('flt.revenue'.tr, '$currency ${ErpFmt.amount(costs.revenue)}'),
                FactLine('flt.fuel'.tr, '$currency ${ErpFmt.amount(costs.fuel)}'),
                FactLine('flt.expenses'.tr, '$currency ${ErpFmt.amount(costs.expenses)}'),
                if (costs.hire > 0) FactLine('flt.hire'.tr, '$currency ${ErpFmt.amount(costs.hire)}'),
                if (costs.fixed > 0) FactLine('flt.fixed'.tr, '$currency ${ErpFmt.amount(costs.fixed)}'),
                FactLine('flt.totalCost'.tr, '$currency ${ErpFmt.amount(costs.total)}', strong: true),
                if (costs.revenue > 0) FactLine('flt.profit'.tr, '$currency ${ErpFmt.amount(costs.profit)}', strong: true),
                if (costs.pending > 0) FactLine('flt.pendingAmount'.tr, '$currency ${ErpFmt.amount(costs.pending)}'),
              ],
            ),
          ),
        ],
        if (t.notes != null) ...[
          erpGap,
          VouchFlowPanel(title: 'flt.notes'.tr, child: Text(t.notes!, style: VfType.small.copyWith(color: vf.text2))),
        ],
      ],
    );
  }
}
