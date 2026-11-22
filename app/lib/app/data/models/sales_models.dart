import 'erp_models.dart' show ErpRef;

/*
 * The shapes the Sales and Dispatch endpoints return (/api/erp/sales/...,
 * /api/erp/dispatch/..., /api/erp/customers), as the web's lib/sales-api.ts
 * types them. Decimals arrive as strings ("8500.00"); every reader here
 * turns them into numbers once, so screens never parse.
 */

double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

double? _dn(dynamic v) => v == null ? null : _d(v);

int _i(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

int? _in(dynamic v) => v == null ? null : _i(v);

String? _s(dynamic v) {
  if (v == null) return null;
  final s = '$v';
  return s.isEmpty ? null : s;
}

/// A calendar date: only the day is read, so midnight UTC never becomes
/// yesterday on a phone west of Greenwich.
DateTime? _date(dynamic v) {
  final s = _s(v);
  if (s == null || s.length < 10) return null;
  return DateTime.tryParse(s.substring(0, 10));
}

DateTime? _time(dynamic v) {
  final s = _s(v);
  return s == null ? null : DateTime.tryParse(s)?.toLocal();
}

Map<String, dynamic>? _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : null;

List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) read) =>
    (v is List ? v : const []).whereType<Map>().map((e) => read(Map<String, dynamic>.from(e))).toList();

String? _name(dynamic v) => _s(_map(v)?['name']);

/// "2026-11-12", the way the API takes a date.
String salesIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A document another one points at: `{id, number, status?}`.
class SalesDocRef {
  const SalesDocRef(this.id, this.number, [this.status]);

  static SalesDocRef? fromJson(dynamic json) {
    final m = _map(json);
    if (m == null) return null;
    return SalesDocRef(_i(m['id']), '${m['number'] ?? ''}', _s(m['status']));
  }

  final int id;
  final String number;
  final String? status;
}

/* ─────────────────────────────────────────────────────────── statuses ── */

abstract class SalesStatus {
  static const draft = 'draft';
  static const sent = 'sent';
  static const converted = 'converted';
  static const rejected = 'rejected';
  static const cancelled = 'cancelled';
  static const submitted = 'submitted';
  static const awaitingPayment = 'awaiting_payment';
  static const ready = 'ready';
  static const loading = 'loading';
  static const dispatched = 'dispatched';
  static const delivered = 'delivered';
  static const posted = 'posted';
  static const recorded = 'recorded';
  static const verified = 'verified';
  static const open = 'open';
  static const loaded = 'loaded';
  static const returned = 'returned';
  static const writtenOff = 'written_off';

  /// The order pipeline, in the order an order travels it.
  static const pipeline = [draft, submitted, awaitingPayment, ready, loading, dispatched, delivered];

  /// The web's statusTone, as the badge tag it paints.
  static String tag(String status) => switch (status) {
    delivered || posted || verified || converted || returned => 'tag-accent',
    submitted || awaitingPayment || recorded || open || writtenOff => 'tag-warn',
    rejected => 'tag-accent-2',
    cancelled => 'tag-neutral',
    _ => 'tag-info',
  };
}

/// How a customer may pay.
const salesReceiptMethods = ['cash', 'bank_transfer', 'mobile_money', 'cheque'];

/* ─────────────────────────────────────────────────────────── customers ── */

class SalesCustomer {
  const SalesCustomer({
    required this.id,
    required this.code,
    required this.name,
    this.group,
    this.contactPerson,
    this.phone,
    this.email,
    this.tin,
    this.address,
    this.city,
    this.creditLimit = 0,
    this.paymentTermsDays = 0,
    this.requiresPrepayment = false,
    this.priceList,
    this.isActive = true,
  });

  factory SalesCustomer.fromJson(Map<String, dynamic> json) => SalesCustomer(
    id: _i(json['id']),
    code: '${json['code'] ?? ''}',
    name: '${json['name'] ?? ''}',
    group: _s(json['customer_group']),
    contactPerson: _s(json['contact_person']),
    phone: _s(json['phone']),
    email: _s(json['email']),
    tin: _s(json['tin']),
    address: _s(json['address']),
    city: _s(json['city']),
    creditLimit: _d(json['credit_limit']),
    paymentTermsDays: _i(json['payment_terms_days']),
    requiresPrepayment: json['requires_prepayment'] == true,
    priceList: _s(json['price_list']),
    isActive: json['is_active'] != false,
  );

  static SalesCustomer? maybe(dynamic json) {
    final m = _map(json);
    return m == null ? null : SalesCustomer.fromJson(m);
  }

  final int id;
  final String code, name;
  final String? group, contactPerson, phone, email, tin, address, city, priceList;
  final double creditLimit;
  final int paymentTermsDays;
  final bool requiresPrepayment, isActive;

