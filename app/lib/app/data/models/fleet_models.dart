import 'people_json.dart';

/*
 * The shapes /api/erp/fleet returns (Fleet\*Controller, the models' toArray):
 * vehicles, trips with their fuel, maintenance schedules and service records,
 * and the overview. A driver reads the same trip shape through my-trips,
 * without the ledger parts.
 */

abstract class FleetTripStatus {
  static const planned = 'planned';
  static const dispatched = 'dispatched';
  static const completed = 'completed';
  static const closed = 'closed';
  static const cancelled = 'cancelled';
  static const all = [planned, dispatched, completed, closed, cancelled];
}

abstract class FleetVehicleStatus {
  static const available = 'available';
  static const onTrip = 'on_trip';
  static const maintenance = 'maintenance';
  static const outOfService = 'out_of_service';
  static const all = [available, onTrip, maintenance, outOfService];
}

abstract class FleetEntryStatus {
  static const pending = 'pending';
  static const approved = 'approved';
  static const rejected = 'rejected';
  static const all = [pending, approved, rejected];
}

/// One fuel issue on a trip.
class FleetFuel {
  const FleetFuel({
    required this.id,
    required this.tripId,
    required this.issueDate,
    required this.litres,
    required this.pricePerLitre,
    required this.amount,
    required this.status,
    this.tripNumber,
    this.route,
    this.vehicle,
    this.station,
    this.receipt,
    this.odometer,
    this.recorder,
    this.rejectionReason,
    this.paidFrom,
  });

  factory FleetFuel.fromJson(Map<String, dynamic> j) {
    final trip = jmap(j['trip']);
    final account = jmap(j['account']);
    final supplier = jmap(j['supplier']);
    return FleetFuel(
      id: ji(j['id']),
      tripId: ji(j['trip_id']),
      issueDate: jday(j['issue_date']),
      litres: jd(j['litres']),
      pricePerLitre: jd(j['price_per_litre']),
      amount: jd(j['amount']),
      status: jstr(j['status']),
      tripNumber: js(trip?['number']),
      route: trip == null || trip['origin'] == null ? null : '${trip['origin']} to ${trip['destination']}',
      vehicle: js(jmap(j['vehicle'])?['registration_number']),
      station: js(j['station']),
      receipt: js(j['receipt_number']),
      odometer: jdn(j['odometer']),
      recorder: js(jmap(j['recorder'])?['name']),
      rejectionReason: js(j['rejection_reason']),
      paidFrom: supplier != null ? js(supplier['name']) : account == null ? null : js(account['name']),
    );
  }

  final int id, tripId;
  final DateTime? issueDate;
  final double litres, pricePerLitre, amount;
  final String status;
  final String? tripNumber, route, vehicle, station, receipt, recorder, rejectionReason, paidFrom;
  final double? odometer;

  bool get isPending => status == FleetEntryStatus.pending;
}

/// A trip expense (toll, allowance …), read for the trip page.
class FleetExpense {
  const FleetExpense({required this.id, required this.type, required this.amount, required this.status, this.description, this.date});

  factory FleetExpense.fromJson(Map<String, dynamic> j) => FleetExpense(
    id: ji(j['id']),
    type: jstr(j['type']),
    amount: jd(j['amount']),
    status: jstr(j['status']),
    description: js(j['description']),
    date: jday(j['expense_date']),
  );

  final int id;
  final String type, status;
  final double amount;
  final String? description;
  final DateTime? date;
}

/// What a trip has cost so far (TripController@detail `costs`).
class FleetTripCosts {
  const FleetTripCosts({
    required this.revenue,
    required this.fuel,
    required this.expenses,
    required this.hire,
    required this.fixed,
    required this.total,
    required this.profit,
    required this.pending,
    this.distanceKm,
    this.days,
  });

  static FleetTripCosts? fromJson(dynamic v) {
    final j = jmap(v);
    if (j == null) return null;
    return FleetTripCosts(
      revenue: jd(j['revenue']),
      fuel: jd(j['fuel']),
      expenses: jd(j['expenses']),
      hire: jd(j['hire']),
      fixed: jd(j['fixed']),
      total: jd(j['total_cost']),
      profit: jd(j['profit']),
      pending: jd(j['pending']),
      distanceKm: jdn(j['distance_km']),
      days: jin(j['days']),
    );
  }

  final double revenue, fuel, expenses, hire, fixed, total, profit, pending;
  final double? distanceKm;
  final int? days;
}

