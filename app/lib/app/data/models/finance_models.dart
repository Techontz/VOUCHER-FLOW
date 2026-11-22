import 'erp_models.dart';

/*
 * The shapes the Procurement, Finance and Assets endpoints return (backend
 * routes/erp/procurement.php, finance.php, integration.php and the core
 * accounting routes), as the web's lib/procurement-api.ts and lib/finance.ts
 * type them. Decimals arrive as strings ("5700000.00"); every reader here
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

Map<String, dynamic> _m(dynamic v) => _map(v) ?? const {};

List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) read) =>
    (v is List ? v : const []).whereType<Map>().map((e) => read(Map<String, dynamic>.from(e))).toList();

ErpRef? _ref(dynamic v) => ErpRef.fromJson(v);

/// A document reference `{id, number}`, the number read into [ErpRef.name].
ErpRef? _numbered(dynamic v) {
  final m = _map(v);
  return m == null ? null : ErpRef(_i(m['id']), '${m['number'] ?? ''}');
}

/// "1220 · CRDB Bank: collections".
String accountLabel(ErpRef? a) => a == null ? '' : [?a.code, a.name].join(' · ');

/* ═════════════════════════════════════════════════════════ procurement ══ */

/// GET /erp/procurement/overview.
class ProcurementOverview {
  const ProcurementOverview({
    required this.openRequisitions,
    required this.requisitionsAwaiting,
    required this.ordersAwaiting,
    required this.ordersToReceive,
    required this.invoicesToMatch,
    required this.invoicesWithVariance,
    required this.payablesOutstanding,
    required this.payablesOverdue,
    required this.payablesDue7Days,
    required this.orderedThisMonth,
    required this.recentOrders,
  });

  factory ProcurementOverview.fromJson(Map<String, dynamic> j) => ProcurementOverview(
    openRequisitions: _i(j['open_requisitions']),
    requisitionsAwaiting: _i(j['requisitions_awaiting_approval']),
    ordersAwaiting: _i(j['orders_awaiting_approval']),
    ordersToReceive: _i(j['orders_to_receive']),
    invoicesToMatch: _i(j['invoices_to_match']),
    invoicesWithVariance: _i(j['invoices_with_variance']),
    payablesOutstanding: _d(j['payables_outstanding']),
    payablesOverdue: _d(j['payables_overdue']),
    payablesDue7Days: _d(j['payables_due_7_days']),
    orderedThisMonth: _d(j['ordered_this_month']),
    recentOrders: _list(j['recent_orders'], PurchaseOrder.fromJson),
  );

  final int openRequisitions, requisitionsAwaiting, ordersAwaiting, ordersToReceive;
  final int invoicesToMatch, invoicesWithVariance;
  final double payablesOutstanding, payablesOverdue, payablesDue7Days, orderedThisMonth;
  final List<PurchaseOrder> recentOrders;
}

class Supplier {
  const Supplier({
    required this.id,
    required this.code,
    required this.name,
    this.category,
    this.contactPerson,
    this.phone,
    this.email,
    this.tin,
    this.address,
    this.city,
    this.paymentTermsDays,
    this.bankName,
    this.bankAccountName,
    this.bankAccountNumber,
    this.isActive = true,
  });

  factory Supplier.fromJson(Map<String, dynamic> j) => Supplier(
    id: _i(j['id']),
    code: '${j['code'] ?? ''}',
    name: '${j['name'] ?? ''}',
    category: _s(j['category']),
    contactPerson: _s(j['contact_person']),
    phone: _s(j['phone']),
    email: _s(j['email']),
    tin: _s(j['tin']),
    address: _s(j['address']),
    city: _s(j['city']),
    paymentTermsDays: _in(j['payment_terms_days']),
    bankName: _s(j['bank_name']),
    bankAccountName: _s(j['bank_account_name']),
    bankAccountNumber: _s(j['bank_account_number']),
    isActive: j['is_active'] != false,
  );

  final int id;
  final String code, name;
  final String? category, contactPerson, phone, email, tin, address, city;
  final int? paymentTermsDays;
  final String? bankName, bankAccountName, bankAccountNumber;
  final bool isActive;
}

/// One decision on a requisition, an order or an invoice variance.
class ProcApproval {
  const ProcApproval({required this.level, required this.decision, this.user, this.comment, this.at});

  factory ProcApproval.fromJson(Map<String, dynamic> j) => ProcApproval(
    level: _i(j['level']),
    decision: '${j['decision'] ?? ''}',
    user: _ref(j['user']),
    comment: _s(j['comment']),
    at: _time(j['created_at']),
  );

  final int level;
  final String decision;
  final ErpRef? user;
  final String? comment;
  final DateTime? at;
}

/// A line of a requisition, an order or an invoice: what, how many, at what.
class ProcLine {
  const ProcLine({
    required this.id,
    required this.lineType,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.amount,
    this.vatAmount = 0,
    this.unitCode,
    this.sku,
    this.receivedQuantity,
    this.orderedQuantity,
    this.orderUnitPrice,
    this.priceVariance = 0,
    this.quantityVariance = 0,
    this.flagged = false,
    this.expenseAccount,
  });