  /// "Dar es Salaam · Kenyatta Road".
  String get place => [?city, ?address].join(' · ');
}

class StatementLine {
  const StatementLine({
    required this.date,
    required this.type,
    required this.id,
    required this.number,
    required this.detail,
    required this.debit,
    required this.credit,
    required this.balance,
  });

  factory StatementLine.fromJson(Map<String, dynamic> json) => StatementLine(
    date: _date(json['date']),
    type: '${json['type'] ?? ''}',
    id: _i(json['id']),
    number: '${json['number'] ?? ''}',
    detail: _s(json['detail']),
    debit: _d(json['debit']),
    credit: _d(json['credit']),
    balance: _d(json['balance']),
  );

  final DateTime? date;

  /// 'invoice' | 'receipt' | 'credit_note'.
  final String type;
  final int id;
  final String number;
  final String? detail;
  final double debit, credit, balance;
}

/// What a customer owes, by age (the statement's and the aged report's
/// buckets).
class AgedBuckets {
  const AgedBuckets({this.current = 0, this.d1to30 = 0, this.d31to60 = 0, this.d61to90 = 0, this.d90plus = 0, this.total = 0});

  factory AgedBuckets.fromJson(Map<String, dynamic>? json) => json == null
      ? const AgedBuckets()
      : AgedBuckets(
          current: _d(json['current']),
          d1to30: _d(json['d1_30']),
          d31to60: _d(json['d31_60']),
          d61to90: _d(json['d61_90']),
          d90plus: _d(json['d90_plus']),
          total: _d(json['total']),
        );

  final double current, d1to30, d31to60, d61to90, d90plus, total;

  List<(String, double)> get buckets => [
    ('current', current),
    ('d1_30', d1to30),
    ('d31_60', d31to60),
    ('d61_90', d61to90),
    ('d90_plus', d90plus),
  ];

  double get overdue => d1to30 + d31to60 + d61to90 + d90plus;
}

class CustomerStatement {
  const CustomerStatement({
    required this.from,
    required this.to,
    required this.openingBalance,
    required this.lines,
    required this.totalDebit,
    required this.totalCredit,
    required this.closingBalance,
    required this.aged,
  });

  factory CustomerStatement.fromJson(Map<String, dynamic> json) => CustomerStatement(
    from: _date(json['from']),
    to: _date(json['to']),
    openingBalance: _d(json['opening_balance']),
    lines: _list(json['lines'], StatementLine.fromJson),
    totalDebit: _d(json['total_debit']),
    totalCredit: _d(json['total_credit']),
    closingBalance: _d(json['closing_balance']),
    aged: AgedBuckets.fromJson(_map(json['aged'])),
  );

  final DateTime? from, to;
  final double openingBalance, totalDebit, totalCredit, closingBalance;
  final List<StatementLine> lines;
  final AgedBuckets aged;
}

/* ───────────────────────────────────────────────────────────── lines ── */

/// One line of a quotation, order or invoice. An order line carries the
/// four quantities an order travels through; the others have one.
class SalesLine {
  const SalesLine({
    required this.id,
    required this.productId,
    required this.productName,
    this.sku,
    this.unitCode,
    this.description,
    required this.quantity,
    this.quantityApproved,
    this.quantityLoaded = 0,
    this.quantityReceived = 0,
    this.quantityInvoiced = 0,
    this.quantityCredited = 0,
    this.unitPrice = 0,
    this.discountPercent = 0,
    this.taxRate = 0,
    this.lineTotal = 0,
  });

  factory SalesLine.fromJson(Map<String, dynamic> json) {
    final product = _map(json['product']) ?? const {};
    return SalesLine(
      id: _i(json['id']),
      productId: _i(json['product_id']),
      productName: '${product['name'] ?? json['description'] ?? ''}',
      sku: _s(product['sku']),
      unitCode: _s(_map(product['unit'])?['code']),
      description: _s(json['description']),
      quantity: _d(json['quantity_ordered'] ?? json['quantity']),
      quantityApproved: _dn(json['quantity_approved']),
      quantityLoaded: _d(json['quantity_loaded']),
      quantityReceived: _d(json['quantity_received']),
      quantityInvoiced: _d(json['quantity_invoiced']),
      quantityCredited: _d(json['quantity_credited']),
      unitPrice: _d(json['unit_price']),
      discountPercent: _d(json['discount_percent']),
      taxRate: _d(json['tax_rate']),
      lineTotal: _d(json['line_total']),
    );
  }

  final int id, productId;
  final String productName;
  final String? sku, unitCode, description;

  /// Ordered on an order, the quantity on a quotation or invoice.
  final double quantity;
  final double? quantityApproved;
  final double quantityLoaded, quantityReceived, quantityInvoiced, quantityCredited;
  final double unitPrice, discountPercent, taxRate, lineTotal;
}

