import '../services/api_service.dart';

/// The in-app stand-in for /api/erp/fleet and /api/erp/hr, answering the
/// same paths with the same JSON shapes as the Laravel controllers
/// (Fleet\*Controller, Hr\*Controller, Hr\SelfServiceController), so the
/// Fleet and HR apps run, and are tested, without a server.
///
/// Recording fuel, starting and ending a trip, deciding fuel and leave,
/// and applying for or cancelling leave all change the fixture, so a flow
/// reads back the way it would against the API.
class MockPeople {
  MockPeople() {
    _seed();
  }

  /// What the built-in roles hold in these two modules (backend
  /// app/Support/Erp/Modules/Fleet.php and Hr.php), trimmed to the mock's roles.
  static List<String> rolePermissions(String role) => switch (role) {
    'company_admin' => const [
      'fleet.view', 'fleet.manage', 'fleet.trips', 'fleet.fuel', 'fleet.expenses', 'fleet.maintenance', 'fleet.approve', //
      'hr.view', 'hr.manage', 'hr.salary', 'hr.attendance', 'hr.leave.approve', 'hr.payroll.prepare', 'hr.self',
    ],
    'finance' => const ['fleet.view', 'fleet.approve', 'hr.view', 'hr.salary', 'hr.payroll.authorise', 'hr.payroll.post', 'hr.self'],
    'ceo' || 'director' => const ['fleet.view', 'hr.view', 'hr.self'],
    'hod' || 'manager' => const ['hr.leave.approve', 'hr.self'],
    _ => const ['hr.self'],
  };

  /* ═══════════════════════════════════════════════════════ the dataset ══ */

  final vehicles = <Map<String, dynamic>>[];
  final trips = <Map<String, dynamic>>[];
  final fuel = <Map<String, dynamic>>[];
  final schedules = <Map<String, dynamic>>[];
  final services = <Map<String, dynamic>>[];
  final employees = <Map<String, dynamic>>[];
  final leave = <Map<String, dynamic>>[];
  final attendance = <Map<String, dynamic>>[];
  final runs = <Map<String, dynamic>>[];
  final payslips = <Map<String, dynamic>>[];
  int _nextFuel = 100, _nextLeave = 50;

  static DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static String _day(int offset) {
    final d = _today.add(Duration(days: offset));
    return '${d.year}-${'${d.month}'.padLeft(2, '0')}-${'${d.day}'.padLeft(2, '0')}';
  }

  static String _at(int dayOffset, int hour) => '${_day(dayOffset)}T${'$hour'.padLeft(2, '0')}:00:00.000000Z';

  static const _driver = {
    'id': 1,
    'user_id': 68,
    'licence_number': 'DL-4002198871',
    'licence_class': 'E',
    'phone': '+255 718 449 394',
    'vehicle_id': 1,
    'daily_allowance': '25000.00',
    'user': {'id': 68, 'name': 'Juma Mrisho'},
  };

  static const _accounts = [
    {'id': 1, 'code': '1100', 'name': 'Cash on hand'},
    {'id': 3, 'code': '1200', 'name': 'Bank'},
  ];
  static const _suppliers = [
    {'id': 8, 'code': 'SUP-FLT-03', 'name': 'Kariakoo Motors Garage', 'category': 'Fleet'},
    {'id': 9, 'code': 'SUP-FLT-04', 'name': 'Puma Energy Ubungo', 'category': 'Fuel'},
  ];

