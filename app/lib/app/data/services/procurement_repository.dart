import 'package:get/get.dart';

import '../models/erp_models.dart';
import '../models/finance_models.dart';
import 'api_service.dart';

/// The Procurement app's endpoints (backend routes/erp/procurement.php,
/// integration.php and the core suppliers routes): requisitions, orders,
/// supplier invoices and payments, the payables ageing, statements, and
/// the payment voucher raised in VouchFlow for an invoice.
///
/// A refusal arrives as the API's [ApiException] with its own wording, for
/// the screen to show as is.
class ProcurementRepository {
  ProcurementRepository(this._api);

  final ApiService _api;

  /// The shared instance, registered on first use.
  static ProcurementRepository get to => Get.isRegistered<ProcurementRepository>()
      ? Get.find<ProcurementRepository>()
      : Get.put(ProcurementRepository(Get.find<ApiService>()), permanent: true);

  static const _base = '/erp/procurement';

  Future<Map<String, dynamic>> _map(String path, [Map<String, dynamic>? q]) async =>
      Map<String, dynamic>.from(await _api.get(path, q) as Map);

  Map<String, dynamic> _data(dynamic payload) => Map<String, dynamic>.from((payload as Map)['data'] as Map);

  String _message(dynamic r) => '${(r as Map)['message'] ?? ''}';

  Future<ProcurementOverview> overview() async => ProcurementOverview.fromJson(_data(await _api.get('$_base/overview')));

  Future<PayablesAgeing> ageing() async => PayablesAgeing.fromJson(_data(await _api.get('$_base/ageing')));

  /* ── suppliers ── */

  Future<ErpPage<Supplier>> suppliers({String? q, int page = 1}) async =>
      ErpPage.fromJson(await _map('/erp/suppliers', {'q': q, 'page': page, 'per_page': 50}), Supplier.fromJson);

  Future<Supplier> supplier(int id) async => Supplier.fromJson(_data(await _api.get('/erp/suppliers/$id')));

  Future<SupplierStatement> statement(int supplierId, {DateTime? from, DateTime? to}) async =>
      SupplierStatement.fromJson(
        _data(await _api.get('$_base/statement/$supplierId', {'from': _day(from), 'to': _day(to)})),
      );

  /* ── requisitions ── */

  Future<ErpPage<PurchaseRequisition>> requisitions({String? status, String? q, int page = 1}) async =>
      ErpPage.fromJson(
        await _map('$_base/requisitions', {'status': status, 'q': q, 'page': page}),
        PurchaseRequisition.fromJson,
      );

  Future<PurchaseRequisition> requisition(int id) async =>
      PurchaseRequisition.fromJson(_data(await _api.get('$_base/requisitions/$id')));

  /// Saves a draft requisition and, when [submit], sends it for approval.
  Future<PurchaseRequisition> createRequisition({
    required String justification,
    required List<RequisitionLineDraft> lines,
    DateTime? neededBy,
    bool submit = true,
  }) async {
    final created = PurchaseRequisition.fromJson(
      _data(
        await _api.post('$_base/requisitions', {
          'justification': justification,
          'needed_by': _day(neededBy),
          'lines': [for (final l in lines) l.toJson()],
        }),
      ),
    );
    if (!submit) return created;
    await _api.post('$_base/requisitions/${created.id}/submit');
    return created;
  }

  Future<String> submitRequisition(int id) async => _message(await _api.post('$_base/requisitions/$id/submit'));

  Future<String> approveRequisition(int id, String comment) async =>
      _message(await _api.post('$_base/requisitions/$id/approve', {if (comment.isNotEmpty) 'comment': comment}));

  Future<String> rejectRequisition(int id, String comment) async =>
      _message(await _api.post('$_base/requisitions/$id/reject', {'comment': comment}));

  /* ── orders ── */

  Future<ErpPage<PurchaseOrder>> orders({String? status, String? q, int? supplierId, int page = 1}) async =>
      ErpPage.fromJson(
        await _map('$_base/orders', {'status': status, 'q': q, 'supplier_id': supplierId, 'page': page}),
        PurchaseOrder.fromJson,
      );

  Future<PurchaseOrder> order(int id) async => PurchaseOrder.fromJson(_data(await _api.get('$_base/orders/$id')));

  Future<String> approveOrder(int id, String comment) async =>
      _message(await _api.post('$_base/orders/$id/approve', {if (comment.isNotEmpty) 'comment': comment}));

  Future<String> rejectOrder(int id, String comment) async =>
      _message(await _api.post('$_base/orders/$id/reject', {'comment': comment}));

  /* ── supplier invoices ── */

  Future<ErpPage<SupplierInvoice>> invoices({String? status, String? q, int? supplierId, int page = 1}) async =>
      ErpPage.fromJson(
        await _map('$_base/invoices', {'status': status, 'q': q, 'supplier_id': supplierId, 'page': page}),
        SupplierInvoice.fromJson,
      );

  Future<SupplierInvoice> invoice(int id) async =>
      SupplierInvoice.fromJson(_data(await _api.get('$_base/invoices/$id')));

  /// Accepts a price or quantity variance so the invoice may be posted.
  Future<String> approveInvoice(int id, String comment) async =>
      _message(await _api.post('$_base/invoices/$id/approve', {if (comment.isNotEmpty) 'comment': comment}));

  /// The payment voucher on its way for this invoice, or null.
  Future<VoucherLink?> voucherFor(int invoiceId) async =>
      VoucherLink.fromJson((await _api.get('$_base/invoices/$invoiceId/voucher') as Map)['data']);

  /// Raises a draft VouchFlow payment voucher for what is still owed.
  Future<VoucherLink> raiseVoucher(int invoiceId) async =>
      VoucherLink.fromJson(_data(await _api.post('$_base/invoices/$invoiceId/voucher')))!;

  /* ── supplier payments ── */

  Future<ErpPage<SupplierPayment>> payments({String? status, String? q, int? supplierId, int page = 1}) async =>
      ErpPage.fromJson(
        await _map('$_base/payments', {'status': status, 'q': q, 'supplier_id': supplierId, 'page': page}),
        SupplierPayment.fromJson,
      );

  Future<SupplierPayment> payment(int id) async =>
      SupplierPayment.fromJson(_data(await _api.get('$_base/payments/$id')));

  /// Active stock products, for a requisition line (only when the company
  /// runs inventory).
  Future<List<ErpProduct>> products() async {
    final payload = await _map('$_base/lookups');
    final data = Map<String, dynamic>.from((payload['data'] as Map?) ?? const {});
    return ((data['products'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => ErpProduct.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}

String? _day(DateTime? d) =>
    d == null ? null : '${d.year}-${'${d.month}'.padLeft(2, '0')}-${'${d.day}'.padLeft(2, '0')}';