  factory ProcLine.fromJson(Map<String, dynamic> j) {
    final product = _m(j['product']);
    final orderLine = _map(j['order_line']);
    return ProcLine(
      id: _i(j['id']),
      lineType: '${j['line_type'] ?? 'stock'}',
      description: _s(j['description']) ?? '${product['name'] ?? ''}',
      quantity: _d(j['quantity']),
      unitPrice: _d(j['unit_price'] ?? j['estimated_unit_price']),
      amount: _d(j['amount']),
      vatAmount: _d(j['vat_amount']),
      unitCode: _s(_m(product['unit'])['code']),
      sku: _s(product['sku']),
      receivedQuantity: _dn(j['received_quantity']),
      orderedQuantity: orderLine == null ? null : _d(orderLine['quantity']),
      orderUnitPrice: _dn(j['order_unit_price']),
      priceVariance: _d(j['price_variance']),
      quantityVariance: _d(j['quantity_variance']),
      flagged: j['flagged'] == true,
      expenseAccount: _ref(j['expense_account']),
    );
  }

  final int id;
  final String lineType, description;
  final double quantity, unitPrice, amount, vatAmount;
  final String? unitCode, sku;
  final double? receivedQuantity, orderedQuantity, orderUnitPrice;
  final double priceVariance, quantityVariance;
  final bool flagged;
  final ErpRef? expenseAccount;
}

class PurchaseRequisition {
  const PurchaseRequisition({
    required this.id,
    required this.number,
    required this.status,
    required this.total,
    required this.justification,
    this.requestedBy,
    this.requester,
    this.department,
    this.neededBy,
    this.approvalsRequired = 1,
    this.linesCount = 0,
    this.createdAt,
    this.submittedAt,
    this.lines = const [],
    this.approvals = const [],
    this.orders = const [],
  });

  factory PurchaseRequisition.fromJson(Map<String, dynamic> j) => PurchaseRequisition(
    id: _i(j['id']),
    number: '${j['number'] ?? ''}',
    status: '${j['status'] ?? 'draft'}',
    total: _d(j['total']),
    justification: '${j['justification'] ?? ''}',
    requestedBy: _in(j['requested_by']),
    requester: _ref(j['requester']),
    department: _ref(j['department']),
    neededBy: _date(j['needed_by']),
    approvalsRequired: _in(j['approvals_required']) ?? 1,
    linesCount: _in(j['lines_count']) ?? (j['lines'] is List ? (j['lines'] as List).length : 0),
    createdAt: _time(j['created_at']),
    submittedAt: _time(j['submitted_at']),
    lines: _list(j['lines'], ProcLine.fromJson),
    approvals: _list(j['approvals'], ProcApproval.fromJson),
    orders: _list(j['orders'], (o) => ErpRef(_i(o['id']), '${o['number'] ?? ''}')),
  );

  final int id;
  final String number, status, justification;
  final double total;
  final int? requestedBy;
  final ErpRef? requester, department;
  final DateTime? neededBy, createdAt, submittedAt;
  final int approvalsRequired, linesCount;
  final List<ProcLine> lines;
  final List<ProcApproval> approvals;
  final List<ErpRef> orders;
}

class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    required this.number,
    required this.status,
    required this.total,
    this.subtotal = 0,
    this.vatAmount = 0,
    this.supplier,
    this.warehouse,
    this.requisition,
    this.creator,
    this.createdBy,
    this.orderDate,
    this.expectedDate,
    this.paymentTerms,
    this.notes,
    this.cancelReason,
    this.approvalsRequired = 1,
    this.linesCount = 0,
    this.orderedQuantity = 0,
    this.receivedQuantity = 0,
    this.lines = const [],
    this.approvals = const [],
    this.invoices = const [],
  });

  factory PurchaseOrder.fromJson(Map<String, dynamic> j) => PurchaseOrder(
    id: _i(j['id']),
    number: '${j['number'] ?? ''}',
    status: '${j['status'] ?? 'draft'}',
    total: _d(j['total']),
    subtotal: _d(j['subtotal']),
    vatAmount: _d(j['vat_amount']),
    supplier: _ref(j['supplier']),
    warehouse: _ref(j['warehouse']),
    requisition: _numbered(j['requisition']),
    creator: _ref(j['creator']),
    createdBy: _in(j['created_by']),
    orderDate: _date(j['order_date']),
    expectedDate: _date(j['expected_date']),
    paymentTerms: _s(j['payment_terms']),
    notes: _s(j['notes']),
    cancelReason: _s(j['cancel_reason']),
    approvalsRequired: _in(j['approvals_required']) ?? 1,
    linesCount: _in(j['lines_count']) ?? 0,
    orderedQuantity: _d(j['ordered_quantity']),
    receivedQuantity: _d(j['received_quantity']),
    lines: _list(j['lines'], ProcLine.fromJson),
    approvals: _list(j['approvals'], ProcApproval.fromJson),
    invoices: _list(j['invoices'], (i) => ErpRef(_i(i['id']), '${i['number'] ?? ''}')),
  );

  final int id;
  final String number, status;
  final double total, subtotal, vatAmount;
  final ErpRef? supplier, warehouse, requisition, creator;
  final int? createdBy;
  final DateTime? orderDate, expectedDate;
  final String? paymentTerms, notes, cancelReason;
  final int approvalsRequired, linesCount;
  final double orderedQuantity, receivedQuantity;
  final List<ProcLine> lines;
  final List<ProcApproval> approvals;
  final List<ErpRef> invoices;

  /// Received so far, 0 to 1, for an order still being delivered.
  double get receivedShare => orderedQuantity <= 0 ? 0 : (receivedQuantity / orderedQuantity).clamp(0, 1);
}

/// A payment applied to an invoice, seen from either side.
class ProcAllocation {
  const ProcAllocation({required this.amount, this.payment, this.invoice});

