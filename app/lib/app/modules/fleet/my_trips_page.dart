import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/fleet_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/fleet_repository.dart';
import '../../data/services/session_service.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDateTime;
import '../erp/erp_widgets.dart';
import 'fleet_widgets.dart';

/// A driver's home: the vehicle they drive, the trip they are on with one
/// big "Log fuel" button, and every trip they have driven (the web's
/// /erp/fleet/my-trips). Everything comes from /fleet/my-trips, the only
/// fleet data a driver may read.
class MyTripsPage extends StatelessWidget {
  const MyTripsPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'fleet',
    permission: 'fleet.own',
    builder: (_) => const _MyTrips(),
  );
}

class _MyTrips extends StatefulWidget {
  const _MyTrips();

  @override
  State<_MyTrips> createState() => _MyTripsState();
}

class _MyTripsState extends State<_MyTrips> {
  final _repo = FleetRepository.to;
  List<FleetTrip>? _trips;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final page = await _repo.trips(mine: true);
      if (mounted) setState(() { _trips = page.data; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'state.offline'.tr);
    }
  }

  Future<void> _open(FleetTrip trip) async {
    await Get.toNamed(Routes.erpFleetTrip, arguments: {'id': trip.id, 'mine': true});
    _load();
  }

  Future<void> _logFuel(FleetTrip? trip) async {
    final saved = await Get.toNamed(Routes.erpFleetFuelNew, arguments: {'mine': true, 'tripId': ?trip?.id});
    if (saved == true) _load();
  }

  /// The trip being driven now, else the next one planned.
  FleetTrip? _current(List<FleetTrip> trips) =>
      trips.where((t) => t.status == FleetTripStatus.dispatched).firstOrNull ??
      (trips.where((t) => t.status == FleetTripStatus.planned).toList()
            ..sort((a, b) => (a.plannedStart ?? DateTime(2100)).compareTo(b.plannedStart ?? DateTime(2100))))
          .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final trips = _trips;
    if (trips == null) {
      return _error == null
          ? const VfLoadingView()
          : ErpPageBody(onRefresh: _load, children: [VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)]);
    }
    final current = _current(trips);
    final latest = current ?? trips.firstOrNull;
    // The highest reading any trip recorded is the vehicle's last known one.
    final readings = [for (final t in trips) ...[?t.odometerOut, ?t.odometerIn]];
    final reading = readings.isEmpty ? null : readings.reduce((a, b) => a > b ? a : b);
    final name = Get.isRegistered<SessionService>() ? Get.find<SessionService>().user.value?.name : null;
    final fuelable = current != null && current.takesFuel ? current : trips.where((t) => t.takesFuel && t.status != FleetTripStatus.planned).firstOrNull;

    return ErpPageBody(
      onRefresh: _load,
      children: [
        ErpPageTitle('flt.myTrips'.tr, subtitle: name == null ? 'flt.myTripsSub'.tr : 'flt.hello'.trParams({'name': name.split(' ').first})),
        _VehicleCard(
          registration: latest?.vehicleLabel,
          reading: reading,
          licenceExpiry: latest?.licenceExpiry,
        ),
        erpGap,
        _CurrentTrip(
          trip: current,
          onOpen: current == null ? null : () => _open(current),
          onFuel: fuelable == null ? null : () => _logFuel(fuelable),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'flt.allMyTrips'.tr,
          subtitle: trips.isEmpty ? null : 'flt.tripCount'.trParams({'n': '${trips.length}'}),
          padded: false,
          child: trips.isEmpty
              ? PanelEmpty('flt.noTripsMine'.tr)
              : Column(
                  children: [
                    for (var i = 0; i < trips.length; i++)
                      TripRow(trip: trips[i], divider: i > 0, showDriver: false, onTap: () => _open(trips[i])),
                  ],
                ),
        ),
      ],
    );
  }
}

/// The driver's vehicle: its plate, last reading and the licence they drive on.
class _VehicleCard extends StatelessWidget {
  const _VehicleCard({this.registration, this.reading, this.licenceExpiry});

