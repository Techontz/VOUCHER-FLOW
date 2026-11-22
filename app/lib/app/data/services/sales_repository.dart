import 'package:get/get.dart';

import '../models/erp_models.dart' show ErpPage;
import '../models/sales_models.dart';
import 'api_service.dart';

/// The Sales and Dispatch apps' endpoints (backend routes/erp/sales.php,
/// `module:sales` and `module:dispatch`, plus /erp/customers).
///
/// Every method returns parsed models; an action returns the API's own
/// message ("SO-2026-000002 submitted for approval."), and a refusal
/// arrives as the API's [ApiException], for the screen to show as is.
class SalesRepository {
  SalesRepository(this._api);

  final ApiService _api;

  /// The shared instance, registered on first use.
  static SalesRepository get to => Get.isRegistered<SalesRepository>()
      ? Get.find<SalesRepository>()
      : Get.put(SalesRepository(Get.find<ApiService>()), permanent: true);

  Future<Map<String, dynamic>> _map(String path, [Map<String, dynamic>? q]) async =>
      Map<String, dynamic>.from(await _api.get(path, q) as Map);

  Map<String, dynamic> _data(dynamic payload) => Map<String, dynamic>.from((payload as Map)['data'] as Map);

  String _message(dynamic payload) => payload is Map ? '${payload['message'] ?? ''}' : '';

  Future<String> _act(String path, [Map<String, dynamic>? body]) async => _message(await _api.post(path, body));

  /* ───────────────────────────────────────────────────────── sales ── */

  Future<SalesOverview> overview() async => SalesOverview.fromJson(_data(await _api.get('/erp/sales/overview')));

  Future<SalesLookups> lookups() async => SalesLookups.fromJson(_data(await _api.get('/erp/sales/lookups')));

  /// Product id to the price this customer pays today (its price list, or
  /// the product's own price).
  Future<Map<int, double>> prices(int customerId) async {
    final payload = await _map('/erp/sales/prices', {'customer_id': customerId});
    final out = <int, double>{};
    final data = payload['data'];
    if (data is Map) {
      data.forEach((k, v) {
        final price = v is Map ? v['price'] : null;
        final id = int.tryParse('$k');
        if (id != null && price is num) out[id] = price.toDouble();
      });
    }
    return out;
  }

  Future<ErpPage<SalesCustomer>> customers({String? q, int page = 1}) async => ErpPage.fromJson(
    await _map('/erp/customers', {'q': q, 'page': page, 'per_page': 50}),
    SalesCustomer.fromJson,
  );

  Future<SalesCustomer> customer(int id) async => SalesCustomer.fromJson(_data(await _api.get('/erp/customers/$id')));

  Future<CustomerStatement> statement(int customerId, {DateTime? from, DateTime? to}) async => CustomerStatement.fromJson(
    _data(
      await _api.get('/erp/sales/customers/$customerId/statement', {
        'from': from == null ? null : salesIsoDate(from),
        'to': to == null ? null : salesIsoDate(to),
      }),
    ),
  );

  Future<ErpPage<SalesQuotation>> quotations({String? status, String? q, int? customerId, int page = 1}) async =>
      ErpPage.fromJson(
        await _map('/erp/sales/quotations', {'status': status, 'q': q, 'customer_id': customerId, 'page': page}),
        SalesQuotation.fromJson,
      );

  Future<SalesQuotation> quotation(int id) async =>
      SalesQuotation.fromJson(_data(await _api.get('/erp/sales/quotations/$id')));

  /// 'send' | 'reject' | 'cancel'.
  Future<String> quotationAction(int id, String action) => _act('/erp/sales/quotations/$id/$action');

  /// Turns a quotation into a draft order; returns the order.
  Future<SalesOrder> convert(int id) async =>
      SalesOrder.fromJson(_data(await _api.post('/erp/sales/quotations/$id/convert')));

  Future<ErpPage<SalesOrder>> orders({String? status, String? q, int? customerId, int page = 1}) async =>
      ErpPage.fromJson(
        await _map('/erp/sales/orders', {'status': status, 'q': q, 'customer_id': customerId, 'page': page}),
        SalesOrder.fromJson,
      );