  factory ProcAllocation.fromJson(Map<String, dynamic> j) {
    final p = _map(j['payment']);
    final i = _map(j['invoice']);
    return ProcAllocation(
      amount: _d(j['amount']),
      payment: p == null ? null : SupplierPayment.fromJson(p),
      invoice: i == null ? null : SupplierInvoice.fromJson(i),
    );
  }

  final double amount;
  final SupplierPayment? payment;
  final SupplierInvoice? invoice;
}

class SupplierInvoice {
  const SupplierInvoice({
    required this.id,
    required this.number,
    required this.status,
    required this.total,
    this.supplierId,
    this.supplierInvoiceNumber,
    this.matchStatus,
    this.paymentStatus,
    this.subtotal = 0,
    this.vatAmount = 0,
    this.amountPaid = 0,
    this.outstanding = 0,
    this.supplier,
    this.order,
    this.creator,
    this.createdBy,
    this.poster,
    this.varianceApprover,
    this.journal,
    this.invoiceDate,
    this.dueDate,
    this.createdAt,
    this.postedAt,
    this.notes,
    this.lines = const [],
    this.allocations = const [],
    this.approvals = const [],
  });

  factory SupplierInvoice.fromJson(Map<String, dynamic> j) => SupplierInvoice(
    id: _i(j['id']),
    number: '${j['number'] ?? ''}',
    status: '${j['status'] ?? 'draft'}',
    total: _d(j['total']),
    supplierId: _in(j['supplier_id']),
    supplierInvoiceNumber: _s(j['supplier_invoice_number']),
    matchStatus: _s(j['match_status']),
    paymentStatus: _s(j['payment_status']),
    subtotal: _d(j['subtotal']),
    vatAmount: _d(j['vat_amount']),
    amountPaid: _d(j['amount_paid']),
    outstanding: _d(j['outstanding']),
    supplier: _ref(j['supplier']),
    order: _numbered(j['order']),
    creator: _ref(j['creator']),
    createdBy: _in(j['created_by']),
    poster: _ref(j['poster']),
    varianceApprover: _ref(j['variance_approver']),
    journal: _numbered(j['journal']),
    invoiceDate: _date(j['invoice_date']),
    dueDate: _date(j['due_date']),
    createdAt: _time(j['created_at']),
    postedAt: _time(j['posted_at']),
    notes: _s(j['notes']),
    lines: _list(j['lines'], ProcLine.fromJson),
    allocations: _list(j['allocations'], ProcAllocation.fromJson),
    approvals: _list(j['approvals'], ProcApproval.fromJson),
  );

  final int id;
  final String number, status;
  final double total, subtotal, vatAmount, amountPaid, outstanding;
  final int? supplierId, createdBy;
  final String? supplierInvoiceNumber, matchStatus, paymentStatus, notes;
  final ErpRef? supplier, order, creator, poster, varianceApprover, journal;
  final DateTime? invoiceDate, dueDate, createdAt, postedAt;
  final List<ProcLine> lines;
  final List<ProcAllocation> allocations;
  final List<ProcApproval> approvals;

  bool get isPosted => status == 'posted';

  /// Past its due date with money still owed.
  bool get isOverdue =>
      isPosted && outstanding > 0 && dueDate != null && dueDate!.isBefore(DateTime.now().subtract(const Duration(days: 1)));

  double get priceVariance => lines.fold(0, (s, l) => s + l.priceVariance);
}

class SupplierPayment {
  const SupplierPayment({
    required this.id,
    required this.number,
    required this.status,
    required this.amount,
    this.method,
    this.reference,
    this.paymentDate,
    this.supplier,
    this.account,
    this.creator,
    this.poster,
    this.journal,
    this.postedAt,
    this.notes,
    this.allocationsCount = 0,
    this.allocations = const [],
  });

  factory SupplierPayment.fromJson(Map<String, dynamic> j) => SupplierPayment(
    id: _i(j['id']),
    number: '${j['number'] ?? ''}',
    status: '${j['status'] ?? 'draft'}',
    amount: _d(j['amount']),
    method: _s(j['method']),
    reference: _s(j['reference']),
    paymentDate: _date(j['payment_date']),
    supplier: _ref(j['supplier']),
    account: _ref(j['account']),
    creator: _ref(j['creator']),
    poster: _ref(j['poster']),
    journal: _numbered(j['journal']),
    postedAt: _time(j['posted_at']),
    notes: _s(j['notes']),
    allocationsCount: _in(j['allocations_count']) ?? 0,
    allocations: _list(j['allocations'], ProcAllocation.fromJson),
  );

  final int id;
  final String number, status;
  final double amount;
  final String? method, reference, notes;
  final DateTime? paymentDate, postedAt;
  final ErpRef? supplier, account, creator, poster, journal;
  final int allocationsCount;
  final List<ProcAllocation> allocations;
}

/// The payment voucher raised in VouchFlow for a supplier invoice.
class VoucherLink {
  const VoucherLink({required this.id, required this.number, this.status});

  static VoucherLink? fromJson(dynamic json) {
    final m = _map(json);
    if (m == null) return null;
    return VoucherLink(id: _i(m['id']), number: '${m['number'] ?? ''}', status: _s(m['status']));
  }

  final int id;
  final String number;
  final String? status;
}

/// One line of a supplier statement: an invoice (credit) or a payment
/// (debit), with the running balance owed.
class StatementEntry {
  const StatementEntry({
    required this.date,
    required this.type,
    required this.id,
    required this.number,
    required this.debit,
    required this.credit,
    required this.balance,
    this.reference,
    this.dueDate,
  });