/// Subtotal, discount, VAT and total, as every sales document carries them.
class SalesTotals {
  const SalesTotals({this.subtotal = 0, this.discount = 0, this.tax = 0, this.total = 0});

  factory SalesTotals.fromJson(Map<String, dynamic> json) => SalesTotals(
    subtotal: _d(json['subtotal']),
    discount: _d(json['discount_total']),
    tax: _d(json['tax_total']),
    total: _d(json['total']),
  );

  final double subtotal, discount, tax, total;
}

/// The web's lineAmounts: what one line comes to, rounded to cents.
SalesTotals salesLineAmounts(double quantity, double price, double discountPercent, double taxRate) {
  double round(double n) => (n * 100).roundToDouble() / 100;
  final subtotal = round(quantity * price);
  final discount = round(subtotal * discountPercent / 100);
  final tax = round((subtotal - discount) * taxRate / 100);
  return SalesTotals(subtotal: subtotal, discount: discount, tax: tax, total: round(subtotal - discount + tax));
}

/* ──────────────────────────────────────────────────────── quotations ── */

class SalesQuotation {
  const SalesQuotation({
    required this.id,
    required this.number,
    required this.status,
    required this.totals,
    this.customer,
    this.quoteDate,
    this.validUntil,
    this.notes,
    this.order,
    this.creator,
    this.createdAt,
    this.lines = const [],
    this.linesCount = 0,
  });

  factory SalesQuotation.fromJson(Map<String, dynamic> json) {
    final lines = _list(json['lines'], SalesLine.fromJson);
    return SalesQuotation(
      id: _i(json['id']),
      number: '${json['number'] ?? ''}',
      status: '${json['status'] ?? SalesStatus.draft}',
      totals: SalesTotals.fromJson(json),
      customer: SalesCustomer.maybe(json['customer']),
      quoteDate: _date(json['quote_date']),
      validUntil: _date(json['valid_until']),
      notes: _s(json['notes']),
      order: SalesDocRef.fromJson(json['order']),
      creator: _name(json['creator']),
      createdAt: _time(json['created_at']),
      lines: lines,
      linesCount: _in(json['lines_count']) ?? lines.length,
    );
  }

  final int id;
  final String number, status;
  final SalesTotals totals;
  final SalesCustomer? customer;
  final DateTime? quoteDate, validUntil, createdAt;
  final String? notes, creator;
  final SalesDocRef? order;
  final List<SalesLine> lines;
  final int linesCount;

  bool get isExpired {
    final until = validUntil;
    if (until == null) return false;
    final now = DateTime.now();
    return until.isBefore(DateTime(now.year, now.month, now.day));
  }
}

/* ──────────────────────────────────────────────────────────── orders ── */

/// The credit policy check: run at approval (`policy_check`) or previewed
/// while an order waits (`policy_preview`).
class SalesPolicy {
  const SalesPolicy({
    required this.mode,
    required this.passed,
    this.creditLimit = 0,
    this.outstanding = 0,
    this.uninvoicedOrders = 0,
    this.thisOrder = 0,
    this.exposure = 0,
    this.overdueInvoices = 0,
    this.reasons = const [],
  });

  static SalesPolicy? fromJson(dynamic json) {
    final m = _map(json);
    if (m == null) return null;
    return SalesPolicy(
      mode: '${m['mode'] ?? 'credit'}',
      passed: m['passed'] != false,
      creditLimit: _d(m['credit_limit']),
      outstanding: _d(m['outstanding']),
      uninvoicedOrders: _d(m['uninvoiced_orders']),
      thisOrder: _d(m['this_order']),
      exposure: _d(m['exposure']),
      overdueInvoices: _i(m['overdue_invoices']),
      reasons: (m['reasons'] is List ? m['reasons'] as List : const []).map((e) => '$e').toList(),
    );
  }

  /// 'credit' | 'prepayment'.
  final String mode;
  final bool passed;
  final double creditLimit, outstanding, uninvoicedOrders, thisOrder, exposure;
  final int overdueInvoices;
  final List<String> reasons;
}

/// Stock on hand, held for open loadings, and what is left, for one
/// product in one warehouse.
class SalesAvailability {
  const SalesAvailability(this.onHand, this.reserved, this.available);

  final double onHand, reserved, available;
}

/// `{product_id: {warehouse_id: {on_hand, reserved, available}}}`.
Map<int, Map<int, SalesAvailability>> _availability(dynamic v) {
  final out = <int, Map<int, SalesAvailability>>{};
  final m = _map(v);
  if (m == null) return out;
  m.forEach((product, byWarehouse) {
    final inner = <int, SalesAvailability>{};
    _map(byWarehouse)?.forEach((warehouse, cell) {
      final c = _map(cell) ?? const {};
      inner[_i(warehouse)] = SalesAvailability(_d(c['on_hand']), _d(c['reserved']), _d(c['available']));
    });
    out[_i(product)] = inner;
  });
  return out;
}