  Future<Map<String, int>> orderCounts() async {
    final data = (await _map('/erp/sales/orders/counts'))['data'];
    return data is Map ? {for (final e in data.entries) '${e.key}': int.tryParse('${e.value}') ?? 0} : {};
  }

  Future<SalesOrder> order(int id) async => SalesOrder.fromJson(_data(await _api.get('/erp/sales/orders/$id')));

  /// Saves an order or a quotation as a draft.
  Future<(int, String)> create(SalesDocumentDraft draft) async {
    final path = draft.quotation ? '/erp/sales/quotations' : '/erp/sales/orders';
    final data = _data(await _api.post(path, draft.toJson()));
    return (int.tryParse('${data['id']}') ?? 0, '${data['number'] ?? ''}');
  }

  Future<String> submitOrder(int id) => _act('/erp/sales/orders/$id/submit');

  Future<String> approveOrder(int id, {Map<int, double>? quantities, String? overrideReason}) =>
      _act('/erp/sales/orders/$id/approve', {
        'quantities': {for (final e in (quantities ?? const <int, double>{}).entries) '${e.key}': e.value},
        'override_reason': (overrideReason ?? '').trim().isEmpty ? null : overrideReason!.trim(),
      });

  Future<String> rejectOrder(int id, String reason) => _act('/erp/sales/orders/$id/reject', {'reason': reason});

  Future<String> cancelOrder(int id) => _act('/erp/sales/orders/$id/cancel');

  /// Raises a draft invoice for what was approved, or for one delivery.
  Future<SalesInvoice> invoiceOrder(int id, {int? loadingOrderId}) async => SalesInvoice.fromJson(
    _data(await _api.post('/erp/sales/orders/$id/invoice', {'loading_order_id': loadingOrderId})),
  );

  Future<ErpPage<SalesInvoice>> invoices({
    String? status,
    bool openOnly = false,
    bool overdue = false,
    int? customerId,
    String? q,
    int page = 1,
    int perPage = 30,
  }) async => ErpPage.fromJson(
    await _map('/erp/sales/invoices', {
      'status': status,
      'open_only': openOnly ? 1 : null,
      'overdue': overdue ? 1 : null,
      'customer_id': customerId,
      'q': q,
      'page': page,
      'per_page': perPage,
    }),
    SalesInvoice.fromJson,
  );

  Future<SalesInvoice> invoice(int id) async => SalesInvoice.fromJson(_data(await _api.get('/erp/sales/invoices/$id')));

  Future<String> postInvoice(int id) => _act('/erp/sales/invoices/$id/post');

  Future<String> cancelInvoice(int id) => _act('/erp/sales/invoices/$id/cancel');

  Future<ErpPage<SalesReceipt>> receipts({String? status, String? q, int? customerId, int page = 1}) async =>
      ErpPage.fromJson(
        await _map('/erp/sales/receipts', {'status': status, 'q': q, 'customer_id': customerId, 'page': page}),
        SalesReceipt.fromJson,
      );

  Future<SalesReceipt> receipt(int id) async => SalesReceipt.fromJson(_data(await _api.get('/erp/sales/receipts/$id')));

  /// Records money received against open invoices; returns the API's
  /// message and the receipt.
  Future<(String, SalesReceipt)> recordReceipt({
    required int customerId,
    required int accountId,
    required String method,
    required DateTime date,
    String? reference,
    String? notes,
    required Map<int, double> allocations,
  }) async {
    final payload = await _api.post('/erp/sales/receipts', {
      'customer_id': customerId,
      'account_id': accountId,
      'method': method,
      'receipt_date': salesIsoDate(date),
      'reference': (reference ?? '').trim().isEmpty ? null : reference!.trim(),
      'notes': (notes ?? '').trim().isEmpty ? null : notes!.trim(),
      'allocations': [
        for (final e in allocations.entries)
          if (e.value > 0) {'sales_invoice_id': e.key, 'amount': e.value},
      ],
    });
    return (_message(payload), SalesReceipt.fromJson(_data(payload)));
  }

  Future<String> verifyReceipt(int id) => _act('/erp/sales/receipts/$id/verify');