  factory StatementEntry.fromJson(Map<String, dynamic> j) => StatementEntry(
    date: _date(j['date']),
    type: '${j['type'] ?? ''}',
    id: _i(j['id']),
    number: '${j['number'] ?? ''}',
    debit: _d(j['debit']),
    credit: _d(j['credit']),
    balance: _d(j['balance']),
    reference: _s(j['reference']),
    dueDate: _date(j['due_date']),
  );

  final DateTime? date, dueDate;
  final String type, number;
  final String? reference;
  final int id;
  final double debit, credit, balance;
}

/// GET /erp/procurement/statement/{supplier}.
class SupplierStatement {
  const SupplierStatement({
    required this.supplier,
    required this.from,
    required this.to,
    required this.openingBalance,
    required this.entries,
    required this.totalInvoiced,
    required this.totalPaid,
    required this.closingBalance,
  });

  factory SupplierStatement.fromJson(Map<String, dynamic> j) => SupplierStatement(
    supplier: Supplier.fromJson(_m(j['supplier'])),
    from: _date(j['from']),
    to: _date(j['to']),
    openingBalance: _d(j['opening_balance']),
    entries: _list(j['entries'], StatementEntry.fromJson),
    totalInvoiced: _d(j['total_invoiced']),
    totalPaid: _d(j['total_paid']),
    closingBalance: _d(j['closing_balance']),
  );

  final Supplier supplier;
  final DateTime? from, to;
  final double openingBalance, totalInvoiced, totalPaid, closingBalance;
  final List<StatementEntry> entries;
}

/// One supplier's row of the payables ageing.
class AgeingRow {
  const AgeingRow({required this.supplier, required this.buckets, required this.total});

  factory AgeingRow.fromJson(Map<String, dynamic> j) => AgeingRow(
    supplier: _ref(j['supplier']) ?? const ErpRef(0, ''),
    buckets: {for (final b in PayablesAgeing.bucketKeys) b: _d(j[b])},
    total: _d(j['total']),
  );

  final ErpRef supplier;
  final Map<String, double> buckets;
  final double total;
}

/// GET /erp/procurement/ageing.
class PayablesAgeing {
  const PayablesAgeing({required this.rows, required this.totals});

  static const bucketKeys = ['current', 'days_1_30', 'days_31_60', 'days_61_90', 'over_90'];

  factory PayablesAgeing.fromJson(Map<String, dynamic> j) {
    final totals = _m(j['totals']);
    return PayablesAgeing(
      rows: _list(j['rows'], AgeingRow.fromJson),
      totals: {for (final b in [...bucketKeys, 'total']) b: _d(totals[b])},
    );
  }

  final List<AgeingRow> rows;
  final Map<String, double> totals;
}

/// A requisition line as the form collects it.
class RequisitionLineDraft {
  RequisitionLineDraft({this.product, this.description = '', this.quantity = '', this.price = ''});

  /// A stock line names a product; a service line describes the work.
  ErpProduct? product;
  String description, quantity, price;

  bool get isService => product == null;
  double? get quantityValue => double.tryParse(quantity.replaceAll(',', ''));
  double get priceValue => double.tryParse(price.replaceAll(',', '')) ?? 0;

  Map<String, dynamic> toJson() => {
    'line_type': isService ? 'service' : 'stock',
    if (!isService) 'product_id': product!.id,
    if (description.trim().isNotEmpty) 'description': description.trim(),
    'quantity': quantityValue ?? 0,
    if (price.trim().isNotEmpty) 'estimated_unit_price': priceValue,
  };
}

/* ═════════════════════════════════════════════════════════════ finance ══ */

/// A cash, bank or mobile money ledger account with its balance.
class CashPosition {
  const CashPosition({required this.accountId, required this.code, required this.name, required this.type, required this.balance, this.bankAccountId});

  factory CashPosition.fromJson(Map<String, dynamic> j) => CashPosition(
    accountId: _i(j['account_id']),
    code: '${j['code'] ?? ''}',
    name: '${j['name'] ?? ''}',
    type: '${j['type'] ?? 'cash'}',
    balance: _d(j['balance']),
    bankAccountId: _in(j['bank_account_id']),
  );

  final int accountId;
  final String code, name, type;
  final double balance;
  final int? bankAccountId;
}

/// Income, costs and profit for a period (the P&L totals).
class ProfitTotals {
  const ProfitTotals(this.values);

  factory ProfitTotals.fromJson(dynamic j) {
    final m = _m(j);
    return ProfitTotals({for (final e in m.entries) e.key: _d(e.value)});
  }

  final Map<String, double> values;

  double get income => values['income'] ?? 0;
  double get costOfSales => values['cost_of_sales'] ?? 0;
  double get grossProfit => values['gross_profit'] ?? 0;
  double get operatingExpenses => values['operating_expenses'] ?? 0;
  double get expenses => values['expenses'] ?? 0;
  double get netProfit => values['net_profit'] ?? 0;
}

/// GET /erp/finance/overview.
class FinanceOverview {
  const FinanceOverview({
    required this.cash,
    required this.cashTotal,
    required this.receivables,
    required this.payables,
    required this.month,
    required this.priorMonth,
    required this.monthFrom,
    required this.currentPeriod,
    required this.currentClosed,
    required this.lastClosed,
    required this.draftCashbook,
    required this.draftTransfers,
    required this.openReconciliations,
    required this.recent,
  });

