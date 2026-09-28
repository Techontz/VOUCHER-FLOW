import 'package:get/get.dart';

import '../models/admin_models.dart';
import 'api_service.dart';

/// Every call the company-administration pages make, with the same paths,
/// verbs and bodies as the web client: employees, departments, the audit
/// log, voucher types, approval workflows, the company profile and billing.
class AdminRepository {
  AdminRepository(this._api);
  final ApiService _api;

  /// Registered once and shared.
  static AdminRepository get to => Get.isRegistered<AdminRepository>()
      ? Get.find<AdminRepository>()
      : Get.put(AdminRepository(Get.find<ApiService>()), permanent: true);

  Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : const {};

  List<Map<String, dynamic>> _rows(dynamic v) {
    final data = _m(v)['data'];
    return data is List ? [for (final r in data) if (r is Map) Map<String, dynamic>.from(r)] : const [];
  }

  /* ── people ── */

  Future<Paginated<Employee>> employees({String q = '', String role = '', String status = '', String departmentId = '', int page = 1}) async =>
      Paginated.fromJson(
        await _api.get('/employees', {'q': q, 'role': role, 'status': status, 'department_id': departmentId, 'page': page, 'per_page': 25}),
        Employee.fromJson,
      );

  /// Invites a person; returns them and, outside production, the one-time
  /// temporary password.
  Future<(Employee, String?)> inviteEmployee(Map<String, dynamic> body) async {
    final r = _m(await _api.post('/employees', {...body, 'send_invitation': true}));
    return (Employee.fromJson(_m(r['data'])), r['temporary_password'] as String?);
  }

  Future<void> updateEmployee(int id, Map<String, dynamic> body) => _api.put('/employees/$id', body);

  Future<void> deleteEmployee(int id) => _api.delete('/employees/$id');

  Future<List<DirectoryUser>> directory() async => [for (final r in _rows(await _api.get('/directory'))) DirectoryUser.fromJson(r)];

  Future<List<AdminDepartment>> departments() async =>
      [for (final r in _rows(await _api.get('/departments'))) AdminDepartment.fromJson(r)];

  Future<void> saveDepartment(int? id, Map<String, dynamic> body) =>
      id == null ? _api.post('/departments', body) : _api.put('/departments/$id', body);

  Future<void> deleteDepartment(int id) => _api.delete('/departments/$id');

  /* ── audit ── */

  Future<Paginated<AuditEntry>> audit({String q = '', String action = '', String from = '', String to = '', int page = 1}) async =>
      Paginated.fromJson(
        await _api.get('/audit-logs', {'q': q, 'action': action, 'from': from, 'to': to, 'page': page, 'per_page': 30}),
        AuditEntry.fromJson,
      );

  Future<List<String>> auditActions() async {
    final data = _m(await _api.get('/audit-logs/actions'))['data'];
    return data is List ? [for (final a in data) '$a'] : const [];
  }

  /* ── voucher types ── */

  Future<List<AdminVoucherType>> voucherTypes({bool includeInactive = false}) async => [
    for (final r in _rows(await _api.get('/voucher-types', {if (includeInactive) 'include_inactive': 'true'})))
      AdminVoucherType.fromJson(r),
  ];

  Future<void> saveVoucherType(int? id, Map<String, dynamic> body) =>
      id == null ? _api.post('/voucher-types', body) : _api.put('/voucher-types/$id', body);

  /* ── workflows ── */

  Future<List<Workflow>> workflows() async => [for (final r in _rows(await _api.get('/workflows'))) Workflow.fromJson(r)];

  Future<List<WorkflowPreset>> presets() async =>
      [for (final r in _rows(await _api.get('/workflows/presets'))) WorkflowPreset.fromJson(r)];

  Future<WorkflowRouting> routing(int workflowId) async =>
      WorkflowRouting.fromJson(_m(_m(await _api.get('/workflows/$workflowId/routing'))['data']));

  Future<Workflow> saveWorkflow(int id, Map<String, dynamic> body) async =>
      Workflow.fromJson(_m(_m(await _api.put('/workflows/$id', body))['data']));

  Future<Workflow> createWorkflow(Map<String, dynamic> body) async =>
      Workflow.fromJson(_m(_m(await _api.post('/workflows', body))['data']));

  Future<Workflow> applyPreset(String key) async =>
      Workflow.fromJson(_m(_m(await _api.post('/workflows/apply-preset', {'preset': key}))['data']));

  Future<Workflow> makeDefault(int id) async =>
      Workflow.fromJson(_m(_m(await _api.post('/workflows/$id/make-default'))['data']));

  Future<void> deleteWorkflow(int id) => _api.delete('/workflows/$id');

  /* ── the company ── */

  Future<CompanyProfile> company() async => CompanyProfile.fromJson(_m(_m(await _api.get('/company'))['data']));

  Future<void> updateCompany(Map<String, dynamic> body) => _api.put('/company', body);

  /* ── billing ── */

  Future<BillingState> billing() async => BillingState.fromJson(_m(await _api.get('/billing/subscription')));

  Future<List<Invoice>> invoices() async =>
      [for (final r in _rows(await _api.get('/billing/invoices', {'per_page': 20}))) Invoice.fromJson(r)];

  /// Changes plan; returns the server's message and the invoice to pay.
  Future<(String, Invoice?)> subscribe(int planId, String cycle) async {
    final r = _m(await _api.post('/billing/subscribe', {'plan_id': planId, 'billing_cycle': cycle}));
    return ('${r['message'] ?? ''}', r['invoice'] is Map ? Invoice.fromJson(_m(r['invoice'])) : null);
  }

  Future<Invoice> pay(int invoiceId, String method, String? reference) async {
    final r = _m(await _api.post('/billing/invoices/$invoiceId/pay', {
      'method': method,
      if (reference != null && reference.isNotEmpty) 'reference': reference,
    }));
    return Invoice.fromJson(_m(r['invoice']));
  }

  Future<void> setAutoRenew(bool value) => _api.post('/billing/auto-renew', {'auto_renew': value});
}
