import 'package:get/get.dart';

import '../models/erp_models.dart' show ErpPage;
import '../models/ops_models.dart';
import 'api_service.dart';

/// The Production app's endpoints (backend routes/erp/production.php,
/// `module:production`): the overview, orders and the actions on them,
/// bills of materials and the quality-control queue.
class ProductionRepository {
  ProductionRepository(this._api);

  final ApiService _api;

  static ProductionRepository get to => Get.isRegistered<ProductionRepository>()
      ? Get.find<ProductionRepository>()
      : Get.put(ProductionRepository(Get.find<ApiService>()), permanent: true);

  static const _base = '/erp/production';

  Future<Map<String, dynamic>> _map(String path, [Map<String, dynamic>? q]) async =>
      Map<String, dynamic>.from(await _api.get(path, q) as Map);

  Map<String, dynamic> _data(dynamic payload) => Map<String, dynamic>.from((payload as Map)['data'] as Map);

  String _message(dynamic payload) => payload is Map ? '${payload['message'] ?? ''}' : '';

  Future<ProductionOverview> overview() async => ProductionOverview.fromJson(_data(await _api.get('$_base/overview')));

  /// [status] is one of [PrdStatus.all], 'open', or null for every order.
  Future<ErpPage<ProductionOrder>> orders({String? status, String? q, int page = 1}) async => ErpPage.fromJson(
    await _map('$_base/orders', {'status': status, 'q': q, 'page': page, 'per_page': 30}),
    ProductionOrder.fromJson,
  );

  Future<ProductionOrder> order(int id) async => ProductionOrder.fromJson(_data(await _api.get('$_base/orders/$id')));

  Future<PrdOptions> options() async => PrdOptions.fromJson(_data(await _api.get('$_base/options')));

  /// Plans an order; returns it.
  Future<ProductionOrder> plan(PrdOrderDraft draft) async =>
      ProductionOrder.fromJson(_data(await _api.post('$_base/orders', draft.toJson())));

  /// What the order would need before it is planned: the requirements
  /// against the store, and the standard cost per unit.
  Future<({List<PrdRequirement> requirements, double? unitCost})> check(PrdOrderDraft draft) async {
    final data = _data(
      await _api.post('$_base/orders/check', {
        'product_id': draft.productId,
        'planned_quantity': double.tryParse(draft.quantity.trim()) ?? 0,
        'materials_warehouse_id': draft.materialsWarehouseId,
      }),
    );
    final standard = data['standard'] is Map ? data['standard'] as Map : const {};
    return (
      requirements: ((data['requirements'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => PrdRequirement.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      unitCost: standard['unit_cost'] is num ? (standard['unit_cost'] as num).toDouble() : null,
    );
  }

  /// Release, complete or close; returns the API's message.
  Future<String> act(int id, String action) async => _message(await _api.post('$_base/orders/$id/$action'));

  Future<String> cancel(int id, String reason) async =>
      _message(await _api.post('$_base/orders/$id/cancel', {'reason': reason}));

  /// Issues materials to the order (posted at once).
  Future<String> issue(int id, List<Map<String, dynamic>> lines) async =>
      _message(await _api.post('$_base/orders/$id/issue', {'lines': lines}));

  /// Records output; it waits for its quality check before entering stock.
  Future<String> receive(int id, Map<String, dynamic> output) async =>
      _message(await _api.post('$_base/orders/$id/receipts', output));

  Future<ErpPage<PrdReceipt>> qc({String status = PrdReceiptStatus.pending, String? q, int page = 1}) async =>
      ErpPage.fromJson(await _map('$_base/qc', {'status': status, 'q': q, 'page': page, 'per_page': 30}), PrdReceipt.fromJson);

  /// Releases the batch into stock or rejects it.
  Future<String> inspect(int receiptId, {required String decision, required List<QcParameter> parameters, String? notes}) async =>
      _message(
        await _api.post('$_base/receipts/$receiptId/qc', {
          'decision': decision,
          'parameters': [for (final p in parameters) if (p.name.trim().isNotEmpty) p.toJson()],
          'notes': (notes ?? '').trim().isEmpty ? null : notes!.trim(),
        }),
      );

  Future<ErpPage<PrdBom>> boms({String? q, int page = 1}) async =>
      ErpPage.fromJson(await _map('$_base/boms', {'q': q, 'page': page, 'per_page': 30}), PrdBom.fromJson);

  Future<PrdBom> bom(int id) async => PrdBom.fromJson(_data(await _api.get('$_base/boms/$id')));
}