  factory FinanceOverview.fromJson(Map<String, dynamic> j) {
    final month = _m(j['month']);
    final periods = _m(j['periods']);
    final drafts = _m(j['drafts']);
    return FinanceOverview(
      cash: _list(j['cash'], CashPosition.fromJson),
      cashTotal: _d(j['cash_total']),
      receivables: _d(j['receivables']),
      payables: _d(j['payables']),
      month: ProfitTotals.fromJson(month['totals']),
      priorMonth: ProfitTotals.fromJson(month['prior_totals']),
      monthFrom: _date(month['from']),
      currentPeriod: _s(periods['current']),
      currentClosed: periods['current_closed'] == true,
      lastClosed: _s(periods['last_closed']),
      draftCashbook: _i(drafts['cashbook']),
      draftTransfers: _i(drafts['transfers']),
      openReconciliations: _list(
        j['open_reconciliations'],
        (r) => ErpRef(_i(r['id']), '${_m(r['bank_account'])['name'] ?? ''}', _s(r['number'])),
      ),
      recent: _list(j['recent'], CashbookEntry.fromJson),
    );
  }

  final List<CashPosition> cash;
  final double cashTotal, receivables, payables;
  final ProfitTotals month, priorMonth;
  final DateTime? monthFrom;
  final String? currentPeriod, lastClosed;
  final bool currentClosed;
  final int draftCashbook, draftTransfers;

  /// The reconciliation (number in [ErpRef.code]) and its bank's name.
  final List<ErpRef> openReconciliations;
  final List<CashbookEntry> recent;
}

/// One line of a bank account's statement (from the ledger).
class BankLine {
  const BankLine({required this.date, required this.number, required this.debit, required this.credit, required this.balance, this.description, this.journalId, this.reconciled = false});

  factory BankLine.fromJson(Map<String, dynamic> j) => BankLine(
    date: _date(j['entry_date']),
    number: '${j['number'] ?? ''}',
    debit: _d(j['debit']),
    credit: _d(j['credit']),
    balance: _d(j['balance']),
    description: _s(j['description']) ?? _s(j['memo']),
    journalId: _in(j['journal_entry_id']),
    reconciled: j['reconciled'] == true,
  );

  final DateTime? date;
  final String number;
  final String? description;
  final double debit, credit, balance;
  final int? journalId;
  final bool reconciled;
}

class BankAccount {
  const BankAccount({
    required this.id,
    required this.name,
    required this.type,
    required this.balance,
    this.bankName,
    this.branch,
    this.accountName,
    this.accountNumber,
    this.currency = 'TZS',
    this.openingBalance = 0,
    this.openingDate,
    this.isActive = true,
    this.ledger,
    this.statementFrom,
    this.statementTo,
    this.statementOpening,
    this.statementClosing,
    this.lines = const [],
  });

  factory BankAccount.fromJson(Map<String, dynamic> j) {
    final st = _map(j['statement']);
    return BankAccount(
      id: _i(j['id']),
      name: '${j['name'] ?? ''}',
      type: '${j['type'] ?? 'bank'}',
      balance: _d(j['balance']),
      bankName: _s(j['bank_name']),
      branch: _s(j['branch']),
      accountName: _s(j['account_name']),
      accountNumber: _s(j['account_number']),
      currency: _s(j['currency']) ?? 'TZS',
      openingBalance: _d(j['opening_balance']),
      openingDate: _date(j['opening_date']),
      isActive: j['is_active'] != false,
      ledger: _ref(j['account']),
      statementFrom: st == null ? null : _date(st['from']),
      statementTo: st == null ? null : _date(st['to']),
      statementOpening: st == null ? null : _d(st['opening']),
      statementClosing: st == null ? null : _d(st['closing']),
      lines: st == null ? const [] : _list(st['lines'], BankLine.fromJson),
    );
  }

  final int id;
  final String name, type, currency;
  final double balance, openingBalance;
  final String? bankName, branch, accountName, accountNumber;
  final DateTime? openingDate;
  final bool isActive;
  final ErpRef? ledger;
  final DateTime? statementFrom, statementTo;
  final double? statementOpening, statementClosing;
  final List<BankLine> lines;
}

/// A general receipt or payment through a bank or cash account.
class CashbookEntry {
  const CashbookEntry({
    required this.id,
    required this.number,
    required this.type,
    required this.status,
    required this.amount,
    required this.description,
    this.entryDate,
    this.counterparty,
    this.reference,
    this.bankAccount,
    this.account,
    this.creator,
    this.createdBy,
    this.poster,
    this.postedAt,
    this.journal,
    this.reversalReason,
  });

  factory CashbookEntry.fromJson(Map<String, dynamic> j) => CashbookEntry(
    id: _i(j['id']),
    number: '${j['number'] ?? ''}',
    type: '${j['type'] ?? 'payment'}',
    status: '${j['status'] ?? 'draft'}',
    amount: _d(j['amount']),
    description: '${j['description'] ?? ''}',
    entryDate: _date(j['entry_date']),
    counterparty: _s(j['counterparty']),
    reference: _s(j['reference']),
    bankAccount: _ref(j['bank_account']),
    account: _ref(j['account']),
    creator: _ref(j['creator']),
    createdBy: _in(j['created_by']),
    poster: _ref(j['poster']),
    postedAt: _time(j['posted_at']),
    journal: _numbered(j['journal']),
    reversalReason: _s(j['reversal_reason']),
  );

  final int id;
  final String number, type, status, description;
  final double amount;
  final DateTime? entryDate, postedAt;
  final String? counterparty, reference, reversalReason;
  final ErpRef? bankAccount, account, creator, poster, journal;
  final int? createdBy;

  bool get isReceipt => type == 'receipt';
}

