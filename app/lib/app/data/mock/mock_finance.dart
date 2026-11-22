import '../services/api_service.dart';
import 'mock_seed.dart';

/// The in-app stand-in for the Procurement, Finance and Assets endpoints
/// (/erp/procurement/*, /erp/suppliers, /erp/finance/*, /erp/journals,
/// /erp/trial-balance, /erp/assets/*), answering with the JSON shapes the
/// Laravel controllers return. Approving, rejecting, raising a voucher,
/// recording and posting a cashbook entry change the fixture, so a flow
/// tried offline reads back the way it would against the server.
///
/// [MockErp] asks it first and falls back to its own routes.
class MockFinance {
  MockFinance() {
    _seed();
  }

  static const unhandled = Object();

  static const _procurementAll = [
    'procurement.view', 'procurement.request', 'procurement.approve', 'procurement.quote', //
    'procurement.order', 'procurement.receive', 'procurement.invoice', 'procurement.pay',
  ];
  static const _financeAll = [
    'finance.view', 'finance.bank', 'finance.cashbook', 'finance.statements', 'finance.close', 'finance.budget', //
    'assets.view', 'assets.manage', 'assets.depreciate', 'assets.dispose',
  ];

  /// The role's procurement, finance and asset permissions on top of
  /// [base], as the backend's Modules/Procurement.php and Finance.php
  /// defaults grant them. A test's explicit set is left as it is.
  List<String> withPermissions(List<String> base, String role, {bool explicit = false}) {
    if (explicit) return base;
    final extra = rolePermissions(role);
    return [...base, ...extra.where((p) => !base.contains(p))];
  }

  /// What a built-in role holds in these three apps.
  static List<String> rolePermissions(String role) {
    return switch (role) {
      'company_admin' => [..._procurementAll, ..._financeAll],
      'finance' => ['suppliers.view', 'procurement.view', 'procurement.approve', 'procurement.invoice', 'procurement.pay', ..._financeAll],
      'ceo' || 'director' => ['procurement.view', 'procurement.approve', 'finance.view', 'finance.statements', 'assets.view'],
      'hod' || 'manager' => ['procurement.view', 'procurement.request', 'procurement.approve'],
      'cashier' => ['procurement.view', 'procurement.pay'],
      _ => const <String>[],
    };
  }

  /* ════════════════════════════════════════════════════════ the dataset ══ */

  final suppliers = <Map<String, dynamic>>[];
  final requisitions = <Map<String, dynamic>>[];
  final orders = <Map<String, dynamic>>[];
  final invoices = <Map<String, dynamic>>[];
  final payments = <Map<String, dynamic>>[];
  final banks = <Map<String, dynamic>>[];
  final cashbook = <Map<String, dynamic>>[];
  final journals = <Map<String, dynamic>>[];
  final assets = <Map<String, dynamic>>[];
  final runs = <Map<String, dynamic>>[];

  /// The payment voucher raised for each supplier invoice, by invoice id.
  final vouchers = <int, Map<String, dynamic>>{};
  int _nextVoucher = 9001, _nextRequisition = 10, _nextCashbook = 20, _nextJournal = 60;

  static String _day(int daysAgo) => iso(daysAgo).substring(0, 10);
  static String _date(int daysAgo) => '${_day(daysAgo)}T00:00:00.000000Z';

  static const _people = {
    2: 'Neema Shirima',
    4: 'Rehema Juma',
    9: 'Joseph Mrisho',
    62: 'Grace Mushi',
    64: 'Upendo Kimaro',
    77: 'Daudi Mollel',
  };

  Map<String, dynamic> _person(int id) => {'id': id, 'name': _people[id] ?? 'Staff'};

  Map<String, dynamic> _supplierRef(int id) {
    final s = suppliers.firstWhere((s) => s['id'] == id);
    return {'id': id, 'code': s['code'], 'name': s['name'], 'payment_terms_days': s['payment_terms_days']};
  }