  void _seed() {
    Map<String, dynamic> vehicle(int id, String reg, String make, String model, String status, double odo, int insuranceDays, int licenceDays) => {
      'id': id,
      'registration_number': reg,
      'make': make,
      'model': model,
      'type': 'truck',
      'year': 2019,
      'capacity': '10.000',
      'capacity_unit': 'tonnes',
      'ownership': 'owned',
      'hire_includes_fuel': false,
      'odometer': odo.toStringAsFixed(1),
      'status': status,
      'insurer': 'Jubilee Allianz',
      'insurance_policy_number': 'JA-MV-$id',
      'insurance_expiry': _day(insuranceDays),
      'road_licence_number': 'RL-$id',
      'road_licence_expiry': _day(licenceDays),
      'is_active': true,
      'supplier': null,
      'driver': id == 1 ? _driver : null,
    };
    vehicles.addAll([
      vehicle(1, 'T 101 DXA', 'Isuzu', 'FVZ 1400', 'on_trip', 152492, 210, 150),
      vehicle(2, 'T 214 DYB', 'Mitsubishi', 'Fuso Fighter', 'available', 203999, 18, 120),
      vehicle(3, 'T 552 EBB', 'Scania', 'P410', 'maintenance', 178859, 300, -3),
    ]);

    Map<String, dynamic> trip(int id, String status, int vehicleId, String from, String to, int startDay, {double? out, double? inn}) => {
      'id': id,
      'number': 'TRP-2026-${'$id'.padLeft(6, '0')}',
      'cost_option': 'charged',
      'vehicle_id': vehicleId,
      'driver_id': 1,
      'external_vehicle': null,
      'customer_id': 1,
      'origin': from,
      'destination': to,
      'distance_km': '640.0',
      'planned_start': _at(startDay, 6),
      'planned_end': _at(startDay + 1, 18),
      'actual_start': status == 'planned' ? null : _at(startDay, 7),
      'actual_end': status == 'completed' || status == 'closed' ? _at(startDay + 1, 17) : null,
      'odometer_out': out?.toStringAsFixed(1),
      'odometer_in': inn?.toStringAsFixed(1),
      'source_reference': 'LO-2026-000${300 + id}',
      'cargo_description': '350 cartons 500ml and 350 cartons 1.5L',
      'transport_charge': '1410000.00',
      'hire_cost': '0.00',
      'standard_litres': null,
      'actual_litres': null,
      'fuel_over_standard': false,
      'status': status,
      'notes': null,
      'vehicle': {'id': vehicleId, 'registration_number': vehicles.firstWhere((v) => v['id'] == vehicleId)['registration_number']},
      'driver': _driver,
      'customer': {'id': 1, 'name': 'Shoppers Supermarket: Masaki'},
    };
    trips.addAll([
      trip(31, 'dispatched', 1, 'Dar es Salaam', 'Arusha', -1, out: 152492),
      trip(32, 'planned', 2, 'Dar es Salaam', 'Morogoro', 2),
      trip(30, 'completed', 1, 'Dar es Salaam', 'Dodoma', -4, out: 151570, inn: 152492),
      trip(29, 'closed', 1, 'Dar es Salaam', 'Tanga', -8, out: 150900, inn: 151570),
    ]);

    fuel.addAll([
      _fuel(55, 31, 1, 180, 3150, 'Lake Oil Chalinze', 'pending', 0),
      _fuel(54, 30, 1, 210, 3150, 'Puma Morogoro', 'approved', -4),
    ]);

    schedules.addAll([
      {'id': 1, 'vehicle_id': 1, 'title': 'Engine oil, filters and greasing', 'interval_km': 10000, 'interval_days': 90, 'last_done_odometer': '143092.0', 'last_done_date': _day(-20), 'next_due_odometer': '153092.0', 'next_due_date': _day(70), 'is_active': true, 'state': 'due'},
      {'id': 9, 'vehicle_id': 3, 'title': 'Brake inspection', 'interval_km': null, 'interval_days': 180, 'last_done_odometer': null, 'last_done_date': _day(-186), 'next_due_odometer': null, 'next_due_date': _day(-6), 'is_active': true, 'state': 'overdue'},
      {'id': 2, 'vehicle_id': 2, 'title': 'Tyre rotation', 'interval_km': 20000, 'interval_days': null, 'last_done_odometer': '200000.0', 'last_done_date': _day(-40), 'next_due_odometer': '220000.0', 'next_due_date': null, 'is_active': true, 'state': 'ok'},
    ]);
    services.add({
      'id': 5, 'number': 'SRV-2026-000005', 'vehicle_id': 2, 'service_date': _day(0), 'odometer': '203999.0',
      'work_done': 'Clutch plate and pressure plate replacement', 'cost': '1450000.00', 'invoice_number': 'KMG-4188',
      'status': 'draft', 'supplier': {'id': 8, 'name': 'Kariakoo Motors Garage'},
    });

    Map<String, dynamic> employee(int id, String number, String name, String email, String job, String dept, double basic, {String status = 'active'}) => {
      'id': id,
      'employee_number': number,
      'full_name': name,
      'email': email,
      'phone': '0767 0${id}7 898',
      'national_id': '19920101-73307-8541$id-50',
      'tin': '184-037-37$id',
      'nssf_number': '40393659$id',
      'date_of_birth': '1992-01-0$id',
      'gender': id.isEven ? 'female' : 'male',
      'address': 'Mbezi Beach, Dar es Salaam',
      'next_of_kin_name': 'Mary ${name.split(' ').last}',
      'next_of_kin_phone': '0787 592 61$id',
      'next_of_kin_relation': 'Spouse',
      'employment_type': 'permanent',
      'job_title': job,
      'grade': 'S3',
      'department': {'id': id, 'name': dept},
      'manager': {'id': 2, 'full_name': 'Anna Lyimo'},
      'hire_date': '2022-11-01',
      'probation_end': '2023-05-01',
      'status': status,
      'contract': {
        'type': 'permanent', 'start_date': '2026-01-01', 'end_date': null, 'status': 'active',
        'basic_salary': basic, 'housing_allowance': 100000, 'transport_allowance': 80000, 'other_allowance': 0,
        'gross_salary': basic + 180000,
      },
      'bank_name': 'NMB',
      'bank_account_number': '20410393659$id',
      'salary_visible': true,
    };
    employees.addAll([
      employee(1, 'WC-0170', 'Neema Swai', 'neema@watercom.test', 'Storekeeper', 'Production', 850000),
      employee(2, 'WC-0061', 'Anna Lyimo', 'anna@watercom.test', 'Head of Human Resources', 'Human Resources', 3200000),
      employee(3, 'WC-0129', 'Baraka Mollel', 'baraka@watercom.test', 'Transport Supervisor', 'Transport & Logistics', 1250000),
      employee(4, 'WC-0114', 'Frank Kessy', 'frank@watercom.test', 'Procurement Officer', 'Procurement', 1350000),
    ]);

    leave.addAll([
      _leave(5, 1, 'annual', _day(18), _day(22), 5, 'pending', 'End of year break'),
      _leave(4, 3, 'sick', _day(-12), _day(-11), 2, 'approved', null),
      _leave(3, 4, 'annual', _day(-2), _day(3), 4, 'approved', 'Family visit'),
    ]);

    // This month's attendance for everyone, weekdays up to today.
    final first = DateTime(_today.year, _today.month);
    for (var d = first; !d.isAfter(_today); d = d.add(const Duration(days: 1))) {
      if (d.weekday > 5) continue;
      for (final e in employees) {
        final id = e['id'] as int;
        final late = (d.day + id) % 7 == 0;
        final today = d == _today;
        attendance.add({
          'id': attendance.length + 1,
          'employee_id': id,
          'date': '${d.year}-${'${d.month}'.padLeft(2, '0')}-${'${d.day}'.padLeft(2, '0')}T00:00:00.000000Z',
          'check_in': late ? '08:21:00' : '07:5$id:00',
          'check_out': today ? null : '17:${10 + id}:00',
          'status': late ? 'late' : 'present',
          'hours_worked': today ? '0.00' : (late ? '8.80' : '9.20'),
          'overtime_hours': today || late ? '0.00' : '0.20',
          'source': 'import',
          'note': null,
        });
      }
    }

    final last = DateTime(_today.year, _today.month - 1);
    final lastPeriod = '${last.year}-${'${last.month}'.padLeft(2, '0')}';
    final thisPeriod = '${_today.year}-${'${_today.month}'.padLeft(2, '0')}';
    runs.addAll([
      _run(4, thisPeriod, 'draft', null),
      _run(3, lastPeriod, 'paid', '$lastPeriod-28T00:00:00.000000Z'),
    ]);
    var slip = 100;
    for (final r in runs) {
      for (final e in employees) {
        payslips.add(_payslip(++slip, r, e));
      }
    }
    for (final r in runs) {
      final mine = payslips.where((p) => p['payroll_run_id'] == r['id']).toList();
      double sum(String k) => mine.fold(0.0, (s, p) => s + double.parse('${p[k]}'));
      r['gross'] = sum('gross').toStringAsFixed(2);
      r['total_deductions'] = sum('total_deductions').toStringAsFixed(2);
      r['net'] = sum('net').toStringAsFixed(2);
      r['paye'] = sum('paye').toStringAsFixed(2);
      r['nssf_employee'] = sum('nssf_employee').toStringAsFixed(2);
      r['nssf_employer'] = sum('nssf_employer').toStringAsFixed(2);
      r['wcf'] = sum('wcf').toStringAsFixed(2);
      r['sdl'] = sum('sdl').toStringAsFixed(2);
      r['employees_count'] = mine.length;
    }
  }