/// GET /erp/finance/cashbook: a page of entries and the posted totals.
class CashbookPage {
  const CashbookPage(this.page, this.receipts, this.payments);

  factory CashbookPage.fromJson(Map<String, dynamic> j) {
    final totals = _m(j['totals']);
    return CashbookPage(ErpPage.fromJson(j, CashbookEntry.fromJson), _d(totals['receipts']), _d(totals['payments']));
  }

  final ErpPage<CashbookEntry> page;
  final double receipts, payments;
}

/// A cashbook entry as the form collects it.
class CashbookDraft {
  CashbookDraft({required this.type});

  String type; // 'receipt' | 'payment'
  DateTime entryDate = DateTime.now();
  int? bankAccountId;
  int? accountId;
  String amount = '', counterparty = '', reference = '', description = '';

  double? get amountValue => double.tryParse(amount.replaceAll(',', ''));

  Map<String, dynamic> toJson() => {
    'type': type,
    'entry_date':
        '${entryDate.year}-${'${entryDate.month}'.padLeft(2, '0')}-${'${entryDate.day}'.padLeft(2, '0')}',
    'bank_account_id': bankAccountId,
    'account_id': accountId,
    'amount': amountValue,
    if (counterparty.trim().isNotEmpty) 'counterparty': counterparty.trim(),
    if (reference.trim().isNotEmpty) 'reference': reference.trim(),
    'description': description.trim(),
  };
}

/// A ledger account (the chart of accounts).
class LedgerAccount {
  const LedgerAccount({required this.id, required this.code, required this.name, required this.type});

  factory LedgerAccount.fromJson(Map<String, dynamic> j) =>
      LedgerAccount(id: _i(j['id']), code: '${j['code'] ?? ''}', name: '${j['name'] ?? ''}', type: '${j['type'] ?? ''}');

  final int id;
  final String code, name, type;

  String get label => '$code · $name';
}

class JournalLine {
  const JournalLine({required this.account, required this.debit, required this.credit, this.description});

  factory JournalLine.fromJson(Map<String, dynamic> j) => JournalLine(
    account: _ref(j['account']) ?? const ErpRef(0, ''),
    debit: _d(j['debit']),
    credit: _d(j['credit']),
    description: _s(j['description']),
  );

  final ErpRef account;
  final double debit, credit;
  final String? description;
}

class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.number,
    required this.status,
    required this.total,
    this.entryDate,
    this.memo,
    this.sourceType,
    this.purpose,
    this.creator,
    this.postedAt,
    this.reversalOf,
    this.lines = const [],
  });

  factory JournalEntry.fromJson(Map<String, dynamic> j) => JournalEntry(
    id: _i(j['id']),
    number: '${j['number'] ?? ''}',
    status: '${j['status'] ?? 'posted'}',
    total: _d(j['total']),
    entryDate: _date(j['entry_date']),
    memo: _s(j['memo']),
    sourceType: _s(j['source_type']),
    purpose: _s(j['purpose']),
    creator: _ref(j['creator']),
    postedAt: _time(j['posted_at']),
    reversalOf: _numbered(j['reversal_of']),
    lines: _list(j['lines'], JournalLine.fromJson),
  );

  final int id;
  final String number, status;
  final double total;
  final DateTime? entryDate, postedAt;
  final String? memo, sourceType, purpose;
  final ErpRef? creator, reversalOf;
  final List<JournalLine> lines;
}

class TrialBalanceRow {
  const TrialBalanceRow({required this.code, required this.name, required this.type, required this.debit, required this.credit, required this.balance});

  factory TrialBalanceRow.fromJson(Map<String, dynamic> j) => TrialBalanceRow(
    code: '${j['code'] ?? ''}',
    name: '${j['name'] ?? ''}',
    type: '${j['type'] ?? ''}',
    debit: _d(j['debit']),
    credit: _d(j['credit']),
    balance: _d(j['balance']),
  );

  final String code, name, type;
  final double debit, credit, balance;
}

/// GET /erp/trial-balance.
class TrialBalance {
  const TrialBalance({required this.rows, required this.totalDebit, required this.totalCredit, required this.balanced});

  factory TrialBalance.fromJson(Map<String, dynamic> j) => TrialBalance(
    rows: _list(j['rows'], TrialBalanceRow.fromJson),
    totalDebit: _d(j['total_debit']),
    totalCredit: _d(j['total_credit']),
    balanced: j['balanced'] != false,
  );

  final List<TrialBalanceRow> rows;
  final double totalDebit, totalCredit;
  final bool balanced;
}

/// One account's line on a statement.
class StatementRow {
  const StatementRow({required this.code, required this.name, required this.section, required this.amount, this.prior});

  factory StatementRow.fromJson(Map<String, dynamic> j) => StatementRow(
    code: '${j['code'] ?? ''}',
    name: '${j['name'] ?? ''}',
    section: '${j['section'] ?? ''}',
    amount: _d(j['amount']),
    prior: _dn(j['prior']),
  );

  final String code, name, section;
  final double amount;
  final double? prior;
}

/// GET /erp/finance/statements/profit-and-loss.
class ProfitAndLoss {
  const ProfitAndLoss({required this.from, required this.to, required this.priorFrom, required this.priorTo, required this.rows, required this.totals, required this.prior});

  factory ProfitAndLoss.fromJson(Map<String, dynamic> j) => ProfitAndLoss(
    from: _date(j['from']),
    to: _date(j['to']),
    priorFrom: _date(j['prior_from']),
    priorTo: _date(j['prior_to']),
    rows: _list(j['rows'], StatementRow.fromJson),
    totals: ProfitTotals.fromJson(j['totals']),
    prior: ProfitTotals.fromJson(j['prior_totals']),
  );