class FleetTrip {
  const FleetTrip({
    required this.id,
    required this.number,
    required this.status,
    required this.costOption,
    required this.origin,
    required this.destination,
    this.vehicleId,
    this.vehicle,
    this.externalVehicle,
    this.driverId,
    this.driver,
    this.driverPhone,
    this.driverVehicleId,
    this.licenceExpiry,
    this.customer,
    this.distanceKm,
    this.plannedStart,
    this.plannedEnd,
    this.actualStart,
    this.actualEnd,
    this.odometerOut,
    this.odometerIn,
    this.cargo,
    this.sourceReference,
    this.transportCharge = 0,
    this.fuelOverStandard = false,
    this.standardLitres,
    this.actualLitres,
    this.notes,
    this.fuel = const [],
    this.expenses = const [],
    this.costs,
  });

  factory FleetTrip.fromJson(Map<String, dynamic> j) {
    final vehicle = jmap(j['vehicle']);
    final driver = jmap(j['driver']);
    return FleetTrip(
      id: ji(j['id']),
      number: jstr(j['number']),
      status: jstr(j['status']),
      costOption: jstr(j['cost_option']),
      origin: jstr(j['origin']),
      destination: jstr(j['destination']),
      vehicleId: jin(j['vehicle_id']),
      vehicle: js(vehicle?['registration_number']),
      externalVehicle: js(j['external_vehicle']),
      driverId: jin(j['driver_id']),
      driver: js(jmap(driver?['user'])?['name']),
      driverPhone: js(driver?['phone']) ?? js(jmap(driver?['user'])?['phone']),
      driverVehicleId: jin(driver?['vehicle_id']),
      licenceExpiry: jday(driver?['licence_expiry']),
      customer: js(jmap(j['customer'])?['name']),
      distanceKm: jdn(j['distance_km']),
      plannedStart: jtime(j['planned_start']),
      plannedEnd: jtime(j['planned_end']),
      actualStart: jtime(j['actual_start']),
      actualEnd: jtime(j['actual_end']),
      odometerOut: jdn(j['odometer_out']),
      odometerIn: jdn(j['odometer_in']),
      cargo: js(j['cargo_description']),
      sourceReference: js(j['source_reference']),
      transportCharge: jd(j['transport_charge']),
      fuelOverStandard: jb(j['fuel_over_standard']),
      standardLitres: jdn(j['standard_litres']),
      actualLitres: jdn(j['actual_litres']),
      notes: js(j['notes']),
      fuel: jlist(j['fuel_issues'], FleetFuel.fromJson),
      expenses: jlist(j['expenses'], FleetExpense.fromJson),
      costs: FleetTripCosts.fromJson(j['costs']),
    );
  }

  final int id;
  final String number, status, costOption, origin, destination;
  final int? vehicleId, driverId, driverVehicleId;
  final String? vehicle, externalVehicle, driver, driverPhone, customer, cargo, sourceReference, notes;
  final DateTime? licenceExpiry, plannedStart, plannedEnd, actualStart, actualEnd;
  final double? distanceKm, odometerOut, odometerIn, standardLitres, actualLitres;
  final double transportCharge;
  final bool fuelOverStandard;
  final List<FleetFuel> fuel;
  final List<FleetExpense> expenses;
  final FleetTripCosts? costs;

  String get route => '$origin to $destination';
  String get vehicleLabel => vehicle ?? externalVehicle ?? '';

  /// On the road or about to be: the trip a driver is working on.
  bool get isOpen => status == FleetTripStatus.planned || status == FleetTripStatus.dispatched;

  /// The company carries costs on it, and it is not closed or cancelled.
  bool get takesFuel =>
      costOption != 'customer_vehicle' && status != FleetTripStatus.closed && status != FleetTripStatus.cancelled;

  double? get kmDriven => odometerOut != null && odometerIn != null ? odometerIn! - odometerOut! : null;
}

/// A maintenance schedule and how due it is ('ok' | 'due' | 'overdue').
class FleetSchedule {
  const FleetSchedule({
    required this.id,
    required this.title,
    required this.state,
    this.vehicleId,
    this.vehicle,
    this.vehicleOdometer,
    this.intervalKm,
    this.intervalDays,
    this.nextDueOdometer,
    this.nextDueDate,
    this.lastDoneDate,
  });

