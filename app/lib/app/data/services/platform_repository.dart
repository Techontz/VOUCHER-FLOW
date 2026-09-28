import 'package:get/get.dart';

import '../models/platform_models.dart';
import 'api_service.dart';

/// The platform super admin's API: tenants, plans, invoices, users, and the
/// per-company insight endpoints (routes/api.php, prefix `platform`).
class PlatformRepository {
  PlatformRepository(this._api);

  final ApiService _api;

  static PlatformRepository get to => Get.isRegistered<PlatformRepository>()
      ? Get.find<PlatformRepository>()
      : Get.put(PlatformRepository(Get.find<ApiService>()), permanent: true);

  Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  // ── companies ──

  Future<PlatformPage<PlatformCompany>> companies({String q = '', String status = '', int page = 1, int perPage = 25}) async =>
      PlatformPage.fromJson(
        _m(await _api.get('/platform/companies', {'q': q, 'status': status, 'page': page, 'per_page': perPage})),
        PlatformCompany.fromJson,
      );

  /// Company names by id, for naming a user's tenant.
  Future<Map<int, String>> companyNames() async {
    final page = await companies(perPage: 500);
    return {for (final c in page.items) c.id: c.name};
  }

  /// Provisions a tenant on a trial with its first administrator. Returns the
  /// created company's name.
  Future<String> createCompany({
    required String name,
    required String email,
    String? phone,
    int? planId,
    required String adminName,
    required String adminEmail,
    String? adminJobTitle,
    required String adminPassword,
  }) async {
    final res = _m(await _api.post('/platform/companies', {
      'company': {'name': name, 'email': email, 'phone': ?phone},
      'admin': {'name': adminName, 'email': adminEmail, 'job_title': ?adminJobTitle, 'password': adminPassword},
      'plan_id': ?planId,
    }));
    return '${_m(res['data'])['name'] ?? name}';
  }

  Future<void> setCompanyStatus(int id, {required bool suspend}) =>
      _api.post('/platform/companies/$id/${suspend ? 'suspend' : 'activate'}');

  Future<void> deleteCompany(int id) => _api.delete('/platform/companies/$id');

  Future<CompanyDetail> company(int id) async => CompanyDetail.fromJson(_m(await _api.get('/platform/companies/$id')));

  Future<CompanyOverview> overview(int id) async =>
      CompanyOverview.fromJson(_m(_m(await _api.get('/platform/companies/$id/overview'))['data']));

  Future<List<DepartmentRow>> departments(int id) async {
    final res = _m(await _api.get('/platform/companies/$id/departments'));
    return [for (final e in (res['data'] as List? ?? const [])) DepartmentRow.fromJson(_m(e))];
  }

  Future<CompanyWorkflows> workflows(int id) async =>
      CompanyWorkflows.fromJson(_m(_m(await _api.get('/platform/companies/$id/workflows'))['data']));

  Future<PlatformPage<PlatformUser>> companyUsers(int id, Map<String, String> filters, {int page = 1, int perPage = 25}) async =>
      PlatformPage.fromJson(
        _m(await _api.get('/platform/companies/$id/users', {...filters, 'page': page, 'per_page': perPage})),
        PlatformUser.fromJson,
      );

  Future<PlatformPage<PlatformVoucherRow>> companyVouchers(int id, Map<String, String> filters, {int page = 1}) async =>
      PlatformPage.fromJson(
        _m(await _api.get('/platform/companies/$id/vouchers', {...filters, 'page': page, 'per_page': 20})),
        PlatformVoucherRow.fromJson,
      );

  Future<PlatformPage<AuditEntry>> activity(int companyId, {String q = '', int page = 1}) async => PlatformPage.fromJson(
    _m(await _api.get('/audit-logs', {'company_id': companyId, 'q': q, 'page': page, 'per_page': 30})),
    AuditEntry.fromJson,
  );

  /// Moves the tenant onto another plan. Returns the server's message.
  Future<String> changePlan(int id, int planId) async {
    final res = _m(await _api.post('/platform/companies/$id/change-plan', {'plan_id': planId}));
    return '${res['message'] ?? ''}';
  }

  /// Blank fields are sent as null, which the endpoint leaves as they are.
  Future<void> saveBranding(int id, Map<String, String> fields) => _api.post(
    '/platform/companies/$id/branding',
    {for (final e in fields.entries) e.key: e.value.trim().isEmpty ? null : e.value.trim()},
  );

  // ── plans ──

  Future<List<PlatformPlan>> plans() async {
    final res = _m(await _api.get('/platform/plans'));
    return [for (final e in (res['data'] as List? ?? const [])) PlatformPlan.fromJson(_m(e))];
  }

  Future<void> savePlan(int? id, Map<String, dynamic> payload) =>
      id == null ? _api.post('/platform/plans', payload) : _api.put('/platform/plans/$id', payload);

  // ── payments ──

  Future<PlatformPage<PlatformInvoice>> payments({String q = '', String status = '', String method = '', int page = 1}) async =>
      PlatformPage.fromJson(
        _m(await _api.get('/platform/payments', {'q': q, 'status': status, 'method': method, 'page': page, 'per_page': 25})),
        PlatformInvoice.fromJson,
      );

  Future<void> refund(int invoiceId) => _api.post('/platform/payments/$invoiceId/refund');

  Future<void> markPaid(int invoiceId) => _api.post('/platform/payments/$invoiceId/mark-paid', {'reference': 'manual'});

  // ── users ──

  Future<PlatformPage<PlatformUser>> users({String q = '', String role = '', String status = '', int page = 1}) async =>
      PlatformPage.fromJson(
        _m(await _api.get('/platform/users', {'q': q, 'role': role, 'status': status, 'page': page, 'per_page': 25})),
        PlatformUser.fromJson,
      );

  Future<void> setUserStatus(int userId, String status) => _api.put('/platform/users/$userId', {'status': status});
}