  final DateTime? from, to, priorFrom, priorTo;
  final List<StatementRow> rows;
  final ProfitTotals totals, prior;

  List<StatementRow> section(String key) => rows.where((r) => r.section == key).toList();
}

/// GET /erp/finance/statements/balance-sheet.
class BalanceSheet {
  const BalanceSheet({required this.asOf, required this.rows, required this.totals, required this.currentEarnings, required this.balanced});

  factory BalanceSheet.fromJson(Map<String, dynamic> j) => BalanceSheet(
    asOf: _date(j['as_of']),
    rows: _list(j['rows'], StatementRow.fromJson),
    totals: {for (final e in _m(j['totals']).entries) e.key: _d(e.value)},
    currentEarnings: _d(j['current_earnings']),
    balanced: j['balanced'] != false,
  );

  final DateTime? asOf;
  final List<StatementRow> rows;
  final Map<String, double> totals;
  final double currentEarnings;
  final bool balanced;

  List<StatementRow> section(String key) => rows.where((r) => r.section == key).toList();
}

class BudgetRow {
  const BudgetRow({required this.code, required this.name, required this.type, required this.budget, required this.actual, required this.variance, this.usedPercent});

  factory BudgetRow.fromJson(Map<String, dynamic> j) => BudgetRow(
    code: '${j['code'] ?? ''}',
    name: '${j['name'] ?? ''}',
    type: '${j['type'] ?? ''}',
    budget: _d(j['budget']),
    actual: _d(j['actual']),
    variance: _d(j['variance']),
    usedPercent: _dn(j['used_percent']),
  );

  final String code, name, type;
  final double budget, actual, variance;
  final double? usedPercent;
}

/// GET /erp/finance/statements/budget-vs-actual.
class BudgetVsActual {
  const BudgetVsActual({required this.year, required this.hasBudget, required this.rows, required this.totals, this.from, this.to});

  factory BudgetVsActual.fromJson(Map<String, dynamic> j) => BudgetVsActual(
    year: _i(j['fiscal_year']),
    hasBudget: j['has_budget'] == true,
    rows: _list(j['rows'], BudgetRow.fromJson),
    totals: {for (final e in _m(j['totals']).entries) e.key: _d(e.value)},
    from: _date(j['from']),
    to: _date(j['to']),
  );

  final int year;
  final bool hasBudget;
  final List<BudgetRow> rows;
  final Map<String, double> totals;
  final DateTime? from, to;
}

/* ══════════════════════════════════════════════════════════════ assets ══ */

class AssetClassSummary {
  const AssetClassSummary({required this.id, required this.name, required this.count, required this.cost, required this.bookValue, this.code});

  factory AssetClassSummary.fromJson(Map<String, dynamic> j) => AssetClassSummary(
    id: _i(j['id']),
    name: '${j['name'] ?? ''}',
    code: _s(j['code']),
    count: _i(j['count']),
    cost: _d(j['cost']),
    bookValue: _d(j['book_value']),
  );

  final int id, count;
  final String name;
  final String? code;
  final double cost, bookValue;
}

class DepreciationRun {
  const DepreciationRun({
    required this.id,
    required this.number,
    required this.period,
    required this.total,
    required this.assetsCount,
    this.runDate,
    this.creator,
    this.journal,
    this.lines = const [],
  });

  factory DepreciationRun.fromJson(Map<String, dynamic> j) => DepreciationRun(
    id: _i(j['id']),
    number: '${j['number'] ?? ''}',
    period: '${j['period'] ?? ''}',
    total: _d(j['total']),
    assetsCount: _i(j['assets_count']),
    runDate: _date(j['run_date']),
    creator: _ref(j['creator']),
    journal: _map(j['journal']) == null
        ? (j['journal_entry_id'] == null ? null : ErpRef(_i(j['journal_entry_id']), ''))
        : _numbered(j['journal']),
    lines: _list(j['lines'], DepreciationLine.fromJson),
  );

  final int id, assetsCount;
  final String number, period;
  final double total;
  final DateTime? runDate;
  final ErpRef? creator, journal;
  final List<DepreciationLine> lines;
}

/// One asset's charge in a depreciation run, or one month of an asset's
/// history.
class DepreciationLine {
  const DepreciationLine({required this.period, required this.opening, required this.amount, required this.closing, this.asset, this.assetTag, this.run});

  factory DepreciationLine.fromJson(Map<String, dynamic> j) {
    final asset = _map(j['asset']);
    final run = _map(j['run']);
    return DepreciationLine(
      period: '${j['period'] ?? ''}',
      opening: _d(j['opening_value']),
      amount: _d(j['amount']),
      closing: _d(j['closing_value']),
      asset: asset == null ? null : ErpRef(_i(asset['id']), '${asset['name'] ?? ''}', _s(asset['tag'])),
      run: run == null ? null : ErpRef(_i(run['id']), '${run['number'] ?? ''}'),
    );
  }

  final String period;
  final double opening, amount, closing;

  /// The asset, its tag in [ErpRef.code].
  final ErpRef? asset;
  final String? assetTag;
  final ErpRef? run;
}

/// GET /erp/assets/overview.
class AssetsOverview {
  const AssetsOverview({
    required this.counts,
    required this.cost,
    required this.accumulated,
    required this.bookValue,
    required this.byClass,
    required this.latestRun,
    required this.nextPeriod,
    required this.nextDue,
    required this.disposedThisYear,
  });