  factory FleetSchedule.fromJson(Map<String, dynamic> j) {
    final v = jmap(j['vehicle']);
    return FleetSchedule(
      id: ji(j['id']),
      title: jstr(j['title']),
      state: js(j['state']) ?? 'ok',
      vehicleId: jin(j['vehicle_id']),
      vehicle: js(v?['registration_number']),
      vehicleOdometer: jdn(v?['odometer']),
      intervalKm: jin(j['interval_km']),
      intervalDays: jin(j['interval_days']),
      nextDueOdometer: jdn(j['next_due_odometer']),
      nextDueDate: jday(j['next_due_date']),
      lastDoneDate: jday(j['last_done_date']),
    );
  }

  final int id;
  final String title, state;
  final int? vehicleId, intervalKm, intervalDays;
  final String? vehicle;
  final double? vehicleOdometer, nextDueOdometer;
  final DateTime? nextDueDate, lastDoneDate;
}

/// A service record: a draft until posted to the ledger.
class FleetService {
  const FleetService({
    required this.id,
    required this.number,
    required this.status,
    required this.workDone,
    required this.cost,
    this.vehicle,
    this.date,
    this.odometer,
    this.garage,
    this.invoice,
  });

  factory FleetService.fromJson(Map<String, dynamic> j) => FleetService(
    id: ji(j['id']),
    number: jstr(j['number']),
    status: jstr(j['status']),
    workDone: jstr(j['work_done']),
    cost: jd(j['cost']),
    vehicle: js(jmap(j['vehicle'])?['registration_number']),
    date: jday(j['service_date']),
    odometer: jdn(j['odometer']),
    garage: js(jmap(j['supplier'])?['name']),
    invoice: js(j['invoice_number']),
  );

  final int id;
  final String number, status, workDone;
  final double cost;
  final String? vehicle, garage, invoice;
  final DateTime? date;
  final double? odometer;
}

class FleetVehicle {
  const FleetVehicle({
    required this.id,
    required this.registration,
    required this.type,
    required this.ownership,
    required this.status,
    required this.odometer,
    this.make,
    this.model,
    this.year,
    this.capacity,
    this.capacityUnit,
    this.insurer,
    this.policyNumber,
    this.insuranceExpiry,
    this.roadLicenceNumber,
    this.roadLicenceExpiry,
    this.driver,
    this.owner,
    this.hireIncludesFuel = false,
    this.monthlyFixedCost,
    this.schedules = const [],
    this.services = const [],
    this.trips = const [],
    this.fuel = const [],
    this.offRoadSince,
  });

  factory FleetVehicle.fromJson(Map<String, dynamic> j) => FleetVehicle(
    id: ji(j['id']),
    registration: jstr(j['registration_number']),
    type: jstr(j['type']),
    ownership: jstr(j['ownership']),
    status: jstr(j['status']),
    odometer: jd(j['odometer']),
    make: js(j['make']),
    model: js(j['model']),
    year: jin(j['year']),
    capacity: jdn(j['capacity']),
    capacityUnit: js(j['capacity_unit']),
    insurer: js(j['insurer']),
    policyNumber: js(j['insurance_policy_number']),
    insuranceExpiry: jday(j['insurance_expiry']),
    roadLicenceNumber: js(j['road_licence_number']),
    roadLicenceExpiry: jday(j['road_licence_expiry']),
    driver: js(jmap(jmap(j['driver'])?['user'])?['name']),
    owner: js(jmap(j['supplier'])?['name']),
    hireIncludesFuel: jb(j['hire_includes_fuel']),
    monthlyFixedCost: jdn(j['monthly_fixed_cost']),
    schedules: jlist(j['schedules'], FleetSchedule.fromJson),
    services: jlist(j['services'], FleetService.fromJson),
    trips: jlist(j['trips'], FleetTrip.fromJson),
    fuel: jlist(j['fuel'], FleetFuel.fromJson),
    offRoadSince: jtime(jmap(j['open_downtime'])?['started_at']),
  );

  final int id;
  final String registration, type, ownership, status;
  final double odometer;
  final String? make, model, capacityUnit, insurer, policyNumber, roadLicenceNumber, driver, owner;
  final int? year;
  final double? capacity, monthlyFixedCost;
  final DateTime? insuranceExpiry, roadLicenceExpiry, offRoadSince;
  final bool hireIncludesFuel;
  final List<FleetSchedule> schedules;
  final List<FleetService> services;
  final List<FleetTrip> trips;
  final List<FleetFuel> fuel;

  String get title => [make, model].whereType<String>().join(' ');
  bool get isHired => ownership == 'hired';

