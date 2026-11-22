import 'package:get/get.dart';

import '../models/erp_models.dart' show ErpPage;
import '../models/hr_models.dart';
import '../models/people_json.dart';
import 'api_service.dart';

/// The HR app's endpoints (backend routes/erp/hr.php, `module:hr`): the
/// staff side (employees, leave to decide, attendance, payroll runs, read
/// only here) and self-service under /hr/me, which only ever reaches the
/// caller's own record.
class HrRepository {
  HrRepository(this._api);

  final ApiService _api;

  /// The shared instance, registered on first use.
  static HrRepository get to => Get.isRegistered<HrRepository>()
      ? Get.find<HrRepository>()
      : Get.put(HrRepository(Get.find<ApiService>()), permanent: true);

  Future<Map<String, dynamic>> _map(String path, [Map<String, dynamic>? q]) async =>
      Map<String, dynamic>.from(await _api.get(path, q) as Map);

  Map<String, dynamic> _data(dynamic payload) => Map<String, dynamic>.from((payload as Map)['data'] as Map);

  String _message(dynamic r) => r is Map ? '${r['message'] ?? ''}' : '';

  /* ─────────────────────────────────────────────────────────── staff ── */

  Future<HrOverview> overview() async => HrOverview.fromJson(_data(await _api.get('/erp/hr/overview')));

  /// The staff list. EmployeeResource pages carry their counters in `meta`.
  Future<ErpPage<HrEmployee>> employees({String? q, String? status, int page = 1}) async {
    final payload = await _map('/erp/hr/employees', {'q': q, 'status': status, 'page': page, 'per_page': 40});
    final meta = jmap(payload['meta']) ?? payload;
    final rows = jlist(payload['data'], HrEmployee.fromJson);
    return ErpPage(rows, jin(meta['current_page']) ?? 1, jin(meta['last_page']) ?? 1, jin(meta['total']) ?? rows.length);
  }

  Future<HrPersonFile> employee(int id) async {
    final payload = await _map('/erp/hr/employees/$id');
    return HrPersonFile(
      employee: HrEmployee.fromJson(_data(payload)),
      balances: jlist(payload['leave_balances'], HrLeaveBalance.fromJson),
      leave: jlist(payload['leave_requests'], HrLeaveRequest.fromJson),
      attendance: jlist(payload['attendance'], HrAttendance.fromJson),
      payslips: jlist(payload['payslips'], HrPayslipSummary.fromJson),
    );
  }

  /// Leave requests the caller may see: every one for HR, their team for a
  /// department head. Pending ones come first.
  Future<ErpPage<HrLeaveRequest>> leaveRequests({String? status, int page = 1}) async => ErpPage.fromJson(
    await _map('/erp/hr/leave/requests', {'status': status, 'page': page, 'per_page': 30}),
    HrLeaveRequest.fromJson,
  );

  Future<String> approveLeave(int id, {String? note}) async =>
      _message(await _api.post('/erp/hr/leave/requests/$id/approve', {if (note != null && note.isNotEmpty) 'note': note}));

  Future<String> rejectLeave(int id, String note) async =>
      _message(await _api.post('/erp/hr/leave/requests/$id/reject', {'note': note}));

  /// The day's register. [team] reads a department head's own people only.
  Future<List<HrDailyRow>> attendance({DateTime? date, bool team = false}) async {
    final payload = await _map(team ? '/erp/hr/team/attendance' : '/erp/hr/attendance', {
      'date': date == null ? null : jdate(date),
    });
    return jlist(payload['data'], HrDailyRow.fromJson);
  }

  Future<ErpPage<HrPayrollRun>> payrollRuns({int page = 1}) async => ErpPage.fromJson(
    await _map('/erp/hr/payroll-runs', {'page': page}),
    (j) => HrPayrollRun.fromJson(j),
  );

  Future<HrPayrollRun> payrollRun(int id) async {
    final payload = await _map('/erp/hr/payroll-runs/$id');
    return HrPayrollRun.fromJson(_data(payload), payslips: payload['payslips']);
  }

  /// One payslip: the caller's own through /me, anyone's for payroll staff.
  Future<HrPayslip> payslip(int id, {bool mine = true}) async =>
      HrPayslip.fromJson(_data(await _api.get(mine ? '/erp/hr/me/payslips/$id' : '/erp/hr/payslips/$id')));

  /* ──────────────────────────────────────────────────── self-service ── */

  Future<HrPersonFile> me() async {
    final data = _data(await _api.get('/erp/hr/me'));
    return HrPersonFile(employee: HrEmployee.fromJson(data), balances: jlist(data['leave_balances'], HrLeaveBalance.fromJson));
  }

  /// Saves the details a person may correct themselves.
  Future<String> updateMe(Map<String, String?> fields) async => _message(await _api.put('/erp/hr/me', fields));

  Future<(List<HrLeaveRequest>, List<HrLeaveBalance>)> myLeave() async {
    final payload = await _map('/erp/hr/me/leave');
    return (jlist(payload['data'], HrLeaveRequest.fromJson), jlist(payload['balances'], HrLeaveBalance.fromJson));
  }

  Future<List<HrLeaveType>> leaveTypes() async {
    final payload = await _map('/erp/hr/leave-types');
    return jlist(payload['data'], HrLeaveType.fromJson).toList();
  }

  /// Applies for leave; returns the request as filed (with its days counted).
  Future<HrLeaveRequest> requestLeave(LeaveDraft draft) async =>
      HrLeaveRequest.fromJson(_data(await _api.post('/erp/hr/me/leave', draft.toJson())));

  Future<String> cancelMyLeave(int id) async => _message(await _api.post('/erp/hr/me/leave/$id/cancel'));

  Future<List<HrPayslipSummary>> myPayslips() async =>
      jlist((await _map('/erp/hr/me/payslips'))['data'], HrPayslipSummary.fromJson);

  /// One month of the caller's own attendance ("2026-11").
  Future<List<HrAttendance>> myAttendance(String month) async =>
      jlist((await _map('/erp/hr/me/attendance', {'month': month}))['data'], HrAttendance.fromJson);
}
