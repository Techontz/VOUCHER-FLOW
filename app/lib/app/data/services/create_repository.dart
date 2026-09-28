import 'dart:typed_data';

import 'package:get/get.dart';

import '../models/vouchers_models.dart';
import 'api_service.dart';

/// The calls the voucher register and the create/edit screens make beyond
/// [VoucherRepository]: the filtered, paginated register with its totals,
/// voucher types with their codes, the company's workflows (for the approval
/// route), the server-rendered draft preview and the register export.
class CreateRepository {
  CreateRepository(this._api);

  final ApiService _api;

  /// The shared instance, registered on first use.
  static CreateRepository get to => Get.isRegistered<CreateRepository>()
      ? Get.find<CreateRepository>()
      : Get.put(CreateRepository(Get.find<ApiService>()), permanent: true);

  /// Workflows per company: signing into another tenant must never show the
  /// first company's routes.
  final Map<int, List<RouteWorkflow>> _workflows = {};

  static Map<String, dynamic> _clean(Map<String, dynamic> params) =>
      Map.of(params)..removeWhere((_, v) => v == null || '$v'.isEmpty);

  /// `GET /vouchers` with the register's filters, 20 a page as on the web.
  Future<RegisterPage> register(Map<String, dynamic> filters, {int page = 1}) async {
    final payload = await _api.get('/vouchers', {..._clean(filters), 'page': page, 'per_page': 20});
    return RegisterPage.fromJson(Map<String, dynamic>.from(payload as Map));
  }

  Future<List<VoucherTypeOption>> types() async {
    final payload = await _api.get('/voucher-types') as Map;
    return (payload['data'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => VoucherTypeOption.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// The company's workflows, fetched once per company.
  Future<List<RouteWorkflow>> workflows(int companyId) async {
    final cached = _workflows[companyId];
    if (cached != null) return cached;
    final payload = await _api.get('/workflows') as Map;
    final list = (payload['data'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => RouteWorkflow.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return _workflows[companyId] = list;
  }

  /// The draft as the server renders it, in the company's chosen template.
  Future<String> documentPreview(Map<String, dynamic> draft) async {
    final payload = await _api.post('/vouchers/document-preview', draft) as Map;
    final html = payload['html'];
    if (html is! String || html.isEmpty) throw ApiException(500, 'No preview.');
    return html;
  }

  /// Exactly the register rows the filters select, as PDF, Excel or CSV.
  Future<Uint8List> exportVouchers(Map<String, dynamic> filters, String format) async =>
      Uint8List.fromList(await _api.bytes('/reports/vouchers/export', {..._clean(filters), 'format': format}));
}