  /// The paper that runs out first, when one runs out within 30 days.
  DateTime? get firstExpiry {
    final dates = [insuranceExpiry, roadLicenceExpiry].whereType<DateTime>().toList()..sort();
    return dates.firstOrNull;
  }
}

/// A paper running out (insurance, road licence, driving licence).
class FleetExpiring {
  const FleetExpiring({required this.kind, required this.subject, required this.date, required this.expired, this.vehicleId});

  factory FleetExpiring.fromJson(Map<String, dynamic> j) => FleetExpiring(
    kind: jstr(j['kind']),
    subject: jstr(j['subject']),
    date: jday(j['date']),
    expired: jb(j['expired']),
    vehicleId: jin(j['vehicle_id']),
  );

  final String kind, subject;
  final DateTime? date;
  final bool expired;
  final int? vehicleId;
}

/// GET /erp/fleet/overview.
class FleetOverview {
  const FleetOverview({
    required this.vehicles,
    required this.byStatus,
    required this.tripsToday,
    required this.fuelAlerts,
    required this.expiring,
    required this.maintenanceDue,
    required this.pendingEntries,
    required this.tripsClosed,
    required this.revenue,
    required this.cost,
    required this.profit,
    required this.litres,
  });

  factory FleetOverview.fromJson(Map<String, dynamic> j) {
    final v = jmap(j['vehicles']) ?? const {};
    final month = jmap(j['month']) ?? const {};
    return FleetOverview(
      vehicles: ji(v['total']),
      byStatus: {for (final e in (jmap(v['by_status']) ?? const {}).entries) e.key: ji(e.value)},
      tripsToday: jlist(j['trips_today'], FleetTrip.fromJson),
      fuelAlerts: jlist(j['fuel_alerts'], FleetTrip.fromJson),
      expiring: jlist(j['expiring'], FleetExpiring.fromJson),
      maintenanceDue: jlist(j['maintenance_due'], FleetSchedule.fromJson),
      pendingEntries: ji(j['pending_entries']),
      tripsClosed: ji(month['trips_closed']),
      revenue: jd(month['revenue']),
      cost: jd(month['cost']),
      profit: jd(month['profit']),
      litres: jd(month['litres']),
    );
  }

  final int vehicles, pendingEntries, tripsClosed;
  final Map<String, int> byStatus;
  final List<FleetTrip> tripsToday, fuelAlerts;
  final List<FleetExpiring> expiring;
  final List<FleetSchedule> maintenanceDue;
  final double revenue, cost, profit, litres;

  int get onTrip => byStatus[FleetVehicleStatus.onTrip] ?? 0;
}

/// Where fuel money can come from: a cash or bank account, or a supplier's
/// credit (the web's PaymentSource).
class FleetPayLookups {
  const FleetPayLookups({required this.accounts, required this.suppliers});

  factory FleetPayLookups.fromJson(Map<String, dynamic> j) => FleetPayLookups(
    accounts: jlist(j['accounts'], FleetPick.fromJson),
    suppliers: jlist(j['suppliers'], FleetPick.fromJson),
  );

  final List<FleetPick> accounts, suppliers;
}

class FleetPick {
  const FleetPick(this.id, this.name, {this.code, this.category});

  factory FleetPick.fromJson(Map<String, dynamic> j) =>
      FleetPick(ji(j['id']), jstr(j['name']), code: js(j['code']), category: js(j['category']));

  final int id;
  final String name;
  final String? code, category;

  String get label => code == null ? name : '$code $name';
}

/// A fuel entry being keyed in (TripController@fuelRules).
class FuelDraft {
  String litres = '';
  String price = '';
  String station = '';
  String receipt = '';
  String odometer = '';
  DateTime date = DateTime.now();

  /// 'account' (cash or bank) or 'supplier' (credit).
  String paidBy = 'account';
  int? accountId;
  int? supplierId;

  double? get litresValue => double.tryParse(litres.replaceAll(',', ''));
  double? get priceValue => double.tryParse(price.replaceAll(',', ''));
  double get amount => (litresValue ?? 0) * (priceValue ?? 0);

  Map<String, dynamic> toJson() => {
    'issue_date': jdate(date),
    'litres': litresValue,
    'price_per_litre': priceValue,
    if (station.trim().isNotEmpty) 'station': station.trim(),
    if (receipt.trim().isNotEmpty) 'receipt_number': receipt.trim(),
    'odometer': ?double.tryParse(odometer.replaceAll(',', '')),
    if (paidBy == 'account') 'account_id': accountId,
    if (paidBy == 'supplier') 'supplier_id': supplierId,
  };
}