  Map<String, dynamic> _fuel(int id, int tripId, int vehicleId, double litres, double price, String station, String status, int day) => {
    'id': id,
    'trip_id': tripId,
    'vehicle_id': vehicleId,
    'issue_date': _day(day),
    'litres': litres.toStringAsFixed(3),
    'price_per_litre': price.toStringAsFixed(2),
    'amount': (litres * price).toStringAsFixed(2),
    'station': station,
    'receipt_number': 'FR-55$id',
    'odometer': null,
    'account_id': 1,
    'supplier_id': null,
    'status': status,
    'rejection_reason': null,
    'recorder': {'id': 68, 'name': 'Juma Mrisho'},
    'account': _accounts.first,
    'supplier': null,
  };

  static const _types = [
    {'id': 1, 'code': 'annual', 'name': 'Annual leave', 'days_per_year': '28.00', 'paid': true, 'counting': 'working', 'is_active': true},
    {'id': 2, 'code': 'sick', 'name': 'Sick leave', 'days_per_year': '63.00', 'paid': true, 'counting': 'working', 'is_active': true},
    {'id': 6, 'code': 'unpaid', 'name': 'Unpaid leave', 'days_per_year': '0.00', 'paid': false, 'counting': 'working', 'is_active': true},
  ];

  Map<String, dynamic> _leave(int id, int employeeId, String code, String start, String end, double days, String status, String? reason) {
    final e = employees.firstWhere((x) => x['id'] == employeeId);
    final type = _types.firstWhere((t) => t['code'] == code);
    return {
      'id': id,
      'employee_id': employeeId,
      'leave_type_id': type['id'],
      'start_date': '${start}T00:00:00.000000Z',
      'end_date': '${end}T00:00:00.000000Z',
      'days': days.toStringAsFixed(2),
      'reason': reason,
      'status': status,
      'decision_note': null,
      'employee': {'id': employeeId, 'full_name': e['full_name'], 'employee_number': e['employee_number'], 'department': e['department']},
      'leave_type': {'id': type['id'], 'name': type['name'], 'code': code, 'paid': type['paid']},
      'decider': status == 'approved' ? {'id': 5, 'name': 'Anna Lyimo'} : null,
    };
  }

