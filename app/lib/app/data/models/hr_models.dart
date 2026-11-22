import 'people_json.dart';

/*
 * The shapes /api/erp/hr returns: employees (EmployeeResource), leave,
 * attendance, payroll runs and payslips, the HR overview, and the
 * self-service /hr/me answers. Pay is only present when the API decided the
 * caller may see it (hr.salary, or their own record).
 */

abstract class HrLeaveStatus {
  static const pending = 'pending';
  static const approved = 'approved';
  static const rejected = 'rejected';
  static const cancelled = 'cancelled';
  static const all = [pending, approved, rejected, cancelled];
}

abstract class HrAttendanceStatus {
  static const present = 'present';
  static const late = 'late';
  static const absent = 'absent';
  static const leave = 'leave';
  static const off = 'off';
  static const all = [present, late, absent, leave, off];
}

class HrContract {
  const HrContract({
    required this.type,
    this.start,
    this.end,
    this.basic,
    this.housing,
    this.transport,
    this.other,
  });

  static HrContract? fromJson(dynamic v) {
    final j = jmap(v);
    if (j == null) return null;
    return HrContract(
      type: jstr(j['type']),
      start: jday(j['start_date']),
      end: jday(j['end_date']),
      basic: jdn(j['basic_salary']),
      housing: jdn(j['housing_allowance']),
      transport: jdn(j['transport_allowance']),
      other: jdn(j['other_allowance']),
    );
  }

  final String type;
  final DateTime? start, end;
  final double? basic, housing, transport, other;

  bool get hasPay => basic != null;
  double get gross => (basic ?? 0) + (housing ?? 0) + (transport ?? 0) + (other ?? 0);
}

class HrEmployee {
  const HrEmployee({
    required this.id,
    required this.number,
    required this.name,
    required this.status,
    this.email,
    this.phone,
    this.jobTitle,
    this.grade,
    this.department,
    this.manager,
    this.employmentType,
    this.hireDate,
    this.probationEnd,
    this.dateOfBirth,
    this.gender,
    this.address,
    this.nextOfKinName,
    this.nextOfKinPhone,
    this.nextOfKinRelation,
    this.nationalId,
    this.tin,
    this.nssf,
    this.bank,
    this.bankAccount,
    this.shift,
    this.contract,
    this.salaryVisible = false,
  });

  factory HrEmployee.fromJson(Map<String, dynamic> j) {
    // /hr/me sends the department and manager as names; the staff list
    // sends them as records.
    String? named(dynamic v, String key) => v is Map ? js(v[key]) : js(v);
    final shift = jmap(j['shift']);
    final contract = HrContract.fromJson(j['contract']);
    return HrEmployee(
      id: ji(j['id']),
      number: jstr(j['employee_number']),
      name: jstr(j['full_name']),
      status: js(j['status']) ?? 'active',
      email: js(j['email']),
      phone: js(j['phone']),
      jobTitle: js(j['job_title']),
      grade: js(j['grade']),
      department: named(j['department'], 'name'),
      manager: named(j['manager'], 'full_name'),
      employmentType: js(j['employment_type']),
      hireDate: jday(j['hire_date']),
      probationEnd: jday(j['probation_end']),
      dateOfBirth: jday(j['date_of_birth']),
      gender: js(j['gender']),
      address: js(j['address']),
      nextOfKinName: js(j['next_of_kin_name']),
      nextOfKinPhone: js(j['next_of_kin_phone']),
      nextOfKinRelation: js(j['next_of_kin_relation']),
      nationalId: js(j['national_id']),
      tin: js(j['tin']),
      nssf: js(j['nssf_number']),
      bank: js(j['bank_name']),
      bankAccount: js(j['bank_account_number']),
      shift: shift == null
          ? js(j['shift'])
          : [js(shift['name']), if (shift['start_time'] != null) '${shift['start_time']} to ${shift['end_time']}']
                .whereType<String>()
                .join(' · '),
      contract: contract,
      salaryVisible: j['salary_visible'] == true || (contract?.hasPay ?? false),
    );
  }

  final int id;
  final String number, name, status;
  final String? email, phone, jobTitle, grade, department, manager, employmentType, gender, address;
  final String? nextOfKinName, nextOfKinPhone, nextOfKinRelation, nationalId, tin, nssf, bank, bankAccount, shift;
  final DateTime? hireDate, probationEnd, dateOfBirth;
  final HrContract? contract;
  final bool salaryVisible;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }
}

class HrLeaveBalance {
  const HrLeaveBalance({
    required this.typeId,
    required this.type,
    required this.code,
    required this.paid,
    required this.entitled,
    required this.accrued,
    required this.taken,
    required this.limited,
    this.available,
  });