class SalesOrder {
  const SalesOrder({
    required this.id,
    required this.number,
    required this.status,
    required this.totals,
    this.customer,
    this.paymentMode,
    this.orderDate,
    this.requiredDate,
    this.deliveryAddress,
    this.notes,
    this.policy,
    this.policyIsPreview = false,
    this.overrideReason,
    this.overrider,
    this.rejectionReason,
    this.creator,
    this.approver,
    this.createdAt,
    this.submittedAt,
    this.approvedAt,
    this.paymentVerifiedAt,
    this.warehouseId,
    this.warehouse,
    this.quotation,
    this.lines = const [],
    this.linesCount = 0,
    this.invoices = const [],
    this.loadingOrders = const [],
    this.verifiedPayments = 0,
    this.remainingToLoad = const {},
    this.availability = const {},
    this.warehouses = const [],
  });

  factory SalesOrder.fromJson(Map<String, dynamic> json) {
    final lines = _list(json['lines'], SalesLine.fromJson);
    final preview = SalesPolicy.fromJson(json['policy_preview']);
    final remaining = <int, double>{};
    _map(json['remaining_to_load'])?.forEach((k, v) => remaining[_i(k)] = _d(v));
    return SalesOrder(
      id: _i(json['id']),
      number: '${json['number'] ?? ''}',
      status: '${json['status'] ?? SalesStatus.draft}',
      totals: SalesTotals.fromJson(json),
      customer: SalesCustomer.maybe(json['customer']),
      paymentMode: _s(json['payment_mode']),
      orderDate: _date(json['order_date']),
      requiredDate: _date(json['required_date']),
      deliveryAddress: _s(json['delivery_address']),
      notes: _s(json['notes']),
      policy: preview ?? SalesPolicy.fromJson(json['policy_check']),
      policyIsPreview: preview != null,
      overrideReason: _s(json['override_reason']),
      overrider: _name(json['overrider']),
      rejectionReason: _s(json['rejection_reason']),
      creator: _name(json['creator']),
      approver: _name(json['approver']),
      createdAt: _time(json['created_at']),
      submittedAt: _time(json['submitted_at']),
      approvedAt: _time(json['approved_at']),
      paymentVerifiedAt: _time(json['payment_verified_at']),
      warehouseId: _in(json['warehouse_id']),
      warehouse: ErpRef.fromJson(json['warehouse']),
      quotation: SalesDocRef.fromJson(json['quotation']),
      lines: lines,
      linesCount: _in(json['lines_count']) ?? lines.length,
      invoices: _list(json['invoices'], SalesInvoice.fromJson),
      loadingOrders: _list(json['loading_orders'], LoadingOrder.fromJson),
      verifiedPayments: _d(json['verified_payments']),
      remainingToLoad: remaining,
      availability: _availability(json['availability']),
      warehouses: [for (final w in (json['warehouses'] is List ? json['warehouses'] as List : const [])) ?ErpRef.fromJson(w)],
    );
  }

  final int id;
  final String number, status;
  final SalesTotals totals;
  final SalesCustomer? customer;
  final String? paymentMode, deliveryAddress, notes, overrideReason, overrider, rejectionReason, creator, approver;
  final DateTime? orderDate, requiredDate, createdAt, submittedAt, approvedAt, paymentVerifiedAt;
  final SalesPolicy? policy;
  final bool policyIsPreview;
  final int? warehouseId;
  final ErpRef? warehouse;
  final SalesDocRef? quotation;
  final List<SalesLine> lines;
  final int linesCount;
  final List<SalesInvoice> invoices;
  final List<LoadingOrder> loadingOrders;
  final double verifiedPayments;

  /// Order line id to what may still be loaded.
  final Map<int, double> remainingToLoad;
  final Map<int, Map<int, SalesAvailability>> availability;
  final List<ErpRef> warehouses;

  double get leftToLoad => remainingToLoad.values.fold(0, (s, v) => s + v);

  /// Prepayment when the API set it, or when the customer must prepay.
  bool get isPrepayment =>
      paymentMode == null ? (customer?.requiresPrepayment ?? false) : paymentMode == 'prepayment';
}

/* ────────────────────────────────────────────────────────── invoices ── */

class SalesAllocation {
  const SalesAllocation({required this.id, required this.amount, this.receipt, this.invoice, this.date, this.method});

  factory SalesAllocation.fromJson(Map<String, dynamic> json) {
    final receipt = _map(json['receipt']);
    return SalesAllocation(
      id: _i(json['id']),
      amount: _d(json['amount']),
      receipt: SalesDocRef.fromJson(receipt),
      invoice: SalesDocRef.fromJson(json['invoice']),
      date: _date(receipt?['receipt_date']),
      method: _s(receipt?['method']),
    );
  }