  Map<String, dynamic> _run(int id, String period, String status, String? paid) => {
    'id': id,
    'number': 'PAY-2026-${'$id'.padLeft(6, '0')}',
    'period': period,
    'period_start': '$period-01T00:00:00.000000Z',
    'status': status,
    'payment_date': paid,
    'notes': null,
    'preparer': {'id': 74, 'name': 'Amina Mfinanga'},
    'authoriser': status == 'draft' ? null : {'id': 6, 'name': 'Rehema Kweka'},
  };

  Map<String, dynamic> _payslip(int id, Map<String, dynamic> run, Map<String, dynamic> e) {
    final c = e['contract'] as Map;
    final basic = (c['basic_salary'] as num).toDouble();
    final gross = basic + 180000;
    final nssf = gross * .1;
    final paye = (gross - nssf) * .2;
    final total = nssf + paye;
    String f(num v) => v.toStringAsFixed(2);
    return {
      'id': id,
      'payroll_run_id': run['id'],
      'employee_id': e['id'],
      'employee_number': e['employee_number'],
      'employee_name': e['full_name'],
      'department': (e['department'] as Map)['name'],
      'job_title': e['job_title'],
      'bank_name': e['bank_name'],
      'bank_account_number': e['bank_account_number'],
      'days_paid': '30.00',
      'unpaid_days': '0.00',
      'overtime_hours': '0.00',
      'basic': f(basic),
      'housing_allowance': '100000.00',
      'transport_allowance': '80000.00',
      'other_allowance': '0.00',
      'overtime': '0.00',
      'other_earnings': '0.00',
      'absence_deduction': '0.00',
      'gross': f(gross),
      'nssf_employee': f(nssf),
      'taxable': f(gross - nssf),
      'paye': f(paye),
      'heslb': '0.00',
      'loans': '0.00',
      'other_deductions': '0.00',
      'total_deductions': f(total),
      'net': f(gross - total),
      'nssf_employer': f(nssf),
      'wcf': f(gross * .005),
      'sdl': f(gross * .035),
      'lines': {'earnings': [], 'deductions': [], 'loans': []},
    };
  }

  /* ══════════════════════════════════════════════════════════ dispatch ══ */

  /// Answers one /erp/fleet or /erp/hr request, [rest] being the path after
  /// /erp/; null when the fixture does not answer it.
  Object? handle(
    String method,
    List<String> rest, {
    required List<String> perms,
    required List<String> modules,
    required String email,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
  }) {
    void need(String p) {
      if (!perms.contains(p)) throw ApiException(403, 'Your role does not allow this.');
    }

    final module = rest.first;
    if (!modules.contains(module)) {
      throw ApiException(403, 'The $module module is not switched on for your company.');
    }
    final r = rest.skip(1).toList();
    return module == 'fleet' ? _fleet(method, r, need, perms, body, query) : _hr(method, r, need, perms, email, body, query);
  }

