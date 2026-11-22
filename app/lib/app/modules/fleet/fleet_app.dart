import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../routes/routes.dart';
import '../shell/app_registry.dart';
import '../shell/nav.dart';
import 'fuel_page.dart';
import 'maintenance_page.dart';
import 'my_trips_page.dart';
import 'overview_page.dart';
import 'trips_page.dart';
import 'vehicles_page.dart';

/*
 * The Fleet app, as the shell sees it. Two audiences: a driver (fleet.own)
 * has one page, their vehicle, the trip they are on and the fuel they log;
 * fleet staff (fleet.view) have the overview, trips, vehicles, fuel and
 * maintenance. Each sees only the entries their permissions open, so a
 * driver lands straight on "My trips".
 */

const _fleet = 'fleet';

const fleetNav = [
  VfNavItem(
    '/erp/fleet/my',
    'flt.nav.my',
    PhosphorIconsRegular.steeringWheel,
    PhosphorIconsFill.steeringWheel,
    module: _fleet,
    permissions: ['fleet.own'],
  ),
  VfNavItem(
    '/erp/fleet',
    'flt.nav.overview',
    PhosphorIconsRegular.house,
    PhosphorIconsFill.house,
    module: _fleet,
    permissions: ['fleet.view'],
  ),
  VfNavItem(
    '/erp/fleet/trips',
    'flt.nav.trips',
    PhosphorIconsRegular.path,
    PhosphorIconsFill.path,
    module: _fleet,
    permissions: ['fleet.view'],
  ),
  VfNavItem(
    '/erp/fleet/vehicles',
    'flt.nav.vehicles',
    PhosphorIconsRegular.truck,
    PhosphorIconsFill.truck,
    module: _fleet,
    permissions: ['fleet.view'],
  ),
  VfNavItem(
    '/erp/fleet/fuel',
    'flt.nav.fuel',
    PhosphorIconsRegular.gasPump,
    PhosphorIconsFill.gasPump,
    module: _fleet,
    permissions: ['fleet.view'],
  ),
  VfNavItem(
    '/erp/fleet/maintenance',
    'flt.nav.maintenance',
    PhosphorIconsRegular.wrench,
    PhosphorIconsFill.wrench,
    module: _fleet,
    permissions: ['fleet.view'],
  ),
];

/// What the Fleet "+" offers: fuel, logged by a driver on their own trip or
/// issued by fleet staff on any trip. Planning a trip stays on the web.
const fleetCreateActions = [
  VfCreateAction(
    label: 'flt.logFuel',
    hint: 'flt.logFuelHint',
    icon: PhosphorIconsRegular.gasPump,
    route: Routes.erpFleetFuelNew,
    arguments: {'mine': true},
    permission: 'fleet.own',
  ),
  VfCreateAction(
    label: 'flt.recordFuel',
    hint: 'flt.recordFuelHint',
    icon: PhosphorIconsRegular.gasPump,
    route: Routes.erpFleetFuelNew,
    arguments: {'mine': false},
    permission: 'fleet.fuel',
  ),
];

final fleetApp = VfAppModule(
  area: _fleet,
  nav: fleetNav,
  pages: {
    '/erp/fleet/my': (_) => const MyTripsPage(),
    '/erp/fleet': (_) => const FleetOverviewPage(),
    '/erp/fleet/trips': (_) => const TripsPage(),
    '/erp/fleet/vehicles': (_) => const VehiclesPage(),
    '/erp/fleet/fuel': (_) => const FuelPage(),
    '/erp/fleet/maintenance': (_) => const MaintenancePage(),
  },
  create: fleetCreateActions,
);