  final int id;
  final double amount;
  final SalesDocRef? receipt, invoice;
  final DateTime? date;
  final String? method;
}

class SalesCreditNoteRef {
  const SalesCreditNoteRef(this.id, this.number, this.status, this.total, this.date);

  factory SalesCreditNoteRef.fromJson(Map<String, dynamic> json) => SalesCreditNoteRef(
    _i(json['id']),
    '${json['number'] ?? ''}',
    '${json['status'] ?? ''}',
    _d(json['total']),
    _date(json['credit_date']),
  );

  final int id;
  final String number, status;
  final double total;
  final DateTime? date;
}

class SalesInvoice {
  const SalesInvoice({
    required this.id,
    required this.number,
    required this.status,
    required this.totals,
    this.customer,
    this.customerId = 0,
    this.salesOrderId,
    this.loadingOrderId,
    this.order,
    this.loadingOrder,
    this.deliveryNoteNumber,
    this.invoiceDate,
    this.dueDate,
    this.amountPaid = 0,
    this.amountCredited = 0,
    this.balance = 0,
    this.notes,
    this.creator,
    this.poster,
    this.postedAt,
    this.createdAt,
    this.lines = const [],
    this.allocations = const [],
    this.creditNotes = const [],
  });

  factory SalesInvoice.fromJson(Map<String, dynamic> json) {
    final totals = SalesTotals.fromJson(json);
    final paid = _d(json['amount_paid']);
    final credited = _d(json['amount_credited']);
    final loading = _map(json['loading_order']);
    return SalesInvoice(
      id: _i(json['id']),
      number: '${json['number'] ?? ''}',
      status: '${json['status'] ?? SalesStatus.draft}',
      totals: totals,
      customer: SalesCustomer.maybe(json['customer']),
      customerId: _i(json['customer_id']),
      salesOrderId: _in(json['sales_order_id']),
      loadingOrderId: _in(json['loading_order_id']),
      order: SalesDocRef.fromJson(json['order']),
      loadingOrder: SalesDocRef.fromJson(loading),
      deliveryNoteNumber: _s(loading?['delivery_note_number']),
      invoiceDate: _date(json['invoice_date']),
      dueDate: _date(json['due_date']),
      amountPaid: paid,
      amountCredited: credited,
      balance: json.containsKey('balance') ? _d(json['balance']) : totals.total - paid - credited,
      notes: _s(json['notes']),
      creator: _name(json['creator']),
      poster: _name(json['poster']),
      postedAt: _time(json['posted_at']),
      createdAt: _time(json['created_at']),
      lines: _list(json['lines'], SalesLine.fromJson),
      allocations: _list(json['allocations'], SalesAllocation.fromJson),
      creditNotes: _list(json['credit_notes'], SalesCreditNoteRef.fromJson),
    );
  }

  final int id;
  final String number, status;
  final SalesTotals totals;
  final SalesCustomer? customer;
  final int customerId;
  final int? salesOrderId, loadingOrderId;
  final SalesDocRef? order, loadingOrder;
  final String? deliveryNoteNumber, notes, creator, poster;
  final DateTime? invoiceDate, dueDate, postedAt, createdAt;
  final double amountPaid, amountCredited, balance;
  final List<SalesLine> lines;
  final List<SalesAllocation> allocations;
  final List<SalesCreditNoteRef> creditNotes;

  bool get isOpen => status == SalesStatus.posted && balance > 0.004;

  bool get isOverdue {
    final due = dueDate;
    if (!isOpen || due == null) return false;
    final now = DateTime.now();
    return due.isBefore(DateTime(now.year, now.month, now.day));
  }
}

/* ────────────────────────────────────────────────────────── receipts ── */

class SalesReceipt {
  const SalesReceipt({
    required this.id,
    required this.number,
    required this.status,
    required this.amount,
    required this.method,
    this.customer,
    this.receiptDate,
    this.reference,
    this.notes,
    this.account,
    this.creator,
    this.createdBy,
    this.verifier,
    this.verifiedAt,
    this.rejectionReason,
    this.createdAt,
    this.allocations = const [],
  });

  factory SalesReceipt.fromJson(Map<String, dynamic> json) => SalesReceipt(
    id: _i(json['id']),
    number: '${json['number'] ?? ''}',
    status: '${json['status'] ?? SalesStatus.recorded}',
    amount: _d(json['amount']),
    method: '${json['method'] ?? 'cash'}',
    customer: SalesCustomer.maybe(json['customer']),
    receiptDate: _date(json['receipt_date']),
    reference: _s(json['reference']),
    notes: _s(json['notes']),
    account: ErpRef.fromJson(json['account']),
    creator: _name(json['creator']),
    createdBy: _in(json['created_by']),
    verifier: _name(json['verifier']),
    verifiedAt: _time(json['verified_at']),
    rejectionReason: _s(json['rejection_reason']),
    createdAt: _time(json['created_at']),
    allocations: _list(json['allocations'], SalesAllocation.fromJson),
  );