  void _seed() {
    Map<String, dynamic> supplier(int id, String code, String name, String category, String phone, int terms, String bank, String number) => {
      'id': id, 'code': code, 'name': name, 'category': category, 'contact_person': null, 'phone': phone, //
      'email': null, 'tin': null, 'address': null, 'city': 'Dar es Salaam', 'payment_terms_days': terms,
      'bank_name': bank, 'bank_account_name': name, 'bank_account_number': number, 'is_active': true,
    };
    suppliers.addAll([
      supplier(1, 'SUP-0001', 'East Africa PET Industries', 'Raw materials', '+255 754 210 300', 30, 'CRDB Bank', '0150 2233 4401'),
      supplier(2, 'SUP-0002', 'Dar Packaging Solutions', 'Packaging', '+255 713 440 912', 14, 'NMB Bank', '2041 7781 120'),
      supplier(3, 'SUP-0003', 'Mlimani Tyre Centre', 'Vehicle parts', '+255 765 118 220', 7, 'NBC Bank', '0110 4432 778'),
      supplier(4, 'SUP-0101', 'Kariakoo Packaging Traders', 'Packaging', '+255 787 330 455', 30, 'CRDB Bank', '0150 9981 002'),
      supplier(5, 'SUP-0102', 'Lake Zone Industrial Supplies', 'Chemicals', '+255 744 902 113', 21, 'Exim Bank', '0020 1188 773'),
    ]);
    suppliers.first['contact_person'] = 'Mwanaisha Ally';

    Map<String, dynamic> line(int id, String type, String description, double qty, double price, {int? product, String? unit, double received = 0}) => {
      'id': id, 'line_type': type, 'product_id': product, 'description': description, 'quantity': qty.toStringAsFixed(3), //
      'estimated_unit_price': price.toStringAsFixed(2), 'unit_price': price.toStringAsFixed(2),
      'amount': (qty * price).toStringAsFixed(2), 'vat_rate': '18.00', 'vat_amount': (qty * price * .18).toStringAsFixed(2),
      'received_quantity': received.toStringAsFixed(3),
      'product': product == null ? null : {'id': product, 'sku': 'SKU-$product', 'name': description, 'unit': {'id': 2, 'code': unit ?? 'PCS'}},
      'expense_account': type == 'service' ? {'id': 25, 'code': '6200', 'name': 'Vehicle repairs & maintenance'} : null,
    };

    Map<String, dynamic> requisition(int id, String status, String why, int needed, List<Map<String, dynamic>> lines, {int approvals = 1, int by = 64}) => {
      'id': id, 'number': 'PRQ-2026-${'$id'.padLeft(6, '0')}', 'requested_by': by, 'needed_by': _date(-needed), //
      'justification': why, 'status': status, 'approvals_required': approvals,
      'total': lines.fold<double>(0, (s, l) => s + double.parse('${l['amount']}')).toStringAsFixed(2),
      'submitted_at': status == 'draft' ? null : iso(2), 'created_at': iso(3), 'lines_count': lines.length,
      'department': null, 'requester': _person(by), 'lines': lines, 'approvals': <Map<String, dynamic>>[], 'orders': <Map<String, dynamic>>[],
    };
    requisitions.addAll([
      requisition(4, 'submitted', 'Preforms for the December peak, three weeks of production', 14,
          [line(41, 'stock', 'PET preform 28g', 60000, 95, product: 1)], approvals: 2),
      requisition(3, 'submitted', 'Service the factory compressor before the peak', 7,
          [line(31, 'service', 'Compressor service and filter change', 1, 850000)]),
      requisition(2, 'approved', 'Shrink film for the 24-pack line, January requirement', 20,
          [line(21, 'stock', 'Shrink film roll', 400, 5200, product: 4, unit: 'KG')]),
      requisition(1, 'draft', 'Labels for the new 1.5 litre artwork', 25, [line(11, 'stock', 'Label: 1.5L', 30000, 14, product: 3)], by: 2),
    ]);
    requisitions.first['approvals'] = [
      {'level': 1, 'decision': 'approved', 'comment': 'Within the quarterly plan.', 'created_at': iso(1), 'user': {'id': 9, 'name': 'Joseph Mrisho', 'role': 'hod'}},
    ];

    Map<String, dynamic> order(int id, int supplierId, String status, int daysAgo, List<Map<String, dynamic>> lines, {int by = 64}) {
      final sub = lines.fold<double>(0, (s, l) => s + double.parse('${l['amount']}'));
      return {
        'id': id, 'number': 'LPO-2026-${'$id'.padLeft(6, '0')}', 'supplier_id': supplierId, 'status': status, //
        'order_date': _date(daysAgo), 'expected_date': _date(daysAgo - 7), 'payment_terms': '30 days', 'currency': 'TZS',
        'subtotal': sub.toStringAsFixed(2), 'vat_amount': (sub * .18).toStringAsFixed(2), 'total': (sub * 1.18).toStringAsFixed(2),
        'approvals_required': 1, 'notes': null, 'cancel_reason': null, 'created_by': by, 'lines_count': lines.length,
        'ordered_quantity': lines.fold<double>(0, (s, l) => s + double.parse('${l['quantity']}')).toStringAsFixed(3),
        'received_quantity': lines.fold<double>(0, (s, l) => s + double.parse('${l['received_quantity']}')).toStringAsFixed(3),
        'supplier': _supplierRef(supplierId), 'warehouse': {'id': 1, 'code': 'MAIN', 'name': 'Factory store Mbezi'},
        'creator': _person(by), 'requisition': null, 'lines': lines, 'approvals': <Map<String, dynamic>>[], 'invoices': <Map<String, dynamic>>[],
      };
    }
    orders.addAll([
      order(6, 4, 'submitted', 1, [line(61, 'stock', 'Label: 500ml', 50000, 12, product: 3)]),
      order(5, 1, 'partially_received', 9, [line(51, 'stock', 'PET preform 28g', 40000, 95, product: 1, received: 25000)]),
      order(4, 2, 'received', 14, [line(41, 'stock', 'Label: 500ml', 80000, 12, product: 3, received: 80000)]),
      order(3, 3, 'closed', 30, [line(31, 'service', 'Six drive tyres fitted, truck T 482 DLM', 6, 780000)]),
      order(2, 5, 'draft', 0, [line(21, 'stock', 'Chlorine tablets', 20, 14500, product: 8, unit: 'KG')]),
    ]);

    Map<String, dynamic> invoice(int id, int supplierId, int orderId, String ref, String status, String match, int daysAgo, int terms, double total, double paid) => {
      'id': id, 'number': 'SINV-2026-${'$id'.padLeft(6, '0')}', 'supplier_id': supplierId, 'purchase_order_id': orderId, //
      'supplier_invoice_number': ref, 'invoice_date': _date(daysAgo), 'due_date': _date(daysAgo - terms),
      'subtotal': (total / 1.18).toStringAsFixed(2), 'vat_amount': (total - total / 1.18).toStringAsFixed(2),
      'total': total.toStringAsFixed(2), 'amount_paid': paid.toStringAsFixed(2), 'status': status, 'match_status': match,
      'outstanding': status == 'posted' ? total - paid : 0,
      'payment_status': status != 'posted' ? null : (paid >= total ? 'paid' : paid > 0 ? 'partially_paid' : 'unpaid'),
      'created_by': 62, 'created_at': iso(daysAgo), 'posted_at': status == 'posted' ? iso(daysAgo) : null,
      'notes': null, 'supplier': _supplierRef(supplierId),
      'order': {'id': orderId, 'number': 'LPO-2026-${'$orderId'.padLeft(6, '0')}'},
      'creator': _person(62), 'poster': status == 'posted' ? _person(62) : null, 'variance_approver': null,
      'journal': status == 'posted' ? {'id': 40 + id, 'number': 'JE-2026-${'${40 + id}'.padLeft(6, '0')}', 'status': 'posted'} : null,
      'lines': <Map<String, dynamic>>[], 'allocations': <Map<String, dynamic>>[], 'approvals': <Map<String, dynamic>>[],
    };
    invoices.addAll([
      invoice(4, 2, 4, 'DPS-INV-0518', 'awaiting_approval', 'variance', 3, 14, 1189440, 0),
      invoice(3, 3, 3, 'MTC-0457', 'posted', 'matched', 23, 7, 5664000, 2832000),
      invoice(2, 1, 5, 'EAPI-INV-4519', 'posted', 'matched', 12, 30, 1062000, 0),
      invoice(1, 1, 5, 'EAPI-INV-4402', 'posted', 'matched', 60, 30, 2242000, 2242000),
    ]);
    invoices[0]['lines'] = [
      {
        ...line(71, 'stock', 'Label: 500ml', 80000, 12.6, product: 3),
        'order_unit_price': '12.00', 'matchable_quantity': '80000.000', 'price_variance': '48000.00',
        'quantity_variance': '0.000', 'flagged': true, 'order_line': {'id': 41, 'quantity': '80000.000'},
      },
    ];
    for (final i in invoices.skip(1)) {
      i['lines'] = [
        {
          ...line(70 + (i['id'] as int), 'service', 'Goods and services per order', 1, double.parse('${i['subtotal']}')),
          'order_unit_price': i['subtotal'], 'price_variance': '0.00', 'quantity_variance': '0.000', 'flagged': false,
        },
      ];
    }

    Map<String, dynamic> payment(int id, int supplierId, int invoiceId, double amount, int daysAgo, String ref) => {
      'id': id, 'number': 'SPAY-2026-${'$id'.padLeft(6, '0')}', 'supplier_id': supplierId, 'payment_date': _date(daysAgo), //
      'method': 'bank_transfer', 'reference': ref, 'amount': amount.toStringAsFixed(2), 'status': 'posted', 'notes': null,
      'posted_at': iso(daysAgo), 'allocations_count': 1, 'supplier': _supplierRef(supplierId),
      'account': {'id': 73, 'code': '1220', 'name': 'CRDB Bank: collections'}, 'creator': _person(77), 'poster': _person(77),
      'journal': {'id': 50 + id, 'number': 'JE-2026-${'${50 + id}'.padLeft(6, '0')}', 'status': 'posted'},
      'invoice_id': invoiceId,
    };
    payments.addAll([payment(2, 3, 3, 2832000, 10, 'NBC-EFT-20981'), payment(1, 1, 1, 2242000, 35, 'CRDB-TT-58810')]);
    for (final p in payments) {
      final inv = invoices.firstWhere((i) => i['id'] == p['invoice_id']);
      final alloc = {'id': p['id'], 'amount': p['amount']};
      p['allocations'] = [{...alloc, 'invoice': _invoiceBrief(inv)}];
      inv['allocations'] = [
        {...alloc, 'payment': {'id': p['id'], 'number': p['number'], 'payment_date': p['payment_date'], 'status': 'posted', 'amount': p['amount']}},
      ];
    }

    Map<String, dynamic> bank(int id, int accountId, String code, String name, String type, String bankName, String number, double balance) => {
      'id': id, 'account_id': accountId, 'name': name, 'type': type, 'bank_name': bankName, 'branch': null, //
      'account_name': 'Watercom Limited', 'account_number': number, 'currency': 'TZS', 'opening_balance': '185000000.00',
      'opening_date': '2026-04-01T00:00:00.000000Z', 'is_active': true, 'balance': balance,
      'account': {'id': accountId, 'code': code, 'name': name},
    };
    banks.addAll([
      bank(1, 72, '1210', 'NMB Bank: operations', 'bank', 'NMB Bank', '2041 0098 551', 545887282.04),
      bank(2, 73, '1220', 'CRDB Bank: collections', 'bank', 'CRDB Bank', '0150 4471 9900', 41215000),
      bank(3, 74, '1230', 'M-Pesa till 556677', 'mobile_money', 'Vodacom M-Pesa', '556677', 11800000),
    ]);

    Map<String, dynamic> entry(int id, String type, int daysAgo, int bankId, int accountId, String code, String accountName, double amount, String party, String description, String status) => {
      'id': id, 'number': '${type == 'receipt' ? 'CBR' : 'CBP'}-2026-${'$id'.padLeft(6, '0')}', 'type': type, //
      'entry_date': _date(daysAgo), 'bank_account_id': bankId, 'account_id': accountId, 'amount': amount.toStringAsFixed(2),
      'counterparty': party, 'reference': null, 'description': description, 'status': status, 'created_by': 62,
      'posted_at': status == 'posted' ? iso(daysAgo) : null, 'reversal_reason': null,
      'bank_account': {'id': bankId, 'name': banks.firstWhere((b) => b['id'] == bankId)['name']},
      'account': {'id': accountId, 'code': code, 'name': accountName}, 'creator': _person(62),
      'poster': status == 'posted' ? _person(77) : null,
      'journal': status == 'posted' ? {'id': id + 100, 'number': 'JE-2026-${'${id + 100}'.padLeft(6, '0')}'} : null,
    };
    cashbook.addAll([
      entry(6, 'receipt', 0, 3, 19, '4900', 'Other income', 760000, 'Green Recycling Mwanza', 'Sale of scrap PET bales', 'draft'),
      entry(5, 'payment', 0, 2, 27, '6400', 'Utilities', 3300000, 'TANESCO', 'Electricity, factory meter', 'draft'),
      entry(4, 'payment', 4, 1, 28, '6300', 'Rent', 4500000, 'Kijitonyama Properties', 'Head office rent, November', 'posted'),
      entry(3, 'payment', 8, 2, 27, '6400', 'Utilities', 685000, 'DAWASA', 'Water and sewerage', 'posted'),
      entry(2, 'receipt', 12, 1, 19, '4900', 'Other income', 1250000, 'Bahari Bottlers', 'Rental of the spare blow moulder', 'posted'),
      entry(1, 'payment', 20, 1, 29, '6640', 'Professional fees', 2950000, 'Mwakilema & Co.', 'Audit fee, interim', 'posted'),
    ]);

    Map<String, dynamic> journal(int id, int daysAgo, String memo, String source, List<(String, String, double, double)> lines) => {
      'id': id, 'number': 'JE-2026-${'$id'.padLeft(6, '0')}', 'entry_date': _date(daysAgo), 'memo': memo, //
      'source_type': source, 'purpose': 'post', 'status': 'posted',
      'total': lines.fold<double>(0, (s, l) => s + l.$3).toStringAsFixed(2), 'reversal_of_id': null,
      'posted_at': iso(daysAgo), 'creator': _person(62), 'reversal_of': null,
      'lines': [
        for (final (i, l) in lines.indexed)
          {'id': id * 10 + i, 'account': {'id': i + 1, 'code': l.$1, 'name': l.$2}, 'debit': l.$3.toStringAsFixed(2), 'credit': l.$4.toStringAsFixed(2), 'description': memo},
      ],
    };
    journals.addAll([
      journal(58, 12, 'Depreciation October 2026 (DPR-2026-000003)', 'AssetDepreciationRun', [
        ('6600', 'Depreciation', 21616380.03, 0),
        ('1525', 'Accumulated depreciation: plant & machinery', 0, 21616380.03),
      ]),
      journal(54, 4, 'Payment CBP-2026-000004: Head office rent, November', 'CashbookEntry', [
        ('6300', 'Rent', 4500000, 0),
        ('1210', 'NMB Bank: operations', 0, 4500000),
      ]),
      journal(52, 10, 'Supplier payment SPAY-2026-000002', 'SupplierPayment', [
        ('2100', 'Accounts payable', 2832000, 0),
        ('1220', 'CRDB Bank: collections', 0, 2832000),
      ]),
      journal(43, 23, 'Supplier invoice SINV-2026-000003, MTC-0457', 'SupplierInvoice', [
        ('6200', 'Vehicle repairs & maintenance', 4800000, 0),
        ('1400', 'VAT input', 864000, 0),
        ('2100', 'Accounts payable', 0, 5664000),
      ]),
    ]);

    Map<String, dynamic> asset(int id, String tag, String name, int classId, String className, String location, int custodian, double cost, double accumulated, String status, int acquiredDaysAgo) => {
      'id': id, 'tag': tag, 'name': name, 'description': null, 'asset_class_id': classId, 'serial_number': null, //
      'location': location, 'acquisition_date': _date(acquiredDaysAgo), 'cost': cost.toStringAsFixed(2), 'residual_value': '0.00',
      'method': 'reducing_balance', 'useful_life_months': 120, 'rate': '25.00',
      'accumulated_depreciation': accumulated.toStringAsFixed(2), 'status': status, 'funding': 'bank',
      'capitalised_at': status == 'draft' ? null : iso(acquiredDaysAgo), 'disposal_date': null, 'disposal_proceeds': null,
      'disposal_gain_loss': null, 'disposal_reason': null, 'book_value': cost - accumulated,
      'asset_class': {'id': classId, 'code': className.substring(0, 4).toUpperCase(), 'name': className},
      'custodian': _person(custodian), 'supplier': null,
      'events': [
        {'type': 'registered', 'event_date': _date(acquiredDaysAgo), 'to_location': location, 'to_custodian': _person(custodian), 'amount': cost.toStringAsFixed(2), 'user': _person(77)},
        if (status != 'draft') {'type': 'capitalised', 'event_date': _date(acquiredDaysAgo), 'amount': cost.toStringAsFixed(2), 'user': _person(77)},
      ],
      'schedule': [
        for (var m = 0; m < 4; m++)
          {'period': _period(-m - 1), 'opening': cost - accumulated, 'amount': (cost - accumulated) * .0208, 'closing': (cost - accumulated) * (1 - .0208 * (m + 1)), 'posted': false},
      ],
      'depreciation': [
        if (status == 'active')
          {'period': _period(1), 'opening_value': '${cost - accumulated + 1000}', 'amount': '1000.00', 'closing_value': '${cost - accumulated}', 'run': {'id': 3, 'number': 'DPR-2026-000003'}},
      ],
    };
    assets.addAll([
      asset(1, 'WC-PL-001', 'Krones bottling line 6,000 bph', 1, 'Plant & machinery', 'Mbezi factory', 64, 480000000, 56960460.49, 'active', 220),
      asset(2, 'WC-MV-001', 'Isuzu FVR delivery truck', 2, 'Motor vehicles', 'Mbezi factory', 9, 185000000, 27750000, 'active', 190),
      asset(3, 'WC-IT-001', 'Dell server, head office', 3, 'Computers & IT equipment', 'Head office, Kijitonyama', 2, 14500000, 1812500, 'active', 160),
      asset(4, 'WC-FF-003', 'Boardroom furniture', 4, 'Furniture & fittings', 'Head office, Kijitonyama', 2, 9800000, 0, 'draft', 5),
    ]);

    for (var n = 1; n <= 3; n++) {
      runs.add({
        'id': n, 'number': 'DPR-2026-${'$n'.padLeft(6, '0')}', 'period': _period(4 - n), 'run_date': _date((4 - n) * 30), //
        'total': (14200000.0 - n * 120000).toStringAsFixed(2), 'assets_count': 3, 'journal_entry_id': 55 + n,
        'creator': _person(62), 'journal': {'id': 55 + n, 'number': 'JE-2026-${'${55 + n}'.padLeft(6, '0')}'},
        'lines': [
          for (final a in assets.where((a) => a['status'] == 'active'))
            {'period': _period(4 - n), 'opening_value': '${a['book_value']}', 'amount': '${(a['book_value'] as double) * .02}', 'closing_value': '${(a['book_value'] as double) * .98}', 'asset': {'id': a['id'], 'tag': a['tag'], 'name': a['name']}},
        ],
      });
    }
    runs.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
  }