  Map<String, dynamic> _page(List<Map<String, dynamic>> rows) => {'data': rows, 'current_page': 1, 'last_page': 1, 'total': rows.length};

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> rows, Map<String, dynamic> query, List<String> fields) {
    final status = query['status'];
    final q = '${query['q'] ?? ''}'.toLowerCase();
    return rows
        .where((row) => status == null || '$status'.isEmpty || row['status'] == status)
        .where((row) => q.isEmpty || fields.any((f) => '${row[f] ?? ''}'.toLowerCase().contains(q)))
        .toList();
  }

  /* ─────────────────────────────────────────────────────────── fleet ── */

  Object? _fleet(String method, List<String> r, void Function(String) need, List<String> perms, Map<String, dynamic> body, Map<String, dynamic> query) {
    final head = r.isEmpty ? '' : r.first;
    int id(int i) => int.tryParse(r.length > i ? r[i] : '') ?? 0;

    if (method == 'GET' && head == 'overview') {
      need('fleet.view');
      final byStatus = {for (final s in ['available', 'on_trip', 'maintenance', 'out_of_service']) s: vehicles.where((v) => v['status'] == s).length};
      final expiring = <Map<String, dynamic>>[
        for (final v in vehicles)
          for (final (kind, key) in [('insurance', 'insurance_expiry'), ('road_licence', 'road_licence_expiry')])
            if (DateTime.parse('${v[key]}').difference(_today).inDays <= 30)
              {'kind': kind, 'subject': v['registration_number'], 'vehicle_id': v['id'], 'driver_id': null, 'date': v[key], 'expired': DateTime.parse('${v[key]}').isBefore(_today)},
      ];
      return {
        'data': {
          'vehicles': {'total': vehicles.length, 'by_status': byStatus},
          'trips_today': trips.where((t) => t['status'] == 'dispatched' || '${t['planned_start']}'.startsWith(_day(0))).map(_tripJson).toList(),
          'fuel_alerts': [],
          'expiring': expiring,
          'maintenance_due': schedules.where((s) => s['state'] != 'ok').map(_scheduleJson).toList(),
          'pending_entries': fuel.where((f) => f['status'] == 'pending').length,
          'month': {'trips_closed': 3, 'revenue': 4230000, 'cost': 2890000, 'profit': 1340000, 'litres': 832},
        },
      };
    }

    if (method == 'GET' && head == 'lookups') {
      need('fleet.view');
      return {'data': {'vehicles': vehicles, 'drivers': [], 'customers': [], 'suppliers': _suppliers, 'accounts': _accounts}};
    }

    if (head == 'vehicles' && method == 'GET') {
      need('fleet.view');
      if (r.length == 2) {
        final v = vehicles.firstWhere((x) => x['id'] == id(1), orElse: () => throw ApiException(404, 'Vehicle not found.'));
        return {
          'data': {
            ...v,
            'schedules': schedules.where((s) => s['vehicle_id'] == v['id']).toList(),
            'services': services.where((s) => s['vehicle_id'] == v['id']).toList(),
            'trips': trips.where((t) => t['vehicle_id'] == v['id']).map(_tripJson).toList(),
            'fuel': fuel.where((f) => f['vehicle_id'] == v['id']).map(_fuelJson).toList(),
            'monthly_fixed_cost': 2465000,
            'open_downtime': null,
          },
        };
      }
      return _page(_filter(vehicles, query, ['registration_number', 'make', 'model']));
    }

    if (head == 'my-trips') {
      need('fleet.own');
      if (method == 'GET' && r.length == 1) return _page(_filter(trips, query, ['number', 'origin', 'destination']).map(_tripJson).toList());
      if (method == 'GET' && r.length == 2 && r[1] == 'lookups') return {'data': {'suppliers': _suppliers, 'accounts': _accounts}};
      if (method == 'GET' && r.length == 2) return {'data': _tripDetail(id(1))};
      if (method == 'POST' && r.length == 3 && r[2] == 'fuel') return _recordFuel(id(1), body, perms);
    }

    if (head == 'trips') {
      if (method == 'GET') {
        need('fleet.view');
        if (r.length == 2) return {'data': _tripDetail(id(1))};
        return _page(_filter(trips, query, ['number', 'origin', 'destination', 'cargo_description']).map(_tripJson).toList());
      }
      if (method == 'POST' && r.length == 3) {
        final trip = _trip(id(1));
        switch (r[2]) {
          case 'fuel':
            need('fleet.fuel');
            return _recordFuel(trip['id'] as int, body, perms);
          case 'dispatch':
            need('fleet.trips');
            if (trip['status'] != 'planned') throw ApiException(422, '${trip['number']} is ${trip['status']} and cannot be dispatched.');
            final v = vehicles.firstWhere((x) => x['id'] == trip['vehicle_id']);
            trip
              ..['status'] = 'dispatched'
              ..['actual_start'] = DateTime.now().toUtc().toIso8601String()
              ..['odometer_out'] = '${body['odometer_out'] ?? v['odometer']}';
            v['status'] = 'on_trip';
            return {'message': '${trip['number']} dispatched.', 'data': _tripDetail(trip['id'] as int)};
          case 'complete':
            need('fleet.trips');
            final reading = body['odometer_in'];
            if (reading == null) throw ApiException(422, 'Enter the odometer reading the vehicle came back with.');
            if (double.parse('$reading') < double.parse('${trip['odometer_out'] ?? 0}')) {
              throw ApiException(422, 'The odometer in cannot be below the odometer out.');
            }
            final v = vehicles.firstWhere((x) => x['id'] == trip['vehicle_id']);
            trip
              ..['status'] = 'completed'
              ..['actual_end'] = DateTime.now().toUtc().toIso8601String()
              ..['odometer_in'] = '$reading';
            v
              ..['status'] = 'available'
              ..['odometer'] = '$reading';
            return {'message': '${trip['number']} completed.', 'data': _tripDetail(trip['id'] as int)};
        }
      }
    }

    if (head == 'fuel' && method == 'GET') {
      need('fleet.view');
      return _page(_filter(fuel, query, ['station', 'receipt_number']).map(_fuelJson).toList());
    }

    if (head == 'fuel' && method == 'POST' && r.length == 3 && r[2] == 'decision') {
      need('fleet.approve');
      final f = fuel.firstWhere((x) => x['id'] == id(1), orElse: () => throw ApiException(404, 'Not found.'));
      final approve = body['decision'] == 'approve';
      if (!approve && '${body['reason'] ?? ''}'.isEmpty) {
        throw ApiException(422, 'The reason field is required when decision is reject.', {'reason': ['The reason field is required when decision is reject.']});
      }
      f['status'] = approve ? 'approved' : 'rejected';
      if (!approve) f['rejection_reason'] = body['reason'];
      return {'message': approve ? 'Approved.' : 'Rejected.', 'data': f};
    }

    if (head == 'schedules' && method == 'GET') {
      need('fleet.view');
      final rows = schedules.map(_scheduleJson).toList();
      return {'data': rows, 'due': rows.where((s) => s['state'] != 'ok').toList()};
    }

    if (head == 'services' && method == 'GET') {
      need('fleet.view');
      return _page([for (final s in services) {...s, 'vehicle': _vehicleRef(s['vehicle_id'] as int)}]);
    }
    return null;
  }

  Map<String, dynamic> _trip(int id) => trips.firstWhere((t) => t['id'] == id, orElse: () => throw ApiException(404, 'Trip not found.'));

  Map<String, dynamic> _vehicleRef(int id) {
    final v = vehicles.firstWhere((x) => x['id'] == id);
    return {'id': id, 'registration_number': v['registration_number'], 'odometer': v['odometer']};
  }

  Map<String, dynamic> _tripJson(Map<String, dynamic> t) => {...t};

  Map<String, dynamic> _scheduleJson(Map<String, dynamic> s) => {...s, 'vehicle': _vehicleRef(s['vehicle_id'] as int)};

  Map<String, dynamic> _fuelJson(Map<String, dynamic> f) {
    final t = _trip(f['trip_id'] as int);
    return {
      ...f,
      'trip': {'id': t['id'], 'number': t['number'], 'origin': t['origin'], 'destination': t['destination'], 'fuel_over_standard': false},
      'vehicle': {'id': f['vehicle_id'], 'registration_number': _vehicleRef(f['vehicle_id'] as int)['registration_number']},
    };
  }

  Map<String, dynamic> _tripDetail(int id) {
    final t = _trip(id);
    final mine = fuel.where((f) => f['trip_id'] == id).toList();
    double sum(String status) => mine.where((f) => f['status'] == status).fold(0.0, (s, f) => s + double.parse('${f['amount']}'));
    return {
      ...t,
      'fuel_issues': mine,
      'expenses': [],
      'costs': {
        'revenue': 1410000, 'fuel': sum('approved'), 'expenses': 0, 'hire': 0, 'fixed': 0, //
        'total_cost': sum('approved'), 'profit': 1410000 - sum('approved'), 'pending': sum('pending'),
        'distance_km': 640, 'days': 2,
      },
      'standard': null,
    };
  }

  Map<String, dynamic> _recordFuel(int tripId, Map<String, dynamic> body, List<String> perms) {
    final t = _trip(tripId);
    if (t['status'] == 'closed' || t['status'] == 'cancelled') {
      throw ApiException(422, '${t['number']} is ${t['status']}: nothing more can be charged to it.');
    }
    final litres = double.tryParse('${body['litres'] ?? ''}') ?? 0;
    final price = double.tryParse('${body['price_per_litre'] ?? ''}') ?? 0;
    final errors = <String, List<String>>{
      if (litres <= 0) 'litres': ['The litres field is required.'],
      if (price <= 0) 'price_per_litre': ['The price per litre field is required.'],
    };
    if (errors.isNotEmpty) throw ApiException(422, errors.values.first.first, errors);
    final accountId = body['account_id'];
    final supplierId = body['supplier_id'];
    if ((accountId == null) == (supplierId == null)) {
      throw ApiException(422, 'Say how this was paid: from a cash or bank account, or on credit from a supplier, not both.');
    }
    final approved = perms.contains('fleet.approve');
    final entry = {
      ..._fuel(++_nextFuel, tripId, t['vehicle_id'] as int, litres, price, '${body['station'] ?? ''}', approved ? 'approved' : 'pending', 0),
      'issue_date': body['issue_date'] ?? _day(0),
      'receipt_number': body['receipt_number'],
      'station': body['station'],
      'odometer': body['odometer']?.toString(),
      'account_id': accountId,
      'supplier_id': supplierId,
      'account': _accounts.where((a) => a['id'] == accountId).firstOrNull,
      'supplier': _suppliers.where((s) => s['id'] == supplierId).firstOrNull,
    };
    fuel.insert(0, entry);
    return {'message': approved ? 'Recorded and approved.' : 'Recorded. It waits for approval.', 'data': entry};
  }

  /* ────────────────────────────────────────────────────────────── hr ── */

  Object? _hr(String method, List<String> r, void Function(String) need, List<String> perms, String email, Map<String, dynamic> body, Map<String, dynamic> query) {
    final head = r.isEmpty ? '' : r.first;
    int id(int i) => int.tryParse(r.length > i ? r[i] : '') ?? 0;
    final payroll = ['hr.payroll.prepare', 'hr.payroll.authorise', 'hr.payroll.post'].any(perms.contains);

    if (head == 'me') {
      need('hr.self');
      final me = employees.where((e) => e['email'] == email).firstOrNull ?? employees.first;
      final meId = me['id'] as int;
      final sub = r.length > 1 ? r[1] : '';
      if (method == 'GET' && sub == '') {
        return {
          'data': {
            ...me,
            'department': (me['department'] as Map)['name'],
            'manager': (me['manager'] as Map)['full_name'],
            'shift': null,
            'leave_balances': _balances(meId),
          },
        };
      }
      if (method == 'PUT' && sub == '') {
        for (final k in ['phone', 'address', 'next_of_kin_name', 'next_of_kin_phone', 'next_of_kin_relation']) {
          if (body.containsKey(k)) me[k] = body[k];
        }
        return {'message': 'Your details are saved.'};
      }
      if (sub == 'leave' && method == 'GET') {
        return {'data': leave.where((l) => l['employee_id'] == meId).toList(), 'balances': _balances(meId)};
      }
      if (sub == 'leave' && method == 'POST' && r.length == 2) return _requestLeave(me, body);
      if (sub == 'leave' && method == 'POST' && r.length == 4 && r[3] == 'cancel') {
        final l = leave.firstWhere((x) => x['id'] == id(2) && x['employee_id'] == meId, orElse: () => throw ApiException(404, 'Not found.'));
        l['status'] = 'cancelled';
        return {'message': 'Leave cancelled.', 'data': l};
      }
      if (sub == 'payslips' && method == 'GET') {
        final released = payslips.where((p) => p['employee_id'] == meId && _runOf(p)['status'] != 'draft').toList();
        if (r.length == 3) {
          final p = released.firstWhere((x) => x['id'] == id(2), orElse: () => throw ApiException(404, 'Not found.'));
          return {'data': {...p, 'run': _runRef(_runOf(p))}};
        }
        return {
          'data': [
            for (final p in released.reversed)
              {'id': p['id'], 'payroll_run_id': p['payroll_run_id'], 'gross': p['gross'], 'total_deductions': p['total_deductions'], 'net': p['net'], 'run': _runRef(_runOf(p))},
          ],
        };
      }
      if (sub == 'attendance' && method == 'GET') {
        final month = '${query['month'] ?? _day(0).substring(0, 7)}';
        return {'month': month, 'data': attendance.where((a) => a['employee_id'] == meId && '${a['date']}'.startsWith(month)).toList()};
      }
      return null;
    }

    if (head == 'leave-types' && method == 'GET') {
      need('hr.self');
      return {'data': _types};
    }

    if (head == 'overview' && method == 'GET') {
      need('hr.view');
      final today = attendance.where((a) => '${a['date']}'.startsWith(_day(0))).toList();
      final run = runs.first;
      return {
        'data': {
          'headcount': employees.where((e) => e['status'] == 'active').length,
          'suspended': 0,
          'by_department': [
            for (final e in employees) {'department_id': e['id'], 'department': (e['department'] as Map)['name'], 'headcount': 1},
          ],
          'on_leave_today': [
            for (final l in leave.where((l) => l['status'] == 'approved' && _covers(l, _today)))
              {'id': l['id'], 'employee': (l['employee'] as Map)['full_name'], 'employee_id': l['employee_id'], 'leave_type': (l['leave_type'] as Map)['name'], 'end_date': '${l['end_date']}'.substring(0, 10)},
          ],
          'pending_leave': leave.where((l) => l['status'] == 'pending').length,
          'attendance_today': {
            'present': today.where((a) => a['status'] == 'present').length,
            'late': today.where((a) => a['status'] == 'late').length,
            'absent': 0,
            'leave': 1,
          },
          'payroll': {
            'current_period': run['period'],
            'current': {'id': run['id'], 'number': run['number'], 'period': run['period'], 'status': run['status'], 'employees_count': run['employees_count'], 'net': double.parse('${run['net']}'), 'gross': double.parse('${run['gross']}')},
          },
          'contracts_expiring': [],
          'probation_ending': [],
          'open_vacancies': 0,
          'applicants_in_pipeline': 0,
          'exits_in_progress': 0,
          'open_discipline_cases': null,
        },
      };
    }

    if (head == 'employees' && method == 'GET') {
      need('hr.view');
      if (r.length == 2) {
        final e = employees.firstWhere((x) => x['id'] == id(1), orElse: () => throw ApiException(404, 'Not found.'));
        return {
          'data': e,
          'contracts': [e['contract']],
          'leave_balances': _balances(e['id'] as int),
          'leave_requests': leave.where((l) => l['employee_id'] == e['id']).toList(),
          'attendance': attendance.where((a) => a['employee_id'] == e['id']).toList().reversed.toList(),
          'payslips': [
            for (final p in payslips.where((p) => p['employee_id'] == e['id']))
              {'id': p['id'], 'payroll_run_id': p['payroll_run_id'], 'gross': p['gross'], 'net': p['net'], 'total_deductions': p['total_deductions'], 'run': _runRef(_runOf(p))},
          ],
        };
      }
      final rows = _filter(employees, query, ['full_name', 'employee_number', 'job_title']);
      return {'data': rows, 'meta': {'current_page': 1, 'last_page': 1, 'total': rows.length}};
    }

    if (head == 'leave' && r.length >= 2 && r[1] == 'requests') {
      if (method == 'GET' && r.length == 2) {
        if (!perms.contains('hr.view') && !perms.contains('hr.leave.approve')) throw ApiException(403, 'Your role does not allow this.');
        final rows = _filter(leave, query, const [])
          ..sort((a, b) => (a['status'] == 'pending' ? 0 : 1).compareTo(b['status'] == 'pending' ? 0 : 1));
        return _page([for (final l in rows) {...l, 'can_decide': l['status'] == 'pending' && perms.contains('hr.leave.approve')}]);
      }
      if (method == 'POST' && r.length == 4) {
        need('hr.leave.approve');
        final l = leave.firstWhere((x) => x['id'] == id(2), orElse: () => throw ApiException(404, 'Not found.'));
        if (l['status'] != 'pending') throw ApiException(422, 'This request has already been decided.');
        if (r[3] == 'reject' && '${body['note'] ?? ''}'.trim().length < 3) {
          throw ApiException(422, 'Say why the leave is rejected.', {'note': ['Say why the leave is rejected.']});
        }
        l['status'] = r[3] == 'approve' ? 'approved' : 'rejected';
        l['decision_note'] = body['note'];
        l['decider'] = {'id': 5, 'name': 'Anna Lyimo'};
        return {'message': r[3] == 'approve' ? 'Leave approved.' : 'Leave rejected.', 'data': l};
      }
    }

    if ((head == 'attendance' || (head == 'team' && r.length > 1 && r[1] == 'attendance')) && method == 'GET') {
      need(head == 'team' ? 'hr.leave.approve' : 'hr.view');
      final date = '${query['date'] ?? _day(0)}';
      return {
        'date': date,
        'data': [
          for (final e in employees)
            {
              'employee': {'id': e['id'], 'full_name': e['full_name'], 'employee_number': e['employee_number'], 'department': (e['department'] as Map)['name'], 'shift': null},
              'record': attendance.where((a) => a['employee_id'] == e['id'] && '${a['date']}'.startsWith(date)).firstOrNull,
              'on_leave': leave.where((l) => l['employee_id'] == e['id'] && l['status'] == 'approved' && _covers(l, DateTime.parse(date))).firstOrNull,
            },
        ],
      };
    }

    if (head == 'payroll-runs' && method == 'GET') {
      if (!payroll) throw ApiException(403, 'Your role does not allow you to see payroll.');
      if (r.length == 2) {
        final run = runs.firstWhere((x) => x['id'] == id(1), orElse: () => throw ApiException(404, 'Not found.'));
        return {'data': run, 'payslips': payslips.where((p) => p['payroll_run_id'] == run['id']).toList(), 'posting': [], 'can': {}};
      }
      return _page(runs);
    }

    if (head == 'payslips' && method == 'GET' && r.length == 2) {
      if (!payroll) throw ApiException(403, 'Your role does not allow you to see payroll.');
      final p = payslips.firstWhere((x) => x['id'] == id(1), orElse: () => throw ApiException(404, 'Not found.'));
      return {'data': {...p, 'run': _runRef(_runOf(p))}};
    }
    return null;
  }

  bool _covers(Map<String, dynamic> l, DateTime d) {
    final s = DateTime.parse('${l['start_date']}'.substring(0, 10));
    final e = DateTime.parse('${l['end_date']}'.substring(0, 10));
    return !d.isBefore(s) && !d.isAfter(e);
  }

  Map<String, dynamic> _runOf(Map<String, dynamic> p) => runs.firstWhere((r) => r['id'] == p['payroll_run_id']);

  Map<String, dynamic> _runRef(Map<String, dynamic> r) => {
    'id': r['id'], 'number': r['number'], 'period': r['period'], 'period_start': r['period_start'], //
    'period_end': null, 'status': r['status'], 'payment_date': r['payment_date'],
  };

  List<Map<String, dynamic>> _balances(int employeeId) {
    double taken(int typeId) => leave
        .where((l) => l['employee_id'] == employeeId && l['leave_type_id'] == typeId && l['status'] == 'approved')
        .fold(0.0, (s, l) => s + double.parse('${l['days']}'));
    return [
      for (final t in _types)
        () {
          final limited = t['code'] != 'unpaid';
          final accrued = t['code'] == 'annual' ? 25.67 : double.parse('${t['days_per_year']}');
          final used = taken(t['id'] as int);
          return {
            'id': employeeId * 10 + (t['id'] as int),
            'employee_id': employeeId,
            'leave_type_id': t['id'],
            'leave_type': {'id': t['id'], 'code': t['code'], 'name': t['name'], 'paid': t['paid']},
            'year': _today.year,
            'entitled': double.parse('${t['days_per_year']}'),
            'accrued': accrued,
            'carried_forward': 0,
            'adjustment': 0,
            'taken': used,
            'available': limited ? accrued - used : null,
            'limited': limited,
          };
        }(),
    ];
  }

  Map<String, dynamic> _requestLeave(Map<String, dynamic> me, Map<String, dynamic> body) {
    final type = _types.where((t) => t['id'] == body['leave_type_id']).firstOrNull;
    final start = DateTime.tryParse('${body['start_date'] ?? ''}');
    final end = DateTime.tryParse('${body['end_date'] ?? ''}');
    final errors = <String, List<String>>{
      if (type == null) 'leave_type_id': ['Choose the kind of leave.'],
      if (start == null) 'start_date': ['The start date field is required.'],
      if (end == null) 'end_date': ['The end date field is required.'],
    };
    if (errors.isNotEmpty) throw ApiException(422, errors.values.first.first, errors);
    if (end!.isBefore(start!)) throw ApiException(422, 'The last day of leave cannot be before the first.');
    var days = 0;
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      if (d.weekday <= 5) days++;
    }
    final row = _leave(++_nextLeave, me['id'] as int, '${type!['code']}', '${body['start_date']}', '${body['end_date']}', days.toDouble(), 'pending', body['reason'] as String?);
    leave.insert(0, row);
    return {'message': 'Leave requested.', 'data': row};
  }
}
