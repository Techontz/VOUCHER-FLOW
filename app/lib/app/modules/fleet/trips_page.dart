import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/models/fleet_models.dart';
import '../../data/services/fleet_repository.dart';
import '../../routes/routes.dart';
import '../erp/erp_widgets.dart';
import 'fleet_widgets.dart';
import 'paged_list.dart';

/// Every trip, newest first, by status and searchable by number, place,
/// document or cargo (the web's /erp/fleet/trips). A trip opens on its page,
/// where it is started and ended.
class TripsPage extends StatelessWidget {
  const TripsPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'fleet',
    permission: 'fleet.view',
    builder: (_) => PagedListBody<FleetTrip>(
      title: 'flt.nav.trips'.tr,
      subtitle: 'flt.tripsSub'.tr,
      searchPlaceholder: 'flt.searchTrips'.tr,
      statuses: const [null, ...FleetTripStatus.all],
      statusLabel: (s) => s == null ? 'flt.all'.tr : tripStatusLabel(s),
      load: (q, status, page) => FleetRepository.to.trips(q: q, status: status, page: page),
      emptyText: 'flt.noTrips'.tr,
      emptyIcon: PhosphorIconsRegular.path,
      row: (context, trip, i, reload) => TripRow(
        trip: trip,
        divider: i > 0,
        onTap: () async {
          await Get.toNamed(Routes.erpFleetTrip, arguments: {'id': trip.id, 'mine': false});
          reload();
        },
      ),
    ),
  );
}