  /// "2026-10" for [monthsAgo] months back (negative: ahead).
  static String _period(int monthsAgo) {
    final now = DateTime.now();
    final d = DateTime(now.year, now.month - monthsAgo);
    return '${d.year}-${'${d.month}'.padLeft(2, '0')}';
  }

  Map<String, dynamic> _invoiceBrief(Map<String, dynamic> i) => {
    for (final k in ['id', 'number', 'supplier_invoice_number', 'invoice_date', 'due_date', 'total', 'amount_paid', 'status', 'outstanding', 'payment_status']) k: i[k],
  };

  /* ══════════════════════════════════════════════════════════ dispatch ══ */

  Map<String, dynamic> _page(List<Map<String, dynamic>> rows, Map<String, dynamic> query, [int perPage = 30]) {
    final page = int.tryParse('${query['page'] ?? ''}') ?? 1;
    final last = rows.isEmpty ? 1 : ((rows.length - 1) ~/ perPage) + 1;
    return {
      'current_page': page,
      'data': rows.skip((page - 1) * perPage).take(perPage).toList(),
      'last_page': last,
      'per_page': perPage,
      'total': rows.length,
    };
  }

  bool _like(Map<String, dynamic> row, String q, List<String> fields) =>
      q.isEmpty || fields.any((f) => '${row[f] ?? ''}'.toLowerCase().contains(q.toLowerCase()));

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> rows, Map<String, dynamic> query, List<String> fields) {
    final status = '${query['status'] ?? ''}';
    final q = '${query['q'] ?? ''}'.trim();
    return rows.where((r) => (status.isEmpty || r['status'] == status) && _like(r, q, fields)).toList();
  }

  Map<String, dynamic> _find(List<Map<String, dynamic>> rows, String id, String what) =>
      rows.firstWhere((r) => '${r['id']}' == id, orElse: () => throw ApiException(404, '$what not found.'));

  /// Answers one /erp request, or [unhandled]. [rest] is the path after
  /// /erp, split on '/'.
  Object? handle(
    String method,
    List<String> rest, {
    required List<String> perms,
    required List<String> modules,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
  }) {
    if (rest.isEmpty) return unhandled;
    void need(String permission) {
      if (!perms.contains(permission)) throw ApiException(403, 'Your role does not allow this.');
    }

    void module(String key, String label) {
      if (!modules.contains(key)) throw ApiException(403, 'The $label module is not switched on for your company.');
    }

    final head = rest.first;
    final get = method == 'GET';

    if (head == 'suppliers' && get) {
      module('procurement', 'procurement');
      need('suppliers.view');
      if (rest.length == 2) return {'data': _find(suppliers, rest[1], 'Supplier')};
      return _page(_filter(suppliers, query, ['name', 'code', 'phone']), query, 50);
    }

    if (head == 'procurement') {
      module('procurement', 'procurement');
      need('procurement.view');
      return _procurement(method, rest.skip(1).toList(), need, body, query);
    }

    if (head == 'finance' || head == 'journals' || head == 'trial-balance') {
      module('accounting', 'accounting');
      if (head == 'journals' && get) {
        need('accounting.view');
        if (rest.length == 2) return {'data': _find(journals, rest[1], 'Journal entry')};
        final source = '${query['source_type'] ?? ''}';
        final rows = _filter(journals, query, ['number', 'memo']).where((j) => source.isEmpty || j['source_type'] == source).toList();
        return _page(rows, query);
      }
      if (head == 'trial-balance' && get) {
        need('accounting.view');
        return {'data': _trialBalance()};
      }
      if (head == 'finance') return _finance(method, rest.skip(1).toList(), need, body, query);
    }

    if (head == 'assets' && get) {
      module('assets', 'assets');
      need('assets.view');
      final sub = rest.length > 1 ? rest[1] : '';
      switch (sub) {
        case 'overview':
          return {'data': _assetsOverview()};
        case 'register':
          if (rest.length == 3) return {'data': _find(assets, rest[2], 'Asset')};
          return _page(_filter(assets, query, ['tag', 'name']), query);
        case 'depreciation':
          if (rest.length == 3) return {'data': _find(runs, rest[2], 'Depreciation run')};
          return _page(runs, query, 24);
      }
    }
    return unhandled;
  }

  Object? _procurement(String method, List<String> r, void Function(String) need, Map<String, dynamic> body, Map<String, dynamic> query) {
    final get = method == 'GET';
    final what = r.isEmpty ? '' : r.first;
    switch (what) {
      case 'overview' when get:
        final posted = invoices.where((i) => i['status'] == 'posted');
        double owed(bool Function(Map<String, dynamic>) test) =>
            posted.where(test).fold(0, (s, i) => s + (i['outstanding'] as num).toDouble());
        final today = DateTime.now();
        return {
          'data': {
            'open_requisitions': requisitions.where((q) => ['submitted', 'approved', 'draft'].contains(q['status'])).length,
            'requisitions_awaiting_approval': requisitions.where((q) => q['status'] == 'submitted').length,
            'orders_awaiting_approval': orders.where((o) => o['status'] == 'submitted').length,
            'orders_to_receive': orders.where((o) => ['approved', 'sent', 'partially_received'].contains(o['status'])).length,
            'invoices_to_match': invoices.where((i) => ['draft', 'awaiting_approval', 'approved'].contains(i['status'])).length,
            'invoices_with_variance': invoices.where((i) => i['status'] == 'awaiting_approval').length,
            'payables_outstanding': owed((_) => true),
            'payables_overdue': owed((i) => DateTime.parse('${i['due_date']}'.substring(0, 10)).isBefore(today)),
            'payables_due_7_days': owed((i) {
              final due = DateTime.parse('${i['due_date']}'.substring(0, 10));
              return !due.isBefore(today) && due.isBefore(today.add(const Duration(days: 7)));
            }),
            'ordered_this_month': 3917600,
            'recent_orders': orders.take(6).toList(),
          },
        };
      case 'ageing' when get:
        return {'data': _ageing()};
      case 'lookups' when get:
        return {
          'data': {
            'products': [
              {'id': 1, 'sku': 'RM-PRF-28', 'name': 'PET preform 28g', 'cost_price': '95.00', 'unit': {'id': 2, 'code': 'PCS'}},
              {'id': 3, 'sku': 'PK-LBL-500', 'name': 'Label: 500ml', 'cost_price': '12.00', 'unit': {'id': 2, 'code': 'PCS'}},
              {'id': 4, 'sku': 'PK-SHR-24', 'name': 'Shrink film roll', 'cost_price': '5200.00', 'unit': {'id': 3, 'code': 'KG'}},
            ],
          },
        };
      case 'statement' when get && r.length == 2:
        return {'data': _statement(int.tryParse(r[1]) ?? 0)};
      case 'requisitions':
        if (get && r.length == 1) return _page(_filter(requisitions, query, ['number', 'justification']), query);
        if (get && r.length == 2) return {'data': _find(requisitions, r[1], 'Requisition')};
        if (method == 'POST' && r.length == 1) {
          need('procurement.request');
          return {'data': _storeRequisition(body)};
        }
        if (method == 'POST' && r.length == 3) {
          final q = _find(requisitions, r[1], 'Requisition');
          return _decide(q, r[2], need, body, 'procurement.request');
        }
      case 'orders':
        if (get && r.length == 1) {
          final status = '${query['status'] ?? ''}';
          final rows = status == 'to_receive'
              ? orders.where((o) => ['approved', 'sent', 'partially_received'].contains(o['status'])).toList()
              : _filter(orders, query, ['number']);
          return _page(status == 'to_receive' ? rows.where((o) => _like(o, '${query['q'] ?? ''}', ['number'])).toList() : rows, query);
        }
        if (get && r.length == 2) return {'data': _find(orders, r[1], 'Purchase order')};
        if (method == 'POST' && r.length == 3) return _decide(_find(orders, r[1], 'Purchase order'), r[2], need, body, 'procurement.order');
      case 'invoices':
        if (get && r.length == 1) {
          final status = '${query['status'] ?? ''}';
          final q = '${query['q'] ?? ''}'.trim();
          final rows = invoices.where((i) {
            final ok = switch (status) {
              '' => true,
              'to_match' => ['draft', 'awaiting_approval', 'approved'].contains(i['status']),
              'unpaid' => i['status'] == 'posted' && (i['outstanding'] as num) > 0,
              _ => i['status'] == status,
            };
            return ok && _like(i, q, ['number', 'supplier_invoice_number']);
          }).toList();
          return _page(rows, query);
        }
        if (get && r.length == 2) return {'data': _find(invoices, r[1], 'Supplier invoice')};
        final inv = _find(invoices, r.length > 1 ? r[1] : '', 'Supplier invoice');
        if (r.length == 3 && r[2] == 'voucher') {
          if (get) return {'data': vouchers[inv['id']]};
          need('procurement.pay');
          if (inv['status'] != 'posted' || (inv['outstanding'] as num) <= 0) {
            throw ApiException(422, 'Only a posted invoice with money still owed can be sent for payment.');
          }
          if (vouchers[inv['id']] case final open?) {
            throw ApiException(422, 'Voucher ${open['number']} is already on its way for this invoice.');
          }
          final id = _nextVoucher++;
          final v = {'id': id, 'number': 'PV-2026-${'$id'.padLeft(6, '0')}', 'status': 'draft'};
          vouchers[inv['id'] as int] = v;
          return {'data': {'id': id, 'number': v['number']}};
        }
        if (method == 'POST' && r.length == 3 && r[2] == 'approve') {
          need('procurement.approve');
          if (inv['status'] != 'awaiting_approval') throw ApiException(422, 'Only an invoice with a variance awaiting approval can be approved.');
          inv['status'] = 'approved';
          inv['variance_approver'] = _person(2);
          inv['variance_approved_at'] = iso(0);
          return {'message': 'Variance on ${inv['number']} approved; it can now be posted.', 'data': inv};
        }
      case 'payments':
        if (get && r.length == 1) return _page(_filter(payments, query, ['number', 'reference']), query);
        if (get && r.length == 2) return {'data': _find(payments, r[1], 'Supplier payment')};
    }
    return unhandled;
  }

  /// Submit, approve, reject or cancel a requisition or an order.
  Map<String, dynamic> _decide(Map<String, dynamic> doc, String action, void Function(String) need, Map<String, dynamic> body, String prepare) {
    final number = doc['number'];
    final comment = '${body['comment'] ?? ''}'.trim();
    switch (action) {
      case 'submit':
        need(prepare);
        if (doc['status'] != 'draft') throw ApiException(422, 'Only a draft can be submitted.');
        doc['status'] = 'submitted';
        doc['submitted_at'] = iso(0);
        return {'message': '$number submitted for approval.', 'data': doc};
      case 'approve':
        need('procurement.approve');
        if (doc['status'] != 'submitted') throw ApiException(422, 'Only a submitted document can be approved.');
        final approvals = (doc['approvals'] as List).cast<Map<String, dynamic>>()
          ..add({'level': (doc['approvals'] as List).length + 1, 'decision': 'approved', 'comment': comment.isEmpty ? null : comment, 'created_at': iso(0), 'user': _person(2)});
        if (approvals.where((a) => a['decision'] == 'approved').length >= (doc['approvals_required'] as int)) {
          doc['status'] = 'approved';
          return {'message': '$number approved.', 'data': doc};
        }
        return {'message': 'First approval recorded; $number now needs a senior approver.', 'data': doc};
      case 'reject':
        need('procurement.approve');
        if (comment.length < 3) {
          throw ApiException(422, 'Give a reason of at least 3 characters.', {'comment': ['Give a reason of at least 3 characters.']});
        }
        (doc['approvals'] as List).add({'level': (doc['approvals'] as List).length + 1, 'decision': 'rejected', 'comment': comment, 'created_at': iso(0), 'user': _person(2)});
        doc['status'] = 'rejected';
        return {'message': '$number rejected.', 'data': doc};
    }
    throw ApiException(404, 'No mock route for $action.');
  }

  Map<String, dynamic> _storeRequisition(Map<String, dynamic> body) {
    final why = '${body['justification'] ?? ''}'.trim();
    if (why.length < 5) {
      throw ApiException(422, 'The justification field must be at least 5 characters.', {'justification': ['The justification field must be at least 5 characters.']});
    }
    final raw = ((body['lines'] as List?) ?? const []).whereType<Map>().toList();
    if (raw.isEmpty) throw ApiException(422, 'The lines field is required.', {'lines': ['The lines field is required.']});
    final id = _nextRequisition++;
    final lines = [
      for (final (n, l) in raw.indexed)
        {
          'id': id * 100 + n, 'line_type': l['line_type'], 'product_id': l['product_id'], //
          'description': l['description'] ?? 'Product ${l['product_id']}',
          'quantity': '${l['quantity']}', 'estimated_unit_price': '${l['estimated_unit_price'] ?? 0}',
          'amount': ((num.tryParse('${l['quantity']}') ?? 0) * (num.tryParse('${l['estimated_unit_price'] ?? 0}') ?? 0)).toStringAsFixed(2),
          'product': null, 'expense_account': null,
        },
    ];
    final r = {
      'id': id, 'number': 'PRQ-2026-${'$id'.padLeft(6, '0')}', 'requested_by': 2, 'needed_by': body['needed_by'], //
      'justification': why, 'status': 'draft', 'approvals_required': 1,
      'total': lines.fold<double>(0, (s, l) => s + double.parse('${l['amount']}')).toStringAsFixed(2),
      'submitted_at': null, 'created_at': iso(0), 'lines_count': lines.length, 'department': null,
      'requester': _person(2), 'lines': lines, 'approvals': <Map<String, dynamic>>[], 'orders': <Map<String, dynamic>>[],
    };
    requisitions.insert(0, r);
    return r;
  }

  Map<String, dynamic> _ageing() {
    const buckets = ['current', 'days_1_30', 'days_31_60', 'days_61_90', 'over_90'];
    final today = DateTime.now();
    final rows = <int, Map<String, dynamic>>{};
    final totals = {for (final b in [...buckets, 'total']) b: 0.0};
    for (final i in invoices.where((i) => i['status'] == 'posted' && (i['outstanding'] as num) > 0)) {
      final late = today.difference(DateTime.parse('${i['due_date']}'.substring(0, 10))).inDays;
      final bucket = late <= 0 ? 'current' : late <= 30 ? 'days_1_30' : late <= 60 ? 'days_31_60' : late <= 90 ? 'days_61_90' : 'over_90';
      final owed = (i['outstanding'] as num).toDouble();
      final row = rows[i['supplier_id'] as int] ??= {'supplier': i['supplier'], for (final b in [...buckets, 'total']) b: 0.0};
      row[bucket] = (row[bucket] as double) + owed;
      row['total'] = (row['total'] as double) + owed;
      totals[bucket] = totals[bucket]! + owed;
      totals['total'] = totals['total']! + owed;
    }
    return {'as_of': _day(0), 'buckets': buckets, 'rows': rows.values.toList(), 'totals': totals};
  }

  Map<String, dynamic> _statement(int supplierId) {
    final s = suppliers.firstWhere((s) => s['id'] == supplierId, orElse: () => throw ApiException(404, 'Supplier not found.'));
    final entries = <Map<String, dynamic>>[
      for (final i in invoices.where((i) => i['supplier_id'] == supplierId && i['status'] == 'posted'))
        {'date': '${i['invoice_date']}'.substring(0, 10), 'type': 'invoice', 'id': i['id'], 'number': i['number'], 'reference': i['supplier_invoice_number'], 'due_date': '${i['due_date']}'.substring(0, 10), 'debit': 0, 'credit': double.parse('${i['total']}')},
      for (final p in payments.where((p) => p['supplier_id'] == supplierId))
        {'date': '${p['payment_date']}'.substring(0, 10), 'type': 'payment', 'id': p['id'], 'number': p['number'], 'reference': p['reference'], 'due_date': null, 'debit': double.parse('${p['amount']}'), 'credit': 0},
    ]..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    var balance = 0.0;
    for (final e in entries) {
      balance += (e['credit'] as num) - (e['debit'] as num);
      e['balance'] = balance;
    }
    return {
      'supplier': s, 'from': _day(90), 'to': _day(0), 'opening_balance': 0, 'entries': entries, //
      'total_invoiced': entries.fold<double>(0, (t, e) => t + (e['credit'] as num)),
      'total_paid': entries.fold<double>(0, (t, e) => t + (e['debit'] as num)),
      'closing_balance': balance,
    };
  }

  Object? _finance(String method, List<String> r, void Function(String) need, Map<String, dynamic> body, Map<String, dynamic> query) {
    final get = method == 'GET';
    final what = r.isEmpty ? '' : r.first;
    if (what == 'statements') {
      need('finance.statements');
      return switch (r.length > 1 ? r[1] : '') {
        'profit-and-loss' => {'data': _profitAndLoss(query)},
        'balance-sheet' => {'data': _balanceSheet()},
        'budget-vs-actual' => {'data': _budget()},
        _ => unhandled,
      };
    }
    need('finance.view');
    switch (what) {
      case 'overview' when get:
        final cash = [
          {'account_id': 1, 'code': '1100', 'name': 'Cash on hand', 'bank_account_id': null, 'type': 'cash', 'is_active': true, 'balance': 14102298},
          for (final b in banks)
            {'account_id': b['account_id'], 'code': (b['account'] as Map)['code'], 'name': b['name'], 'bank_account_id': b['id'], 'type': b['type'], 'is_active': true, 'balance': b['balance']},
        ];
        return {
          'data': {
            'cash': cash,
            'cash_total': cash.fold<double>(0, (s, c) => s + (c['balance'] as num)),
            'receivables': 23503604,
            'payables': invoices.where((i) => i['status'] == 'posted').fold<double>(0, (s, i) => s + (i['outstanding'] as num)),
            'month': {'from': _day(DateTime.now().day - 1), 'to': _day(0), 'totals': _plTotals(1), 'prior_totals': _plTotals(1.4)},
            'periods': {'current': _period(0), 'current_closed': false, 'last_closed': _period(3)},
            'drafts': {'cashbook': cashbook.where((e) => e['status'] == 'draft').length, 'transfers': 0},
            'open_reconciliations': [
              {'id': 2, 'number': 'BRC-2026-000002', 'bank_account_id': 1, 'statement_date': _date(12), 'bank_account': {'id': 1, 'name': 'NMB Bank: operations'}},
            ],
            'recent': cashbook.take(6).toList(),
          },
        };
      case 'bank-accounts' when get:
        if (r.length == 1) return {'data': banks};
        final b = _find(banks, r[1], 'Bank account');
        final lines = <Map<String, dynamic>>[];
        var running = (b['balance'] as num).toDouble();
        for (final e in cashbook.where((e) => e['bank_account_id'] == b['id'] && e['status'] == 'posted')) {
          final amount = double.parse('${e['amount']}');
          running -= e['type'] == 'receipt' ? amount : -amount;
        }
        final opening = running;
        for (final e in cashbook.reversed.where((e) => e['bank_account_id'] == b['id'] && e['status'] == 'posted')) {
          final amount = double.parse('${e['amount']}');
          final receipt = e['type'] == 'receipt';
          running += receipt ? amount : -amount;
          lines.add({
            'id': e['id'], 'debit': receipt ? '$amount' : '0.00', 'credit': receipt ? '0.00' : '$amount', //
            'description': '${e['description']} · ${e['counterparty']}', 'journal_entry_id': (e['journal'] as Map?)?['id'],
            'entry_date': '${e['entry_date']}'.substring(0, 10), 'number': (e['journal'] as Map?)?['number'] ?? e['number'],
            'reconciled': false, 'balance': running,
          });
        }
        return {
          'data': {...b, 'statement': {'from': _day(90), 'to': _day(0), 'opening': opening, 'closing': running, 'lines': lines}, 'reconciliations': <Object>[]},
        };
      case 'cashbook':
        if (get && r.length == 2 && r[1] == 'accounts') {
          return {
            'data': [
              {'id': 19, 'code': '4900', 'name': 'Other income', 'type': 'income'},
              {'id': 28, 'code': '6300', 'name': 'Rent', 'type': 'expense'},
              {'id': 27, 'code': '6400', 'name': 'Utilities', 'type': 'expense'},
              {'id': 29, 'code': '6640', 'name': 'Professional fees', 'type': 'expense'},
              {'id': 30, 'code': '6650', 'name': 'Communication & internet', 'type': 'expense'},
              {'id': 40, 'code': '3200', 'name': 'Owner capital contributions', 'type': 'equity'},
            ],
          };
        }
        if (get && r.length == 1) {
          final type = '${query['type'] ?? ''}';
          final rows = _filter(cashbook, query, ['number', 'description', 'counterparty', 'reference']).where((e) => type.isEmpty || e['type'] == type).toList();
          final posted = rows.where((e) => e['status'] == 'posted');
          double sum(String t) => posted.where((e) => e['type'] == t).fold(0, (s, e) => s + double.parse('${e['amount']}'));
          return {..._page(rows, query), 'totals': {'receipts': sum('receipt'), 'payments': sum('payment')}};
        }
        if (get && r.length == 2) return {'data': _find(cashbook, r[1], 'Cashbook entry')};
        if (method == 'POST' && r.length == 1) {
          need('finance.cashbook');
          return {'data': _storeCashbook(body)};
        }
        if (method == 'POST' && r.length == 3) {
          need('finance.cashbook');
          final e = _find(cashbook, r[1], 'Cashbook entry');
          if (e['status'] != 'draft') throw ApiException(422, 'Only a draft can be ${r[2] == 'post' ? 'posted' : 'cancelled'}.');
          if (r[2] == 'post') {
            final id = _nextJournal++;
            e['status'] = 'posted';
            e['posted_at'] = iso(0);
            e['poster'] = _person(2);
            e['journal'] = {'id': id, 'number': 'JE-2026-${'$id'.padLeft(6, '0')}'};
            final bank = banks.firstWhere((b) => b['id'] == e['bank_account_id']);
            final amount = double.parse('${e['amount']}');
            bank['balance'] = (bank['balance'] as num) + (e['type'] == 'receipt' ? amount : -amount);
            return {'message': '${e['number']} posted.', 'data': e};
          }
          if (r[2] == 'cancel') {
            e['status'] = 'cancelled';
            return {'message': 'Draft cancelled.', 'data': e};
          }
        }
    }
    return unhandled;
  }

  Map<String, dynamic> _storeCashbook(Map<String, dynamic> body) {
    final errors = <String, List<String>>{};
    if ((num.tryParse('${body['amount'] ?? ''}') ?? 0) <= 0) errors['amount'] = ['The amount must be at least 0.01.'];
    if ('${body['description'] ?? ''}'.trim().isEmpty) errors['description'] = ['The description field is required.'];
    final bank = banks.where((b) => b['id'] == body['bank_account_id']).firstOrNull;
    if (bank == null) errors['bank_account_id'] = ['The selected bank account is invalid.'];
    if (errors.isNotEmpty) throw ApiException(422, errors.values.first.first, errors);
    final id = _nextCashbook++;
    final receipt = body['type'] == 'receipt';
    final e = {
      'id': id, 'number': '${receipt ? 'CBR' : 'CBP'}-2026-${'$id'.padLeft(6, '0')}', 'type': receipt ? 'receipt' : 'payment', //
      'entry_date': '${body['entry_date']}T00:00:00.000000Z', 'bank_account_id': bank!['id'], 'account_id': body['account_id'],
      'amount': (num.parse('${body['amount']}')).toStringAsFixed(2), 'counterparty': body['counterparty'],
      'reference': body['reference'], 'description': '${body['description']}'.trim(), 'status': 'draft', 'created_by': 2,
      'posted_at': null, 'reversal_reason': null, 'bank_account': {'id': bank['id'], 'name': bank['name']},
      'account': {'id': body['account_id'], 'code': '', 'name': 'Ledger account ${body['account_id']}'},
      'creator': _person(2), 'poster': null, 'journal': null,
    };
    cashbook.insert(0, e);
    return e;
  }

  Map<String, dynamic> _plTotals(double scale) {
    final income = 5021200 * scale, cos = 2166427.05 * scale, opex = 6505876 * scale;
    return {
      'income': income, 'cost_of_sales': cos, 'gross_profit': income - cos, //
      'operating_expenses': opex, 'expenses': cos + opex, 'net_profit': income - cos - opex,
    };
  }

  Map<String, dynamic> _profitAndLoss(Map<String, dynamic> query) {
    Map<String, dynamic> row(String code, String name, String section, double amount) =>
        {'account_id': int.parse(code), 'code': code, 'name': name, 'type': section == 'income' ? 'income' : 'expense', 'section': section, 'amount': amount, 'prior': amount * 1.4};
    return {
      'from': query['from'] ?? _day(DateTime.now().day - 1), 'to': query['to'] ?? _day(0), //
      'prior_from': _day(40), 'prior_to': _day(DateTime.now().day),
      'rows': [
        row('4000', 'Sales revenue', 'income', 4271200),
        row('4900', 'Other income', 'income', 750000),
        row('5000', 'Cost of goods sold', 'cost_of_sales', 2166427.05),
        row('6100', 'Salaries and wages', 'operating_expenses', 3000000),
        row('6300', 'Rent', 'operating_expenses', 2100000),
        row('6400', 'Utilities', 'operating_expenses', 1405876),
      ],
      'totals': _plTotals(1),
      'prior_totals': _plTotals(1.4),
    };
  }

  Map<String, dynamic> _balanceSheet() {
    Map<String, dynamic> row(String code, String name, String type, String section, double amount) =>
        {'account_id': int.parse(code), 'code': code, 'name': name, 'type': type, 'section': section, 'amount': amount};
    final rows = [
      row('1100', 'Cash on hand', 'asset', 'current_assets', 14102298),
      row('1210', 'NMB Bank: operations', 'asset', 'current_assets', 545887282.04),
      row('1300', 'Accounts receivable', 'asset', 'current_assets', 23503604),
      row('1500', 'Inventory', 'asset', 'current_assets', 46780865.81),
      row('1520', 'Plant & machinery', 'asset', 'non_current_assets', 423039539.51),
      row('1530', 'Motor vehicles', 'asset', 'non_current_assets', 157250000),
      row('2100', 'Accounts payable', 'liability', 'current_liabilities', 119337610),
      row('2200', 'VAT payable', 'liability', 'current_liabilities', 12400000),
      row('3000', 'Share capital', 'equity', 'equity', 1000000000),
    ];
    double sum(String s) => rows.where((r) => r['section'] == s).fold(0, (t, r) => t + (r['amount'] as double));
    final assets = sum('current_assets') + sum('non_current_assets');
    final liabilities = sum('current_liabilities');
    final earnings = assets - liabilities - sum('equity');
    return {
      'as_of': _day(0), 'rows': rows, 'current_earnings': earnings, //
      'totals': {
        'current_assets': sum('current_assets'), 'non_current_assets': sum('non_current_assets'), 'assets': assets,
        'current_liabilities': liabilities, 'non_current_liabilities': 0, 'liabilities': liabilities,
        'equity': sum('equity') + earnings, 'liabilities_and_equity': assets,
      },
      'balanced': true,
    };
  }

  Map<String, dynamic> _budget() {
    Map<String, dynamic> row(String code, String name, String type, double budget, double actual) =>
        {'account_id': int.parse(code), 'code': code, 'name': name, 'type': type, 'budget': budget, 'actual': actual, 'variance': actual - budget, 'used_percent': budget == 0 ? null : (actual / budget * 1000).round() / 10};
    final rows = [
      row('4000', 'Sales revenue', 'income', 2630000000, 2105000000),
      row('4900', 'Other income', 'income', 15600000, 12750000),
      row('6100', 'Salaries and wages', 'expense', 360000000, 300000000),
      row('6300', 'Rent', 'expense', 54000000, 49500000),
      row('6400', 'Utilities', 'expense', 48000000, 52310000),
    ];
    double sum(String type, String key) => rows.where((r) => r['type'] == type).fold(0, (t, r) => t + (r[key] as double));
    return {
      'fiscal_year': DateTime.now().year, 'through_month': DateTime.now().month, 'has_budget': true, //
      'from': '${DateTime.now().year}-01-01', 'to': _day(0), 'rows': rows,
      'totals': {
        'income_budget': sum('income', 'budget'), 'income_actual': sum('income', 'actual'),
        'expense_budget': sum('expense', 'budget'), 'expense_actual': sum('expense', 'actual'),
        'net_budget': sum('income', 'budget') - sum('expense', 'budget'), 'net_actual': sum('income', 'actual') - sum('expense', 'actual'),
      },
    };
  }

  Map<String, dynamic> _trialBalance() {
    Map<String, dynamic> row(String code, String name, String type, double debit, double credit) =>
        {'account_id': int.parse(code), 'code': code, 'name': name, 'type': type, 'debit': debit, 'credit': credit, 'balance': debit - credit};
    final rows = [
      row('1100', 'Cash on hand', 'asset', 35150000, 21047702),
      row('1210', 'NMB Bank: operations', 'asset', 702000000, 156112717.96),
      row('2100', 'Accounts payable', 'liability', 12000000, 131337610),
      row('3000', 'Share capital', 'equity', 0, 1000000000),
      row('4000', 'Sales revenue', 'income', 0, 34000000),
      row('6300', 'Rent', 'expense', 49500000, 0),
      row('1520', 'Plant & machinery', 'asset', 543848029.96, 0),
    ];
    final debit = rows.fold<double>(0, (s, r) => s + (r['debit'] as double));
    final credit = rows.fold<double>(0, (s, r) => s + (r['credit'] as double));
    return {'rows': rows, 'total_debit': debit, 'total_credit': credit, 'balanced': (debit - credit).abs() < .01};
  }

  Map<String, dynamic> _assetsOverview() {
    final live = assets.where((a) => a['status'] == 'active');
    final cost = live.fold<double>(0, (s, a) => s + double.parse('${a['cost']}'));
    final acc = live.fold<double>(0, (s, a) => s + double.parse('${a['accumulated_depreciation']}'));
    final classes = <int, Map<String, dynamic>>{};
    for (final a in live) {
      final c = a['asset_class'] as Map<String, dynamic>;
      final row = classes[c['id'] as int] ??= {'id': c['id'], 'code': c['code'], 'name': c['name'], 'count': 0, 'cost': 0.0, 'book_value': 0.0};
      row['count'] = (row['count'] as int) + 1;
      row['cost'] = (row['cost'] as double) + double.parse('${a['cost']}');
      row['book_value'] = (row['book_value'] as double) + (a['book_value'] as double);
    }
    return {
      'counts': {for (final s in ['draft', 'active', 'disposed']) s: assets.where((a) => a['status'] == s).length},
      'cost': cost, 'accumulated': acc, 'book_value': cost - acc, 'by_class': classes.values.toList(), //
      'latest_run': runs.first, 'next_period': _period(0), 'next_due': 13861189.69, 'disposed_this_year': <Object>[],
    };
  }
}