  factory HrLeaveBalance.fromJson(Map<String, dynamic> j) {
    final type = jmap(j['leave_type']) ?? const {};
    return HrLeaveBalance(
      typeId: ji(j['leave_type_id']),
      type: jstr(type['name']),
      code: jstr(type['code']),
      paid: type['paid'] != false,
      entitled: jd(j['entitled']),
      accrued: jd(j['accrued']),
      taken: jd(j['taken']),
      limited: j['limited'] != false,
      available: jdn(j['available']),
    );
  }

  final int typeId;
  final String type, code;
  final bool paid, limited;
  final double entitled, accrued, taken;

  /// Null when the type has no limit (unpaid leave).
  final double? available;
}

class HrLeaveType {
  const HrLeaveType({required this.id, required this.name, required this.code, required this.daysPerYear, required this.paid, required this.counting});

  factory HrLeaveType.fromJson(Map<String, dynamic> j) => HrLeaveType(
    id: ji(j['id']),
    name: jstr(j['name']),
    code: jstr(j['code']),
    daysPerYear: jd(j['days_per_year']),
    paid: j['paid'] != false,
    counting: js(j['counting']) ?? 'working',
  );

  final int id;
  final String name, code, counting;
  final double daysPerYear;
  final bool paid;
}

class HrLeaveRequest {
  const HrLeaveRequest({
    required this.id,
    required this.status,
    required this.type,
    required this.days,
    this.start,
    this.end,
    this.employeeId,
    this.employee,
    this.employeeNumber,
    this.department,
    this.reason,
    this.decider,
    this.decisionNote,
    this.canDecide = false,
  });

  factory HrLeaveRequest.fromJson(Map<String, dynamic> j) {
    final e = jmap(j['employee']);
    return HrLeaveRequest(
      id: ji(j['id']),
      status: jstr(j['status']),
      type: jstr(jmap(j['leave_type'])?['name']),
      days: jd(j['days']),
      start: jday(j['start_date']),
      end: jday(j['end_date']),
      employeeId: jin(j['employee_id']),
      employee: js(e?['full_name']),
      employeeNumber: js(e?['employee_number']),
      department: js(jmap(e?['department'])?['name']),
      reason: js(j['reason']),
      decider: js(jmap(j['decider'])?['name']),
      decisionNote: js(j['decision_note']),
      canDecide: j['can_decide'] == true,
    );
  }

  final int id;
  final String status, type;
  final double days;
  final DateTime? start, end;
  final int? employeeId;
  final String? employee, employeeNumber, department, reason, decider, decisionNote;
  final bool canDecide;

  bool get isPending => status == HrLeaveStatus.pending;
}

class HrAttendance {
  const HrAttendance({
    required this.id,
    required this.status,
    this.date,
    this.checkIn,
    this.checkOut,
    this.hours = 0,
    this.overtime = 0,
    this.note,
  });

  static HrAttendance? fromJsonOrNull(dynamic v) {
    final j = jmap(v);
    return j == null ? null : HrAttendance.fromJson(j);
  }

  factory HrAttendance.fromJson(Map<String, dynamic> j) => HrAttendance(
    id: ji(j['id']),
    status: jstr(j['status']),
    date: jday(j['date']),
    checkIn: _hm(j['check_in']),
    checkOut: _hm(j['check_out']),
    hours: jd(j['hours_worked']),
    overtime: jd(j['overtime_hours']),
    note: js(j['note']),
  );

  /// "07:52:00" read as "07:52".
  static String? _hm(dynamic v) {
    final s = js(v);
    return s == null ? null : (s.length >= 5 ? s.substring(0, 5) : s);
  }

  final int id;
  final String status;
  final DateTime? date;
  final String? checkIn, checkOut, note;
  final double hours, overtime;
}

/// A row of the daily register: the person, their record, their leave.
class HrDailyRow {
  const HrDailyRow({required this.employeeId, required this.name, required this.number, this.department, this.record, this.onLeave});

  factory HrDailyRow.fromJson(Map<String, dynamic> j) {
    final e = jmap(j['employee']) ?? const {};
    final leave = jmap(j['on_leave']);
    return HrDailyRow(
      employeeId: ji(e['id']),
      name: jstr(e['full_name']),
      number: jstr(e['employee_number']),
      department: js(e['department']),
      record: HrAttendance.fromJsonOrNull(j['record']),
      onLeave: leave == null ? null : (js(jmap(leave['leave_type'])?['name']) ?? 'leave'),
    );
  }

  final int employeeId;
  final String name, number;
  final String? department, onLeave;
  final HrAttendance? record;

  /// What the day reads as: the record's status, leave, or not in yet.
  String get state => record?.status ?? (onLeave != null ? HrAttendanceStatus.leave : 'none');
}