  Future<String> rejectReceipt(int id, String reason) => _act('/erp/sales/receipts/$id/reject', {'reason': reason});

  /* ────────────────────────────────────────────────────── dispatch ── */

  Future<DispatchLookups> dispatchLookups() async =>
      DispatchLookups.fromJson(_data(await _api.get('/erp/dispatch/lookups')));

  Future<VerificationQueue> verification() async =>
      VerificationQueue.fromJson(_data(await _api.get('/erp/dispatch/verification')));

  /// [stage]: null | 'delivery_notes' | 'gate_passes' | 'in_transit' |
  /// 'discrepancies'.
  Future<ErpPage<LoadingOrder>> loadingOrders({String? stage, String? status, String? q, int? salesOrderId, int page = 1}) async =>
      ErpPage.fromJson(
        await _map('/erp/dispatch/loading-orders', {
          'stage': stage,
          'status': status,
          'q': q,
          'sales_order_id': salesOrderId,
          'page': page,
        }),
        LoadingOrder.fromJson,
      );

  Future<LoadingOrder> loadingOrder(int id) async =>
      LoadingOrder.fromJson(_data(await _api.get('/erp/dispatch/loading-orders/$id')));

  /// Plans a truck for an order; returns the new loading order.
  Future<LoadingOrder> createLoading({
    required int salesOrderId,
    required int warehouseId,
    DateTime? plannedDate,
    String? vehicleNumber,
    String? driverName,
    String? destination,
    required Map<int, double> quantities,
  }) async {
    String? blank(String? s) => (s ?? '').trim().isEmpty ? null : s!.trim();
    return LoadingOrder.fromJson(
      _data(
        await _api.post('/erp/dispatch/loading-orders', {
          'sales_order_id': salesOrderId,
          'warehouse_id': warehouseId,
          'planned_date': plannedDate == null ? null : salesIsoDate(plannedDate),
          'vehicle_number': blank(vehicleNumber),
          'driver_name': blank(driverName),
          'destination': blank(destination),
          'quantities': {for (final e in quantities.entries) '${e.key}': e.value},
        }),
      ),
    );
  }

  /// What actually went on the truck, line by line (null clears a line).
  Future<String> saveLoaded(int id, Map<int, double?> quantities) async => _message(
    await _api.put('/erp/dispatch/loading-orders/$id/loaded', {
      'quantities': {for (final e in quantities.entries) '${e.key}': e.value},
    }),
  );

  Future<String> confirmLoading(int id) => _act('/erp/dispatch/loading-orders/$id/confirm-loading');

  Future<String> confirmDriver(int id, String? name) =>
      _act('/erp/dispatch/loading-orders/$id/confirm-driver', {'name': (name ?? '').trim().isEmpty ? null : name!.trim()});

  Future<String> confirmSecurity(int id, String? name) =>
      _act('/erp/dispatch/loading-orders/$id/confirm-security', {'name': (name ?? '').trim().isEmpty ? null : name!.trim()});

  Future<String> issueDeliveryNote(int id) => _act('/erp/dispatch/loading-orders/$id/delivery-note');

  /// The truck leaves the gate: the loading order is out for delivery.
  Future<String> issueGatePass(int id) => _act('/erp/dispatch/loading-orders/$id/gate-pass');

  /// Proof of delivery: who signed, when, and what the customer accepted.
  Future<String> deliver(
    int id, {
    required String receivedBy,
    required DateTime date,
    String? remark,
    required Map<int, double> quantities,
  }) => _act('/erp/dispatch/loading-orders/$id/deliver', {
    'received_by_name': receivedBy.trim(),
    'received_date': salesIsoDate(date),
    'remark': (remark ?? '').trim().isEmpty ? null : remark!.trim(),
    'quantities': {for (final e in quantities.entries) '${e.key}': e.value},
  });

  /// A short delivery: back to stock ('return') or lost ('write_off').
  Future<String> resolve(int id, String decision, String note) =>
      _act('/erp/dispatch/loading-orders/$id/resolve', {'decision': decision, 'note': note});

  Future<String> cancelLoading(int id) => _act('/erp/dispatch/loading-orders/$id/cancel');
}