  final int id;
  final String number, status, method;
  final double amount;
  final SalesCustomer? customer;
  final DateTime? receiptDate, verifiedAt, createdAt;
  final String? reference, notes, creator, verifier, rejectionReason;
  final int? createdBy;
  final ErpRef? account;
  final List<SalesAllocation> allocations;
}

/* ─────────────────────────────────────────────────────────── dispatch ── */

class LoadingLine {
  const LoadingLine({
    required this.id,
    required this.productId,
    required this.productName,
    this.sku,
    this.unitCode,
    this.ordered = 0,
    this.approved = 0,
    this.loaded,
    this.received,
  });

  factory LoadingLine.fromJson(Map<String, dynamic> json) {
    final product = _map(json['product']) ?? const {};
    return LoadingLine(
      id: _i(json['id']),
      productId: _i(json['product_id']),
      productName: '${product['name'] ?? ''}',
      sku: _s(product['sku']),
      unitCode: _s(_map(product['unit'])?['code']),
      ordered: _d(json['quantity_ordered']),
      approved: _d(json['quantity_approved']),
      loaded: _dn(json['quantity_loaded']),
      received: _dn(json['quantity_received']),
    );
  }

  final int id, productId;
  final String productName;
  final String? sku, unitCode;
  final double ordered, approved;

  /// Null until the warehouse enters what went on the truck.
  final double? loaded;

  /// Null until proof of delivery.
  final double? received;

  bool get short => received != null && received! < (loaded ?? 0) - 0.00001;
}

/// One truck, one warehouse, one order: a loading order and every step
/// from the bay to the customer's signature.
class LoadingOrder {
  const LoadingOrder({
    required this.id,
    required this.number,
    required this.status,
    this.salesOrderId,
    this.warehouseId,
    this.plannedDate,
    this.vehicleNumber,
    this.driverName,
    this.destination,
    this.notes,
    this.customer,
    this.order,
    this.orderPaymentMode,
    this.warehouse,
    this.deliveryNoteNumber,
    this.gatePassNumber,
    this.createdAt,
    this.creator,
    this.loadedAt,
    this.loader,
    this.driverConfirmedAt,
    this.driverConfirmedName,
    this.securityConfirmedAt,
    this.securityConfirmedName,
    this.deliveryNoteIssuedAt,
    this.gatePassIssuedAt,
    this.gatePassIssuer,
    this.receivedByName,
    this.receivedDate,
    this.deliveryRemark,
    this.podRecordedAt,
    this.podRecorder,
    this.discrepancyStatus,
    this.discrepancyNote,
    this.discrepancyResolvedAt,
    this.resolver,
    this.stockDocument,
    this.returnDocument,
    this.lines = const [],
    this.linesCount = 0,
    this.availability = const {},
  });

  factory LoadingOrder.fromJson(Map<String, dynamic> json) {
    final lines = _list(json['lines'], LoadingLine.fromJson);
    final order = _map(json['order']);
    return LoadingOrder(
      id: _i(json['id']),
      number: '${json['number'] ?? ''}',
      status: '${json['status'] ?? SalesStatus.open}',
      salesOrderId: _in(json['sales_order_id']),
      warehouseId: _in(json['warehouse_id']),
      plannedDate: _date(json['planned_date']),
      vehicleNumber: _s(json['vehicle_number']),
      driverName: _s(json['driver_name']),
      destination: _s(json['destination']),
      notes: _s(json['notes']),
      customer: SalesCustomer.maybe(json['customer']),
      order: SalesDocRef.fromJson(order),
      orderPaymentMode: _s(order?['payment_mode']),
      warehouse: ErpRef.fromJson(json['warehouse']),
      deliveryNoteNumber: _s(json['delivery_note_number']),
      gatePassNumber: _s(json['gate_pass_number']),
      createdAt: _time(json['created_at']),
      creator: _name(json['creator']),
      loadedAt: _time(json['loaded_at']),
      loader: _name(json['loader']),
      driverConfirmedAt: _time(json['driver_confirmed_at']),
      driverConfirmedName: _s(json['driver_confirmed_name']),
      securityConfirmedAt: _time(json['security_confirmed_at']),
      securityConfirmedName: _s(json['security_confirmed_name']),
      deliveryNoteIssuedAt: _time(json['delivery_note_issued_at']),
      gatePassIssuedAt: _time(json['gate_pass_issued_at']),
      gatePassIssuer: _name(json['gate_pass_issuer']),
      receivedByName: _s(json['received_by_name']),
      receivedDate: _date(json['received_date']),
      deliveryRemark: _s(json['delivery_remark']),
      podRecordedAt: _time(json['pod_recorded_at']),
      podRecorder: _name(json['pod_recorder']),
      discrepancyStatus: _s(json['discrepancy_status']),
      discrepancyNote: _s(json['discrepancy_note']),
      discrepancyResolvedAt: _time(json['discrepancy_resolved_at']),
      resolver: _name(json['resolver']),
      stockDocument: SalesDocRef.fromJson(json['stock_document']),
      returnDocument: SalesDocRef.fromJson(json['return_document']),
      lines: lines,
      linesCount: _in(json['lines_count']) ?? lines.length,
      availability: _availability(json['availability']),
    );
  }