  final String? registration;
  final double? reading;
  final DateTime? licenceExpiry;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final (words, tone) = expiryWords(licenceExpiry);
    final (fg, bg) = tone.colors(t);
    return DecoratedBox(
      decoration: vfCardDecoration(t),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: t.primary.withValues(alpha: t.isDark ? .18 : .12), borderRadius: BorderRadius.circular(12)),
                  child: Icon(PhosphorIconsRegular.truck, size: 26, color: t.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('flt.myVehicle'.tr, style: VfType.label.copyWith(color: t.muted)),
                      const SizedBox(height: 2),
                      Text(
                        registration == null || registration!.isEmpty ? 'flt.noVehicle'.tr : registration!,
                        style: VfType.figure.copyWith(fontSize: 21, color: t.text, letterSpacing: .5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _Fact(label: 'flt.lastReading'.tr, value: kmLabel(reading))),
                const SizedBox(width: 10),
                Expanded(
                  child: _Fact(
                    label: 'flt.drivingLicence'.tr,
                    value: licenceExpiry == null ? '-' : words,
                    color: licenceExpiry == null || tone == VfTone.ok ? null : fg,
                    background: licenceExpiry == null || tone == VfTone.ok ? null : bg,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.color, this.background});

  final String label, value;
  final Color? color, background;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background ?? (t.isDark ? t.glassFillStrong : t.surface2),
        borderRadius: BorderRadius.circular(VfSize.radiusM),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: VfType.meta.copyWith(color: color ?? t.muted)),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 2,
            style: VfType.bodyStrong.copyWith(color: color ?? t.text, fontSize: 14.5, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}

/// The trip on the road now (or next), with the two things a driver does.
class _CurrentTrip extends StatelessWidget {
  const _CurrentTrip({required this.trip, required this.onOpen, required this.onFuel});

  final FleetTrip? trip;
  final VoidCallback? onOpen, onFuel;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final trip = this.trip;
    return VouchFlowPanel(
      title: trip?.status == FleetTripStatus.planned ? 'flt.nextTrip'.tr : 'flt.currentTrip'.tr,
      trailing: trip == null ? null : TripStatusBadge(trip.status),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (trip == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('flt.noTripNow'.tr, style: VfType.small.copyWith(color: t.muted)),
            )
          else ...[
            InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(VfSize.radiusM),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(trip.origin, style: VfType.small.copyWith(color: t.muted)),
                          Row(
                            children: [
                              Icon(PhosphorIconsBold.arrowDown, size: 14, color: t.primary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  trip.destination,
                                  style: VfType.sectionTitle.copyWith(color: t.text, fontSize: 18),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              trip.number,
                              if (trip.actualStart != null)
                                'flt.leftAt'.trParams({'time': dashDateTime(trip.actualStart)})
                              else if (trip.plannedStart != null)
                                'flt.leavesAt'.trParams({'time': dashDateTime(trip.plannedStart)}),
                            ].join(' · '),
                            style: VfType.meta.copyWith(color: t.text2),
                          ),
                          if (trip.cargo != null) ...[
                            const SizedBox(height: 2),
                            Text(trip.cargo!, maxLines: 2, overflow: TextOverflow.ellipsis, style: VfType.meta.copyWith(color: t.muted)),
                          ],
                        ],
                      ),
                    ),
                    Icon(PhosphorIconsBold.caretRight, size: 14, color: t.faint),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          VouchFlowButton(
            label: 'flt.logFuel'.tr,
            icon: PhosphorIconsRegular.gasPump,
            expand: true,
            height: 56,
            onPressed: onFuel,
          ),
          if (trip != null) ...[
            const SizedBox(height: 10),
            VouchFlowButton(
              label: 'flt.openTrip'.tr,
              variant: VfButtonVariant.secondary,
              expand: true,
              onPressed: onOpen,
            ),
          ],
        ],
      ),
    );
  }
}