  factory AssetsOverview.fromJson(Map<String, dynamic> j) => AssetsOverview(
    counts: {for (final e in _m(j['counts']).entries) e.key: _i(e.value)},
    cost: _d(j['cost']),
    accumulated: _d(j['accumulated']),
    bookValue: _d(j['book_value']),
    byClass: _list(j['by_class'], AssetClassSummary.fromJson),
    latestRun: _map(j['latest_run']) == null ? null : DepreciationRun.fromJson(_m(j['latest_run'])),
    nextPeriod: _s(j['next_period']),
    nextDue: _d(j['next_due']),
    disposedThisYear: _list(j['disposed_this_year'], FixedAsset.fromJson),
  );

  final Map<String, int> counts;
  final double cost, accumulated, bookValue, nextDue;
  final List<AssetClassSummary> byClass;
  final DepreciationRun? latestRun;
  final String? nextPeriod;
  final List<FixedAsset> disposedThisYear;

  int get active => counts['active'] ?? 0;
}

/// Something that happened to an asset: registered, capitalised,
/// transferred to a place or a person, disposed.
class AssetEvent {
  const AssetEvent({required this.type, this.date, this.fromLocation, this.toLocation, this.fromCustodian, this.toCustodian, this.amount, this.notes, this.user});

  factory AssetEvent.fromJson(Map<String, dynamic> j) => AssetEvent(
    type: '${j['type'] ?? ''}',
    date: _date(j['event_date']),
    fromLocation: _s(j['from_location']),
    toLocation: _s(j['to_location']),
    fromCustodian: _ref(j['from_custodian']),
    toCustodian: _ref(j['to_custodian']),
    amount: _dn(j['amount']),
    notes: _s(j['notes']),
    user: _ref(j['user']),
  );

  final String type;
  final DateTime? date;
  final String? fromLocation, toLocation, notes;
  final ErpRef? fromCustodian, toCustodian, user;
  final double? amount;
}

/// A month of an asset's depreciation schedule, posted or still to come.
class ScheduleRow {
  const ScheduleRow({required this.period, required this.opening, required this.amount, required this.closing, required this.posted});

  factory ScheduleRow.fromJson(Map<String, dynamic> j) => ScheduleRow(
    period: '${j['period'] ?? ''}',
    opening: _d(j['opening']),
    amount: _d(j['amount']),
    closing: _d(j['closing']),
    posted: j['posted'] == true,
  );

  final String period;
  final double opening, amount, closing;
  final bool posted;
}

class FixedAsset {
  const FixedAsset({
    required this.id,
    required this.tag,
    required this.name,
    required this.status,
    required this.cost,
    required this.accumulated,
    this.bookValue,
    this.description,
    this.assetClass,
    this.serialNumber,
    this.location,
    this.custodian,
    this.supplier,
    this.acquisitionDate,
    this.residualValue = 0,
    this.method,
    this.usefulLifeMonths,
    this.rate,
    this.funding,
    this.disposalDate,
    this.disposalProceeds,
    this.disposalGainLoss,
    this.disposalReason,
    this.capitalisedAt,
    this.events = const [],
    this.schedule = const [],
    this.depreciation = const [],
  });

  factory FixedAsset.fromJson(Map<String, dynamic> j) => FixedAsset(
    id: _i(j['id']),
    tag: '${j['tag'] ?? ''}',
    name: '${j['name'] ?? ''}',
    status: '${j['status'] ?? 'draft'}',
    cost: _d(j['cost']),
    accumulated: _d(j['accumulated_depreciation']),
    bookValue: _dn(j['book_value']),
    description: _s(j['description']),
    assetClass: _ref(j['asset_class']),
    serialNumber: _s(j['serial_number']),
    location: _s(j['location']),
    custodian: _ref(j['custodian']),
    supplier: _ref(j['supplier']),
    acquisitionDate: _date(j['acquisition_date']),
    residualValue: _d(j['residual_value']),
    method: _s(j['method']),
    usefulLifeMonths: _in(j['useful_life_months']),
    rate: _dn(j['rate']),
    funding: _s(j['funding']),
    disposalDate: _date(j['disposal_date']),
    disposalProceeds: _dn(j['disposal_proceeds']),
    disposalGainLoss: _dn(j['disposal_gain_loss']),
    disposalReason: _s(j['disposal_reason']),
    capitalisedAt: _time(j['capitalised_at']),
    events: _list(j['events'], AssetEvent.fromJson),
    schedule: _list(j['schedule'], ScheduleRow.fromJson),
    depreciation: _list(j['depreciation'], DepreciationLine.fromJson),
  );

  final int id;
  final String tag, name, status;
  final double cost, accumulated, residualValue;
  final double? bookValue, rate;
  final String? description, serialNumber, location, method, funding, disposalReason;
  final ErpRef? assetClass, custodian, supplier;
  final DateTime? acquisitionDate, disposalDate, capitalisedAt;
  final int? usefulLifeMonths;
  final double? disposalProceeds, disposalGainLoss;
  final List<AssetEvent> events;
  final List<ScheduleRow> schedule;
  final List<DepreciationLine> depreciation;

  /// Cost less depreciation so far (the API's figure when it sends one).
  double get netBookValue => bookValue ?? (cost - accumulated);

  /// How much of the depreciable amount has been written off, 0 to 1.
  double get depreciatedShare {
    final base = cost - residualValue;
    return base <= 0 ? 0 : (accumulated / base).clamp(0, 1);
  }
}