  final int id;
  final String number, status;
  final int? salesOrderId, warehouseId;
  final DateTime? plannedDate;
  final String? vehicleNumber, driverName, destination, notes;
  final SalesCustomer? customer;
  final SalesDocRef? order;
  final String? orderPaymentMode;
  final ErpRef? warehouse;
  final String? deliveryNoteNumber, gatePassNumber;
  final DateTime? createdAt, loadedAt, driverConfirmedAt, securityConfirmedAt, deliveryNoteIssuedAt, gatePassIssuedAt;
  final String? creator, loader, driverConfirmedName, securityConfirmedName, gatePassIssuer;
  final String? receivedByName, deliveryRemark, podRecorder;
  final DateTime? receivedDate, podRecordedAt, discrepancyResolvedAt;

  /// null | 'open' | 'returned' | 'written_off'.
  final String? discrepancyStatus;
  final String? discrepancyNote, resolver;
  final SalesDocRef? stockDocument, returnDocument;
  final List<LoadingLine> lines;
  final int linesCount;
  final Map<int, Map<int, SalesAvailability>> availability;

  bool get isOpen => status == SalesStatus.open;
  bool get isLoaded => status == SalesStatus.loaded;
  bool get onTheRoad => status == SalesStatus.dispatched;
  bool get isDelivered => status == SalesStatus.delivered;
  bool get allEntered => lines.every((l) => l.loaded != null);
  bool get shortDelivered => lines.any((l) => l.short);
  bool get discrepancyOpen => discrepancyStatus == 'open';
}

/// What finance must look at before goods may leave (GET
/// /erp/dispatch/verification).
class VerificationQueue {
  const VerificationQueue({required this.receipts, required this.awaitingPayment, required this.ready});

  factory VerificationQueue.fromJson(Map<String, dynamic> json) => VerificationQueue(
    receipts: _list(json['receipts'], SalesReceipt.fromJson),
    awaitingPayment: _list(json['awaiting_payment'], SalesOrder.fromJson),
    ready: _list(json['ready'], SalesOrder.fromJson),
  );

  final List<SalesReceipt> receipts;
  final List<SalesOrder> awaitingPayment, ready;
}

/* ─────────────────────────────────────────────────────────── overview ── */

class SalesOverview {
  const SalesOverview({
    required this.salesThisMonth,
    required this.invoicedThisMonth,
    required this.receivedThisMonth,
    required this.receivables,
    required this.overdue,
    required this.openQuotations,
    required this.awaitingVerification,
    required this.awaitingPayment,
    required this.openDiscrepancies,
    required this.pipeline,
    required this.recentOrders,
  });

  factory SalesOverview.fromJson(Map<String, dynamic> json) {
    final pipeline = <String, (int, double)>{};
    _map(json['pipeline'])?.forEach((k, v) {
      final m = _map(v) ?? const {};
      pipeline[k] = (_i(m['count']), _d(m['value']));
    });
    return SalesOverview(
      salesThisMonth: _d(json['sales_this_month']),
      invoicedThisMonth: _d(json['invoiced_this_month']),
      receivedThisMonth: _d(json['received_this_month']),
      receivables: _d(json['receivables']),
      overdue: _d(json['overdue']),
      openQuotations: _i(json['open_quotations']),
      awaitingVerification: _i(json['awaiting_verification']),
      awaitingPayment: _i(json['awaiting_payment']),
      openDiscrepancies: _i(json['open_discrepancies']),
      pipeline: pipeline,
      recentOrders: _list(json['recent_orders'], SalesOrder.fromJson),
    );
  }

  final double salesThisMonth, invoicedThisMonth, receivedThisMonth, receivables, overdue;
  final int openQuotations, awaitingVerification, awaitingPayment, openDiscrepancies;

  /// Status to (orders, value).
  final Map<String, (int, double)> pipeline;
  final List<SalesOrder> recentOrders;

  int count(String status) => pipeline[status]?.$1 ?? 0;
}

/* ──────────────────────────────────────────────────────────── lookups ── */