/// A payslip as a list shows it.
class HrPayslipSummary {
  const HrPayslipSummary({
    required this.id,
    required this.gross,
    required this.deductions,
    required this.net,
    this.runNumber,
    this.period,
    this.runStatus,
    this.paymentDate,
    this.employee,
  });

  factory HrPayslipSummary.fromJson(Map<String, dynamic> j) {
    final run = jmap(j['run']);
    return HrPayslipSummary(
      id: ji(j['id']),
      gross: jd(j['gross']),
      deductions: jd(j['total_deductions']),
      net: jd(j['net']),
      runNumber: js(run?['number']),
      period: js(run?['period']),
      runStatus: js(run?['status']),
      paymentDate: jday(run?['payment_date']),
      employee: js(j['employee_name']),
    );
  }

  final int id;
  final double gross, deductions, net;
  final String? runNumber, period, runStatus, employee;
  final DateTime? paymentDate;
}

/// One extra line on a payslip (a commission, a loan instalment …).
class HrPayLine {
  const HrPayLine(this.label, this.amount);

  final String label;
  final double amount;
}

class HrPayslip {
  const HrPayslip({
    required this.id,
    required this.employee,
    required this.employeeNumber,
    required this.values,
    required this.earnings,
    required this.deductions,
    required this.loans,
    this.department,
    this.jobTitle,
    this.bank,
    this.bankAccount,
    this.runNumber,
    this.period,
    this.periodStart,
    this.periodEnd,
    this.runStatus,
    this.paymentDate,
  });

  factory HrPayslip.fromJson(Map<String, dynamic> j) {
    final run = jmap(j['run']);
    final lines = jmap(j['lines']) ?? const {};
    List<HrPayLine> items(dynamic v) => jlist(
      v,
      (m) => HrPayLine(js(m['description']) ?? js(m['number']) ?? js(m['category']) ?? js(m['type']) ?? '', jd(m['amount'])),
    );
    const keys = [
      'days_paid', 'unpaid_days', 'overtime_hours', 'basic', 'housing_allowance', 'transport_allowance', //
      'other_allowance', 'overtime', 'other_earnings', 'absence_deduction', 'gross', 'nssf_employee', 'taxable',
      'paye', 'heslb', 'loans', 'other_deductions', 'total_deductions', 'net', 'nssf_employer', 'wcf', 'sdl',
    ];
    return HrPayslip(
      id: ji(j['id']),
      employee: jstr(j['employee_name']),
      employeeNumber: jstr(j['employee_number']),
      values: {for (final k in keys) k: jd(j[k])},
      earnings: items(lines['earnings']),
      deductions: items(lines['deductions']),
      loans: items(lines['loans']),
      department: js(j['department']),
      jobTitle: js(j['job_title']),
      bank: js(j['bank_name']),
      bankAccount: js(j['bank_account_number']),
      runNumber: js(run?['number']),
      period: js(run?['period']),
      periodStart: jday(run?['period_start']),
      periodEnd: jday(run?['period_end']),
      runStatus: js(run?['status']),
      paymentDate: jday(run?['payment_date']),
    );
  }

  final int id;
  final String employee, employeeNumber;
  final Map<String, double> values;
  final List<HrPayLine> earnings, deductions, loans;
  final String? department, jobTitle, bank, bankAccount, runNumber, period, runStatus;
  final DateTime? periodStart, periodEnd, paymentDate;

  double v(String key) => values[key] ?? 0;
  double get gross => v('gross');
  double get net => v('net');
  double get totalDeductions => v('total_deductions');
}

class HrPayrollRun {
  const HrPayrollRun({
    required this.id,
    required this.number,
    required this.period,
    required this.status,
    required this.employees,
    required this.values,
    this.preparer,
    this.authoriser,
    this.paymentDate,
    this.notes,
    this.payslips = const [],
  });

  factory HrPayrollRun.fromJson(Map<String, dynamic> j, {dynamic payslips}) {
    const keys = [
      'basic', 'allowances', 'overtime', 'other_earnings', 'absence_deduction', 'gross', 'nssf_employee', //
      'paye', 'heslb', 'loans', 'other_deductions', 'total_deductions', 'net', 'nssf_employer', 'wcf', 'sdl',
    ];
    return HrPayrollRun(
      id: ji(j['id']),
      number: jstr(j['number']),
      period: jstr(j['period']),
      status: jstr(j['status']),
      employees: ji(j['employees_count']),
      values: {for (final k in keys) k: jd(j[k])},
      preparer: js(jmap(j['preparer'])?['name']),
      authoriser: js(jmap(j['authoriser'])?['name']),
      paymentDate: jday(j['payment_date']),
      notes: js(j['notes']),
      payslips: jlist(payslips, HrPayslip.fromJson),
    );
  }

