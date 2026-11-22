import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/fleet_models.dart';
import '../../data/models/people_json.dart';
import '../../data/services/fleet_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../erp/erp_widgets.dart';
import 'fleet_widgets.dart';
import 'paged_list.dart';

/// The vehicle register: owned and hired vehicles with their status, driver
/// and reading, and a warning when a paper runs out within 30 days (the
/// web's /erp/fleet/vehicles).
class VehiclesPage extends StatelessWidget {
  const VehiclesPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'fleet',
    permission: 'fleet.view',
    builder: (_) => PagedListBody<FleetVehicle>(
      title: 'flt.nav.vehicles'.tr,
      subtitle: 'flt.vehiclesSub'.tr,
      searchPlaceholder: 'flt.searchVehicles'.tr,
      statuses: const [null, ...FleetVehicleStatus.all],
      statusLabel: (s) => s == null ? 'flt.all'.tr : vehicleStatusLabel(s),
      load: (q, status, page) => FleetRepository.to.vehicles(q: q, status: status, page: page),
      emptyText: 'flt.noVehicles'.tr,
      emptyIcon: PhosphorIconsRegular.truck,
      row: (context, v, i, reload) => VehicleRow(
        vehicle: v,
        divider: i > 0,
        onTap: () async {
          await Get.toNamed(Routes.erpFleetVehicle, arguments: v.id);
          reload();
        },
      ),
    ),
  );
}

class VehicleRow extends StatelessWidget {
  const VehicleRow({super.key, required this.vehicle, required this.onTap, this.divider = true});

  final FleetVehicle vehicle;
  final VoidCallback onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final v = vehicle;
    final expiry = v.firstExpiry;
    final soon = expiry != null && daysUntil(expiry) <= 30;
    return VouchFlowListRow(
      divider: divider,
      icon: soon ? PhosphorIconsRegular.warning : PhosphorIconsRegular.truck,
      iconColor: soon ? (daysUntil(expiry) < 0 ? t.dangerStrong : t.warningStrong) : t.primary,
      title: v.registration,
      subtitle: [
        if (v.title.isNotEmpty) v.title,
        if (v.isHired) 'flt.hired'.tr,
        ?v.driver,
        kmLabel(v.odometer),
        if (soon) expiryWords(expiry).$1,
      ].join(' · '),
      trailing: VehicleStatusBadge(v.status),
      onTap: onTap,
    );
  }
}