class SalesProduct {
  const SalesProduct({
    required this.id,
    required this.sku,
    required this.name,
    this.type = 'finished_good',
    this.salePrice = 0,
    this.unitCode = '',
    this.allowsDecimals = false,
  });

  factory SalesProduct.fromJson(Map<String, dynamic> json) {
    final unit = _map(json['unit']) ?? const {};
    return SalesProduct(
      id: _i(json['id']),
      sku: '${json['sku'] ?? ''}',
      name: '${json['name'] ?? ''}',
      type: '${json['type'] ?? 'finished_good'}',
      salePrice: _d(json['sale_price']),
      unitCode: '${unit['code'] ?? ''}',
      allowsDecimals: unit['allows_decimals'] == true,
    );
  }

  final int id;
  final String sku, name, type, unitCode;
  final double salePrice;
  final bool allowsDecimals;
}

/// Everything a sales form needs for its pickers (GET /erp/sales/lookups).
class SalesLookups {
  const SalesLookups({
    required this.customers,
    required this.products,
    required this.warehouses,
    required this.cashAccounts,
    required this.taxRate,
  });

  factory SalesLookups.fromJson(Map<String, dynamic> json) => SalesLookups(
    customers: _list(json['customers'], SalesCustomer.fromJson),
    products: _list(json['products'], SalesProduct.fromJson),
    warehouses: [for (final w in (json['warehouses'] is List ? json['warehouses'] as List : const [])) ?ErpRef.fromJson(w)],
    cashAccounts: [for (final a in (json['cash_accounts'] is List ? json['cash_accounts'] as List : const [])) ?ErpRef.fromJson(a)],
    taxRate: _d(json['tax_rate']),
  );

  final List<SalesCustomer> customers;
  final List<SalesProduct> products;
  final List<ErpRef> warehouses, cashAccounts;
  final double taxRate;
}

/// Orders the warehouse may load (GET /erp/dispatch/lookups).
class DispatchLookups {
  const DispatchLookups({required this.warehouses, required this.readyOrders});

  factory DispatchLookups.fromJson(Map<String, dynamic> json) => DispatchLookups(
    warehouses: [for (final w in (json['warehouses'] is List ? json['warehouses'] as List : const [])) ?ErpRef.fromJson(w)],
    readyOrders: _list(json['ready_orders'], SalesOrder.fromJson),
  );

  final List<ErpRef> warehouses;
  final List<SalesOrder> readyOrders;
}

/* ──────────────────────────────────────────────────────────── drafts ── */

/// One line being typed into the order form.
class SalesLineDraft {
  SalesLineDraft({required this.product, this.quantity = '', this.unitPrice = '', this.discount = ''});

  final SalesProduct product;
  String quantity, unitPrice, discount;

  double get quantityValue => double.tryParse(quantity.trim()) ?? 0;
  double get priceValue => double.tryParse(unitPrice.trim()) ?? 0;
  double get discountValue => double.tryParse(discount.trim()) ?? 0;
}

/// A sales order or a quotation being prepared on the phone. Saving leaves a
/// draft; an order is submitted for approval from its page.
class SalesDocumentDraft {
  SalesDocumentDraft({this.quotation = false, DateTime? date}) : date = date ?? DateTime.now();

  final bool quotation;
  int? customerId;
  DateTime date;

  /// The required date on an order, valid until on a quotation.
  DateTime? untilDate;
  int? warehouseId;
  String deliveryAddress = '';
  String notes = '';
  final lines = <SalesLineDraft>[];

  SalesTotals totals(double taxRate) {
    var subtotal = 0.0, discount = 0.0, tax = 0.0, total = 0.0;
    for (final l in lines) {
      final a = salesLineAmounts(l.quantityValue, l.priceValue, l.discountValue, taxRate);
      subtotal += a.subtotal;
      discount += a.discount;
      tax += a.tax;
      total += a.total;
    }
    return SalesTotals(subtotal: subtotal, discount: discount, tax: tax, total: total);
  }

  Map<String, dynamic> toJson() => {
    'customer_id': customerId,
    if (quotation) ...{
      'quote_date': salesIsoDate(date),
      'valid_until': untilDate == null ? null : salesIsoDate(untilDate!),
    } else ...{
      'order_date': salesIsoDate(date),
      'required_date': untilDate == null ? null : salesIsoDate(untilDate!),
      'warehouse_id': warehouseId,
      'delivery_address': deliveryAddress.trim().isEmpty ? null : deliveryAddress.trim(),
    },
    'notes': notes.trim().isEmpty ? null : notes.trim(),
    'lines': [
      for (final l in lines)
        {
          'product_id': l.product.id,
          'quantity': l.quantityValue,
          if (l.unitPrice.trim().isNotEmpty) 'unit_price': l.priceValue,
          if (l.discount.trim().isNotEmpty) 'discount_percent': l.discountValue,
        },
    ],
  };
}