  final int id, employees;
  final String number, period, status;
  final Map<String, double> values;
  final String? preparer, authoriser, notes;
  final DateTime? paymentDate;
  final List<HrPayslip> payslips;

  double v(String key) => values[key] ?? 0;
  double get gross => v('gross');
  double get net => v('net');
  double get totalDeductions => v('total_deductions');

  /// The employer's statutory cost on top of gross.
  double get employerCost => v('nssf_employer') + v('wcf') + v('sdl');
}

class HrNamedDate {
  const HrNamedDate({required this.name, this.employeeId, this.date, this.detail});

  final String name;
  final int? employeeId;
  final DateTime? date;
  final String? detail;
}

/// GET /erp/hr/overview.
class HrOverview {
  const HrOverview({
    required this.headcount,
    required this.suspended,
    required this.byDepartment,
    required this.onLeaveToday,
    required this.pendingLeave,
    required this.present,
    required this.late,
    required this.absent,
    required this.onLeave,
    required this.contractsExpiring,
    required this.probationEnding,
    this.payrollPeriod,
    this.payroll,
    this.openVacancies = 0,
    this.exits = 0,
  });

  factory HrOverview.fromJson(Map<String, dynamic> j) {
    final att = jmap(j['attendance_today']) ?? const {};
    final pay = jmap(j['payroll']) ?? const {};
    final current = jmap(pay['current']) ?? jmap(pay['latest']);
    return HrOverview(
      headcount: ji(j['headcount']),
      suspended: ji(j['suspended']),
      byDepartment: [
        for (final d in jlist(j['by_department'], (m) => m)) (jstr(d['department']), ji(d['headcount'])),
      ],
      onLeaveToday: jlist(
        j['on_leave_today'],
        (m) => HrNamedDate(name: jstr(m['employee']), employeeId: jin(m['employee_id']), date: jday(m['end_date']), detail: js(m['leave_type'])),
      ),
      pendingLeave: ji(j['pending_leave']),
      present: ji(att['present']),
      late: ji(att['late']),
      absent: ji(att['absent']),
      onLeave: ji(att['leave']),
      contractsExpiring: jlist(
        j['contracts_expiring'],
        (m) => HrNamedDate(name: jstr(m['employee']), employeeId: jin(m['employee_id']), date: jday(m['end_date']), detail: js(m['type'])),
      ),
      probationEnding: jlist(
        j['probation_ending'],
        (m) => HrNamedDate(name: jstr(m['employee']), employeeId: jin(m['employee_id']), date: jday(m['probation_end'])),
      ),
      payrollPeriod: js(pay['current_period']),
      payroll: current == null
          ? null
          : HrPayrollRun(
              id: ji(current['id']),
              number: jstr(current['number']),
              period: jstr(current['period']),
              status: jstr(current['status']),
              employees: ji(current['employees_count']),
              values: {'net': jd(current['net']), 'gross': jd(current['gross'])},
            ),
      openVacancies: ji(j['open_vacancies']),
      exits: ji(j['exits_in_progress']),
    );
  }

  final int headcount, suspended, pendingLeave, present, late, absent, onLeave, openVacancies, exits;
  final List<(String, int)> byDepartment;
  final List<HrNamedDate> onLeaveToday, contractsExpiring, probationEnding;
  final String? payrollPeriod;
  final HrPayrollRun? payroll;

  int get inToday => present + late;
}

/// An employee's own record and balances (GET /hr/me), or one person as HR
/// reads them (GET /hr/employees/{id}).
class HrPersonFile {
  const HrPersonFile({
    required this.employee,
    required this.balances,
    this.leave = const [],
    this.attendance = const [],
    this.payslips = const [],
  });

  final HrEmployee employee;
  final List<HrLeaveBalance> balances;
  final List<HrLeaveRequest> leave;
  final List<HrAttendance> attendance;
  final List<HrPayslipSummary> payslips;

  /// The balance worth showing first: annual leave when there is one.
  HrLeaveBalance? get annual =>
      balances.where((b) => b.code == 'annual').firstOrNull ?? balances.where((b) => b.limited).firstOrNull;
}

/// The leave an employee is applying for (SelfServiceController@requestLeave).
class LeaveDraft {
  int? typeId;
  DateTime? start;
  DateTime? end;
  String reason = '';

  Map<String, dynamic> toJson() => {
    'leave_type_id': typeId,
    'start_date': start == null ? null : jdate(start!),
    'end_date': end == null ? null : jdate(end!),
    if (reason.trim().isNotEmpty) 'reason': reason.trim(),
  };

  /// Calendar days in the range (the API counts working days for most types
  /// and says how many it took).
  int get calendarDays => start == null || end == null ? 0 : end!.difference(start!).inDays + 1;
}
