import 'package:get/get.dart';

import '../models/erp_models.dart';
import 'api_service.dart';

/// The Inventory app's endpoints (backend routes/api.php, `module:inventory`):
/// warehouses, products, balances, alerts and stock documents.
///
/// Every method returns parsed models; a refusal arrives as the API's
/// [ApiException] with its own wording, for the screen to show as is.
class InventoryRepository {
  InventoryRepository(this._api);

  final ApiService _api;

  /// The shared instance, registered on first use.
  static InventoryRepository get to => Get.isRegistered<InventoryRepository>()
      ? Get.find<InventoryRepository>()
      : Get.put(
          InventoryRepository(Get.find<ApiService>()),
          permanent: true,
        );

  Future<Map<String, dynamic>> _map(String path, [Map<String, dynamic>? q]) async =>
      Map<String, dynamic>.from(await _api.get(path, q) as Map);

  Map<String, dynamic> _data(dynamic payload) =>
      Map<String, dynamic>.from((payload as Map)['data'] as Map);

  /// The ERP home figures; null when the caller may not see inventory.
  Future<InventoryOverview?> overview() async {
    final payload = await _map('/erp/overview');
    return InventoryOverview.fromOverview(_data(payload));
  }

  /// Every warehouse, active ones first in the API's (name) order.
  Future<List<ErpWarehouse>> warehouses({bool activeOnly = false}) async {
    final payload = await _map('/erp/warehouses');
    final all = ((payload['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => ErpWarehouse.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return activeOnly ? all.where((w) => w.isActive).toList() : all;
  }

  Future<ErpPage<ErpProduct>> products({
    String? q,
    bool activeOnly = true,
    int perPage = 200,
    int page = 1,
  }) async => ErpPage.fromJson(
    await _map('/erp/products', {
      'q': q,
      'active_only': activeOnly ? 1 : null,
      'per_page': perPage,
      'page': page,
    }),
    ErpProduct.fromJson,
  );

  Future<ErpProductDetail> product(int id) async =>
      ErpProductDetail.fromJson(_data(await _api.get('/erp/products/$id')));

  Future<ErpPage<ErpStockBalance>> balances({
    String? q,
    int? warehouseId,
    int? productId,
    int page = 1,
    int perPage = 50,
  }) async => ErpPage.fromJson(
    await _map('/erp/stock/balances', {
      'q': q,
      'warehouse_id': warehouseId,
      'product_id': productId,
      'page': page,
      'per_page': perPage,
    }),
    ErpStockBalance.fromJson,
  );

  Future<StockAlerts> alerts() async =>
      StockAlerts.fromJson(_data(await _api.get('/erp/stock/alerts')));

  Future<ErpPage<ErpStockDocument>> documents({
    String? type,
    String? status,
    String? q,
    int page = 1,
  }) async => ErpPage.fromJson(
    await _map('/erp/stock-documents', {
      'type': type,
      'status': status,
      'q': q,
      'page': page,
    }),
    ErpStockDocument.fromJson,
  );

  Future<ErpStockDocument> document(int id) async =>
      ErpStockDocument.fromJson(
        _data(await _api.get('/erp/stock-documents/$id')),
      );

  /// Saves a draft; nothing moves on the shelf until it is posted.
  Future<ErpStockDocument> create(StockDocumentDraft draft) async =>
      ErpStockDocument.fromJson(
        _data(await _api.post('/erp/stock-documents', draft.toJson())),
      );

  /// Posts a draft. Returns the API's message ("GRN-… posted.").
  Future<String> post(int id) async {
    final r = await _api.post('/erp/stock-documents/$id/post');
    return '${(r as Map)['message'] ?? ''}';
  }

  /// Reverses a posted document; returns the reversing document.
  Future<ErpStockDocument> reverse(int id, String reason) async =>
      ErpStockDocument.fromJson(
        _data(
          await _api.post('/erp/stock-documents/$id/reverse', {
            'reason': reason,
          }),
        ),
      );

  Future<void> cancel(int id) => _api.post('/erp/stock-documents/$id/cancel');

  /// Active suppliers, for a GRN (only when the company runs procurement).
  Future<List<ErpRef>> suppliers() async {
    final payload = await _map('/erp/suppliers', {
      'active_only': 1,
      'per_page': 200,
    });
    return ((payload['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => ErpRef.fromJson(e)!)
        .toList();
  }
}
