import '../services/api_service.dart';

/// The in-app stand-in for the Sales and Dispatch endpoints
/// (/erp/sales/..., /erp/dispatch/..., /erp/customers), answering the same
/// paths with the same JSON shapes as the Laravel controllers
/// (Erp\Sales\*, Erp\CustomerController). Hooked into [MockErp.handle].
///
/// Every step really moves the order: approving, invoicing, recording and
/// verifying a payment, loading, the gate and proof of delivery, so a flow
/// tried offline reads back the way it would against the server.
class MockSales {
  MockSales() {
    _seed();
  }

  /// Returned by [handle] for a path this fixture does not answer.
  static const unhandled = Object();

  /// Everything Sales and Dispatch let a person do (a company
  /// administrator holds all of it).
  static const permissions = [
    'sales.view', 'sales.quote', 'sales.order', 'sales.approve', 'sales.invoice', //
    'sales.receipt', 'sales.return', 'sales.pricing',
    'dispatch.view', 'dispatch.verify', 'dispatch.load', 'dispatch.deliver', 'dispatch.gatepass', 'dispatch.resolve',
  ];

  static const _tax = 18.0;

  final customers = <Map<String, dynamic>>[];
  final quotations = <Map<String, dynamic>>[];
  final orders = <Map<String, dynamic>>[];
  final invoices = <Map<String, dynamic>>[];
  final receipts = <Map<String, dynamic>>[];
  final loadings = <Map<String, dynamic>>[];
  final _seq = <String, int>{};
  int _nextLine = 100;

  static const _products = {
    5: {'id': 5, 'sku': 'FG-W500-24', 'name': 'Watercom 500ml × 24', 'type': 'finished_good', 'sale_price': '8500.00', 'unit': 'CTN'},
    6: {'id': 6, 'sku': 'FG-W1500-12', 'name': 'Watercom 1.5L × 12', 'type': 'finished_good', 'sale_price': '10500.00', 'unit': 'CTN'},
    7: {'id': 7, 'sku': 'FG-W19L', 'name': 'Watercom 19L dispenser jar', 'type': 'finished_good', 'sale_price': '6000.00', 'unit': 'PCS'},
  };

  static const _warehouses = [
    {'id': 3, 'code': 'ARU', 'name': 'Arusha depot'},
    {'id': 1, 'code': 'MAIN', 'name': 'Factory store Mbezi'},
    {'id': 2, 'code': 'FGW', 'name': 'Finished goods warehouse'},
  ];

  static const _accounts = [
    {'id': 1, 'code': '1100', 'name': 'Cash on hand'},
    {'id': 3, 'code': '1200', 'name': 'Bank'},
    {'id': 74, 'code': '1230', 'name': 'M-Pesa till 556677'},
  ];

  /// Wholesale prices, for the customers on that list.
  static const _wholesale = {5: 8000.0, 6: 9900.0, 7: 5600.0};

  static String _iso(int daysAgo) => DateTime.now().subtract(Duration(days: daysAgo)).toUtc().toIso8601String();
  static String _day(int daysAgo) => '${_iso(daysAgo).substring(0, 10)}T00:00:00.000000Z';
  static String _money(num v) => v.toStringAsFixed(2);
  static double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

  String _number(String prefix) {
    final n = (_seq[prefix] ?? 0) + 1;
    _seq[prefix] = n;
    return '$prefix-${DateTime.now().year}-${'$n'.padLeft(6, '0')}';
  }

  Map<String, dynamic> _customer(int id, String code, String name, String city, double limit, int days, {String? list, String? address, String? phone}) => {
    'id': id, 'company_id': 1, 'code': code, 'name': name, 'customer_group': null, 'contact_person': null,
    'phone': phone, 'email': null, 'tin': null, 'address': address, 'city': city,
    'credit_limit': _money(limit), 'payment_terms_days': days, 'requires_prepayment': limit == 0,
    'price_list': list, 'custom_fields': null, 'is_active': true,
  };

  Map<String, dynamic> _brief(Map<String, dynamic> c) =>
      {'id': c['id'], 'code': c['code'], 'name': c['name'], 'requires_prepayment': c['requires_prepayment'], 'phone': c['phone'], 'address': c['address'], 'city': c['city']};

  Map<String, dynamic> _cust(dynamic id) => customers.firstWhere((c) => c['id'] == id);

  double _price(int customerId, int productId) {
    final c = _cust(customerId);
    if (c['price_list'] == 'WHOLESALE') return _wholesale[productId] ?? _n(_products[productId]!['sale_price']);
    return _n(_products[productId]!['sale_price']);
  }

  Map<String, dynamic> _productJson(int id) {
    final p = _products[id]!;
    return {'id': id, 'sku': p['sku'], 'name': p['name'], 'unit_id': 1, 'track_batches': true, 'unit': {'id': 1, 'code': p['unit']}};
  }

  /// One priced line, its amounts worked out the way SalesPricing does.
  Map<String, dynamic> _line(int productId, double qty, double price, {double discount = 0}) {
    final sub = qty * price;
    final disc = sub * discount / 100;
    final tax = (sub - disc) * _tax / 100;
    return {
      'id': _nextLine++, 'product_id': productId, 'description': null,
      'unit_price': _money(price), 'discount_percent': _money(discount), 'tax_rate': _money(_tax),
      'line_subtotal': _money(sub), 'line_discount': _money(disc), 'line_tax': _money(tax), 'line_total': _money(sub - disc + tax),
      'product': _productJson(productId),
    };
  }

  void _total(Map<String, dynamic> doc) {
    final lines = (doc['lines'] as List).cast<Map<String, dynamic>>();
    double sum(String k) => lines.fold(0.0, (s, l) => s + _n(l[k]));
    doc['subtotal'] = _money(sum('line_subtotal'));
    doc['discount_total'] = _money(sum('line_discount'));
    doc['tax_total'] = _money(sum('line_tax'));
    doc['total'] = _money(sum('line_total'));
  }

  Map<String, dynamic> _order(int customer, String status, List<(int, double)> items, {int daysAgo = 2, bool approved = false}) {
    final id = orders.length + 1;
    final prepay = _cust(customer)['requires_prepayment'] == true;
    final o = <String, dynamic>{
      'id': id, 'number': _number('SO'), 'customer_id': customer, 'quotation_id': null, 'warehouse_id': null,
      'order_date': _day(daysAgo), 'required_date': null, 'status': status,
      'payment_mode': approved ? (prepay ? 'prepayment' : 'credit') : null,
      'delivery_address': _cust(customer)['address'], 'notes': null, 'policy_check': null, 'override_reason': null,
      'submitted_at': status == 'draft' ? null : _iso(daysAgo), 'approved_at': approved ? _iso(daysAgo) : null,
      'payment_verified_at': approved && prepay && status != 'awaiting_payment' ? _iso(daysAgo) : null,
      'rejection_reason': null, 'created_by': 63, 'created_at': _iso(daysAgo),
      'lines': [
        for (final (p, q) in items)
          {
            ..._line(p, q, _price(customer, p)),
            'sales_order_id': id, 'quantity_ordered': q.toStringAsFixed(3), 'quantity_approved': approved ? q.toStringAsFixed(3) : null,
            'quantity_loaded': '0.000', 'quantity_received': '0.000', 'quantity_invoiced': '0.000',
          },
      ],
    };
    _total(o);
    orders.add(o);
    return o;
  }

  Map<String, dynamic> _invoice(Map<String, dynamic> order, {String status = 'posted', int daysAgo = 2, int? loadingId, double paid = 0}) {
    final customer = _cust(order['customer_id']);
    final lines = [
      for (final l in (order['lines'] as List).cast<Map<String, dynamic>>())
        {
          ..._line(l['product_id'] as int, _n(l['quantity_approved'] ?? l['quantity_ordered']), _n(l['unit_price'])),
          'sales_order_line_id': l['id'], 'quantity': _n(l['quantity_approved'] ?? l['quantity_ordered']).toStringAsFixed(3), 'quantity_credited': '0.000',
        },
    ];
    for (final l in (order['lines'] as List).cast<Map<String, dynamic>>()) {
      l['quantity_invoiced'] = _n(l['quantity_approved'] ?? l['quantity_ordered']).toStringAsFixed(3);
    }
    final days = customer['payment_terms_days'] as int;
    final inv = <String, dynamic>{
      'id': invoices.length + 1, 'number': _number('INV'), 'customer_id': customer['id'], 'sales_order_id': order['id'],
      'loading_order_id': loadingId, 'invoice_date': _day(daysAgo), 'due_date': _day(daysAgo - days), 'status': status,
      'amount_paid': _money(paid), 'amount_credited': '0.00', 'notes': null,
      'posted_at': status == 'posted' ? _iso(daysAgo) : null, 'created_at': _iso(daysAgo), 'lines': lines,
      'creator': {'id': 62, 'name': 'Grace Mushi'}, 'poster': status == 'posted' ? {'id': 62, 'name': 'Grace Mushi'} : null,
    };
    _total(inv);
    invoices.add(inv);
    return inv;
  }

  Map<String, dynamic> _loading(Map<String, dynamic> order, String status, {int daysAgo = 1, bool shortBy = false}) {
    final id = loadings.length + 1;
    final loaded = status != 'open';
    final out = status == 'dispatched' || status == 'delivered';
    final lo = <String, dynamic>{
      'id': id, 'number': _number('LO'), 'sales_order_id': order['id'], 'customer_id': order['customer_id'], 'warehouse_id': 2,
      'status': status, 'planned_date': _day(daysAgo), 'vehicle_number': 'T 233 EAB', 'driver_name': 'Elia Mwakyusa',
      'destination': _cust(order['customer_id'])['address'], 'notes': null,
      'loaded_at': loaded ? _iso(daysAgo) : null, 'loader': loaded ? {'id': 60, 'name': 'Neema Swai'} : null,
      'driver_confirmed_name': out ? 'Elia Mwakyusa' : null, 'driver_confirmed_at': out ? _iso(daysAgo) : null,
      'security_confirmed_name': out ? 'Omari Selemani (gate)' : null, 'security_confirmed_at': out ? _iso(daysAgo) : null,
      'delivery_note_number': out ? _number('DN') : null, 'delivery_note_issued_at': out ? _iso(daysAgo) : null,
      'gate_pass_number': out ? _number('GP') : null, 'gate_pass_issued_at': out ? _iso(daysAgo) : null,
      'gate_pass_issuer': out ? {'id': 61, 'name': 'Peter Lema'} : null,
      'received_by_name': status == 'delivered' ? 'Abdul Karim' : null, 'received_date': status == 'delivered' ? _day(daysAgo) : null,
      'delivery_remark': shortBy ? 'Three cartons crushed in transit; customer refused them.' : null,
      'pod_recorded_at': status == 'delivered' ? _iso(daysAgo) : null,
      'discrepancy_status': shortBy ? 'open' : null, 'discrepancy_note': null, 'discrepancy_resolved_at': null,
      'stock_document': loaded ? {'id': 900 + id, 'number': 'ISS-${DateTime.now().year}-0000$id', 'status': 'posted'} : null,
      'return_document': null, 'creator': {'id': 10, 'name': 'Baraka Mollel'}, 'created_at': _iso(daysAgo),
      'lines': [
        for (final l in (order['lines'] as List).cast<Map<String, dynamic>>())
          {
            'id': _nextLine++, 'sales_order_line_id': l['id'], 'product_id': l['product_id'],
            'quantity_ordered': l['quantity_ordered'], 'quantity_approved': l['quantity_approved'],
            'quantity_loaded': loaded ? l['quantity_approved'] : null,
            'quantity_received': status == 'delivered' ? _money(_n(l['quantity_approved']) - (shortBy ? 3 : 0)) : null,
            'product': _productJson(l['product_id'] as int),
          },
      ],
    };
    for (final l in (order['lines'] as List).cast<Map<String, dynamic>>()) {
      if (loaded) l['quantity_loaded'] = l['quantity_approved'];
      if (status == 'delivered') l['quantity_received'] = _money(_n(l['quantity_approved']) - (shortBy ? 3 : 0));
    }
    loadings.add(lo);
    return lo;
  }

  void _seed() {
    customers.addAll([
      _customer(1, 'CUS-0001', 'Shoppers Supermarket Masaki', 'Dar es Salaam', 15000000, 30),
      _customer(2, 'CUS-0002', 'Kariakoo Wholesalers Ltd', 'Dar es Salaam', 25000000, 14, list: 'WHOLESALE'),
      _customer(3, 'CUS-0003', 'Mama Ntilie Kiosk Network', 'Dar es Salaam', 0, 0),
      _customer(4, 'CUS-0004', 'Serena Hotel Dar es Salaam', 'Dar es Salaam', 8000000, 30, list: 'HORECA'),
      _customer(5, 'CUS-0005', 'Arusha Distributors', 'Arusha', 20000000, 21, list: 'WHOLESALE', address: 'Sokoine Road, Arusha', phone: '+255 754 221 908'),
    ]);

    _order(2, 'draft', [(5, 120)], daysAgo: 0);
    _order(4, 'submitted', [(5, 80), (7, 20)], daysAgo: 1);
    final prepaid = _order(3, 'awaiting_payment', [(5, 30)], daysAgo: 2, approved: true);
    final inv1 = _invoice(prepaid, daysAgo: 2);
    receipts.add({
      'id': 1, 'number': _number('RCT'), 'customer_id': 3, 'account_id': 3, 'receipt_date': _day(1), 'amount': inv1['total'],
      'method': 'mobile_money', 'reference': 'MP-8841207', 'status': 'recorded', 'notes': null, 'created_by': 8,
      'creator': {'id': 8, 'name': 'Mwajuma Hamisi'}, 'verifier': null, 'verified_at': null, 'rejection_reason': null,
      'recorded_by_email': 'cashier@watercom.test', 'created_at': _iso(1),
      'allocations': [{'id': 1, 'sales_receipt_id': 1, 'sales_invoice_id': inv1['id'], 'amount': inv1['total']}],
    });
    _order(5, 'ready', [(6, 60), (5, 40)], daysAgo: 3, approved: true);
    final loading = _order(1, 'loading', [(5, 90), (6, 40)], daysAgo: 3, approved: true);
    _loading(loading, 'open', daysAgo: 0);
    final road = _order(2, 'dispatched', [(5, 40), (7, 12)], daysAgo: 4, approved: true);
    final lo2 = _loading(road, 'dispatched', daysAgo: 1);
    _invoice(road, daysAgo: 1, loadingId: lo2['id'] as int);
    final done = _order(4, 'delivered', [(6, 40)], daysAgo: 45, approved: true);
    final lo3 = _loading(done, 'delivered', daysAgo: 44, shortBy: true);
    final inv3 = _invoice(done, daysAgo: 44, loadingId: lo3['id'] as int, paid: 200000);
    receipts.add({
      'id': 2, 'number': _number('RCT'), 'customer_id': 4, 'account_id': 3, 'receipt_date': _day(30), 'amount': '200000.00',
      'method': 'bank_transfer', 'reference': 'CRDB-952809', 'status': 'verified', 'notes': null, 'created_by': 8,
      'creator': {'id': 8, 'name': 'Mwajuma Hamisi'}, 'verifier': {'id': 65, 'name': 'Faraji Mrisho'}, 'verified_at': _iso(30),
      'rejection_reason': null, 'recorded_by_email': 'cashier@watercom.test', 'created_at': _iso(30),
      'allocations': [{'id': 2, 'sales_receipt_id': 2, 'sales_invoice_id': inv3['id'], 'amount': '200000.00'}],
    });

    for (final (customer, status, days) in [(1, 'draft', 0), (4, 'sent', 3)]) {
      final id = quotations.length + 1;
      final q = <String, dynamic>{
        'id': id, 'number': _number('QUO'), 'customer_id': customer, 'quote_date': _day(days), 'valid_until': _day(days - 14),
        'status': status, 'notes': null, 'sales_order_id': null, 'created_by': 63, 'created_at': _iso(days),
        'creator': {'id': 63, 'name': 'Hassan Juma'},
        'lines': [
          {..._line(5, 200, _price(customer, 5)), 'quotation_id': id, 'quantity': '200.000'},
          {..._line(7, 40, _price(customer, 7)), 'quotation_id': id, 'quantity': '40.000'},
        ],
      };
      _total(q);
      quotations.add(q);
    }
  }

  /* ════════════════════════════════════════════════════════ the JSON ══ */

  Map<String, dynamic> _page(List<Map<String, dynamic>> rows) =>
      {'data': rows, 'current_page': 1, 'last_page': 1, 'total': rows.length};

  bool _match(Map<String, dynamic> doc, String? q) {
    if (q == null || q.isEmpty) return true;
    final needle = q.toLowerCase();
    return '${doc['number'] ?? ''} ${_cust(doc['customer_id'])['name']} ${doc['vehicle_number'] ?? ''} ${doc['reference'] ?? ''}'
        .toLowerCase()
        .contains(needle);
  }

  double _balance(Map<String, dynamic> i) => _n(i['total']) - _n(i['amount_paid']) - _n(i['amount_credited']);

  Map<String, dynamic> _invoiceJson(Map<String, dynamic> i, {bool full = false}) {
    final order = orders.firstWhere((o) => o['id'] == i['sales_order_id']);
    final lo = loadings.where((l) => l['id'] == i['loading_order_id']).firstOrNull;
    return {
      ...i,
      'balance': _balance(i),
      'customer': full ? _cust(i['customer_id']) : _brief(_cust(i['customer_id'])),
      'order': {'id': order['id'], 'number': order['number'], 'delivery_address': order['delivery_address']},
      'loading_order': lo == null ? null : {'id': lo['id'], 'number': lo['number'], 'delivery_note_number': lo['delivery_note_number']},
      if (full)
        'allocations': [
          for (final r in receipts)
            for (final a in (r['allocations'] as List).cast<Map<String, dynamic>>())
              if (a['sales_invoice_id'] == i['id'])
                {
                  ...a,
                  'receipt': {'id': r['id'], 'number': r['number'], 'receipt_date': r['receipt_date'], 'status': r['status'], 'method': r['method']},
                },
        ],
      if (full) 'credit_notes': const [],
    };
  }

  Map<String, dynamic> _receiptJson(Map<String, dynamic> r) => {
    ...r,
    'customer': _cust(r['customer_id']),
    'account': _accounts.firstWhere((a) => a['id'] == r['account_id'], orElse: () => _accounts[1]),
    'allocations': [
      for (final a in (r['allocations'] as List).cast<Map<String, dynamic>>())
        {
          ...a,
          'invoice': () {
            final i = invoices.firstWhere((x) => x['id'] == a['sales_invoice_id']);
            return {'id': i['id'], 'number': i['number'], 'total': i['total'], 'sales_order_id': i['sales_order_id'], 'balance': _balance(i)};
          }(),
        },
    ],
  };

  Map<String, double> _remaining(Map<String, dynamic> o) {
    final out = <String, double>{};
    for (final l in (o['lines'] as List).cast<Map<String, dynamic>>()) {
      final approved = _n(l['quantity_approved']);
      final planned = loadings
          .where((lo) => lo['sales_order_id'] == o['id'] && lo['status'] != 'cancelled')
          .expand((lo) => (lo['lines'] as List).cast<Map<String, dynamic>>())
          .where((x) => x['sales_order_line_id'] == l['id'])
          .fold(0.0, (s, x) => s + _n(x['quantity_loaded'] ?? x['quantity_approved']));
      out['${l['id']}'] = (approved - planned).clamp(0, double.infinity).toDouble();
    }
    return out;
  }

  Map<String, dynamic> _availability(Iterable<dynamic> productIds) => {
    for (final p in productIds.toSet())
      '$p': {
        '2': {'on_hand': 3030, 'reserved': 90, 'available': 2940},
        '3': {'on_hand': 520, 'reserved': 0, 'available': 520},
      },
  };

  Map<String, dynamic> _policy(Map<String, dynamic> o) {
    final c = _cust(o['customer_id']);
    if (c['requires_prepayment'] == true) return {'mode': 'prepayment', 'passed': true, 'reasons': []};
    final outstanding = invoices.where((i) => i['customer_id'] == c['id'] && i['status'] == 'posted').fold(0.0, (s, i) => s + _balance(i));
    final exposure = outstanding + _n(o['total']);
    final limit = _n(c['credit_limit']);
    final passed = exposure <= limit;
    return {
      'mode': 'credit', 'passed': passed, 'credit_limit': limit, 'outstanding': outstanding, 'uninvoiced_orders': 0,
      'this_order': _n(o['total']), 'exposure': exposure, 'overdue_invoices': 0, 'oldest_overdue_days': 0,
      'reasons': passed ? [] : ['Exposure is over the credit limit.'], 'checked_at': _iso(0),
    };
  }

  Map<String, dynamic> _orderJson(Map<String, dynamic> o, {bool full = false}) {
    final base = {
      ...o,
      'lines_count': (o['lines'] as List).length,
      'customer': full ? _cust(o['customer_id']) : _brief(_cust(o['customer_id'])),
      'creator': {'id': 63, 'name': 'Hassan Juma'},
      'warehouse': _warehouses.where((w) => w['id'] == o['warehouse_id']).firstOrNull,
    };
    if (!full) return base..remove('lines');
    return {
      ...base,
      'approver': o['approved_at'] == null ? null : {'id': 65, 'name': 'Faraji Mrisho'},
      'invoices': [for (final i in invoices.where((i) => i['sales_order_id'] == o['id'])) _invoiceJson(i)..remove('lines')],
      'loading_orders': [for (final l in loadings.where((l) => l['sales_order_id'] == o['id'])) _loadingJson(l)..remove('lines')],
      'verified_payments': _verifiedFor(o),
      'remaining_to_load': _remaining(o),
      'policy_preview': o['status'] == 'submitted' ? _policy(o) : null,
      'availability': _availability((o['lines'] as List).map((l) => (l as Map)['product_id'])),
      'warehouses': _warehouses,
    };
  }

  double _verifiedFor(Map<String, dynamic> o) => [
    for (final r in receipts.where((r) => r['status'] == 'verified'))
      for (final a in (r['allocations'] as List).cast<Map<String, dynamic>>())
        if (invoices.any((i) => i['id'] == a['sales_invoice_id'] && i['sales_order_id'] == o['id'])) _n(a['amount']),
  ].fold(0.0, (s, v) => s + v);

  Map<String, dynamic> _loadingJson(Map<String, dynamic> l) {
    final o = orders.firstWhere((o) => o['id'] == l['sales_order_id']);
    return {
      ...l,
      'lines_count': (l['lines'] as List).length,
      'customer': _brief(_cust(l['customer_id'])),
      'order': {'id': o['id'], 'number': o['number'], 'status': o['status'], 'payment_mode': o['payment_mode'], 'total': o['total'], 'delivery_address': o['delivery_address']},
      'warehouse': _warehouses.firstWhere((w) => w['id'] == l['warehouse_id']),
      'availability': _availability((l['lines'] as List).map((x) => (x as Map)['product_id'])),
    };
  }

  Map<String, dynamic> _quotationJson(Map<String, dynamic> q, {bool full = false}) {
    final o = orders.where((o) => o['id'] == q['sales_order_id']).firstOrNull;
    final out = {
      ...q,
      'lines_count': (q['lines'] as List).length,
      'customer': full ? _cust(q['customer_id']) : _brief(_cust(q['customer_id'])),
      'order': o == null ? null : {'id': o['id'], 'number': o['number'], 'status': o['status']},
    };
    if (!full) out.remove('lines');
    return out;
  }

  /* ════════════════════════════════════════════════════════ dispatch ══ */

  /// Answers one /erp request (path after /erp, split), or [unhandled].
  Object? handle(
    String method,
    List<String> rest, {
    required List<String> perms,
    required List<String> modules,
    required String email,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
  }) {
    if (rest.isEmpty) return unhandled;
    void need(String permission) {
      if (!perms.contains(permission)) throw ApiException(403, 'Your role does not allow this.');
    }

    void module(String m) {
      if (!modules.contains(m)) throw ApiException(403, 'The $m module is not switched on for your company.');
    }

    final head = rest.first;
    if (head == 'customers' && method == 'GET') {
      module('sales');
      need('customers.view');
      if (rest.length == 2) return {'data': _cust(int.tryParse(rest[1]))};
      final q = '${query['q'] ?? ''}'.toLowerCase();
      final rows = [...customers]..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
      return _page(rows.where((c) => q.isEmpty || '${c['name']} ${c['code']}'.toLowerCase().contains(q)).toList());
    }
    if (head == 'sales') {
      module('sales');
      need('sales.view');
      return _sales(method, rest.skip(1).toList(), need, email, body, query);
    }
    if (head == 'dispatch') {
      module('dispatch');
      need('dispatch.view');
      return _dispatch(method, rest.skip(1).toList(), need, email, body, query);
    }
    return unhandled;
  }

  Never _invalid(String message, [String? field]) =>
      throw ApiException(422, message, field == null ? const {} : {field: [message]});

  Map<String, dynamic> _find(List<Map<String, dynamic>> list, String id, String what) =>
      list.where((x) => '${x['id']}' == id).firstOrNull ?? (throw ApiException(404, '$what not found.'));

  Object? _sales(String method, List<String> r, void Function(String) need, String email, Map<String, dynamic> body, Map<String, dynamic> query) {
    final head = r.isEmpty ? '' : r.first;
    final q = query['q'] as String?;
    if (method == 'GET' && head == 'overview') return {'data': _overview()};
    if (method == 'GET' && head == 'lookups') {
      return {
        'data': {
          'customers': customers,
          'products': [
            for (final p in _products.values)
              {...p, 'unit_id': 1, 'track_batches': true, 'track_expiry': true, 'unit': {'id': 1, 'code': p['unit'], 'allows_decimals': false}},
          ],
          'warehouses': _warehouses,
          'price_lists': const [],
          'cash_accounts': _accounts,
          'tax_rate': _tax,
        },
      };
    }
    if (method == 'GET' && head == 'prices') {
      final customer = int.tryParse('${query['customer_id'] ?? ''}');
      return {
        'data': {
          for (final p in _products.keys)
            '$p': {'price': customer == null ? _n(_products[p]!['sale_price']) : _price(customer, p), 'source': 'product'},
        },
        'tax_rate': _tax,
      };
    }
    if (method == 'GET' && head == 'customers' && r.length == 3 && r[2] == 'statement') return {'data': _statement(int.parse(r[1]))};

    if (head == 'quotations') {
      if (r.length == 1 && method == 'GET') {
        return _page([for (final x in quotations.reversed) if ((query['status'] == null || x['status'] == query['status']) && _match(x, q)) _quotationJson(x)]);
      }
      if (r.length == 1 && method == 'POST') {
        need('sales.quote');
        final x = _document(body, quotation: true);
        quotations.add(x);
        return {'data': _quotationJson(x, full: true)};
      }
      final x = _find(quotations, r[1], 'Quotation');
      if (r.length == 2) return {'data': _quotationJson(x, full: true)};
      need('sales.quote');
      final action = r[2];
      String expect(List<String> from, String verb) {
        if (!from.contains(x['status'])) _invalid('${x['number']} is ${x['status']} and cannot be $verb.');
        return verb;
      }

      switch (action) {
        case 'send':
          expect(['draft'], 'sent');
          x['status'] = 'sent';
          return {'message': '${x['number']} marked as sent.', 'data': _quotationJson(x)};
        case 'reject':
          expect(['draft', 'sent'], 'rejected');
          x['status'] = 'rejected';
          return {'message': '${x['number']} marked as declined by the customer.', 'data': _quotationJson(x)};
        case 'cancel':
          expect(['draft', 'sent'], 'cancelled');
          x['status'] = 'cancelled';
          return {'message': '${x['number']} cancelled.', 'data': _quotationJson(x)};
        case 'convert':
          need('sales.order');
          expect(['draft', 'sent'], 'converted');
          final o = _document({
            'customer_id': x['customer_id'],
            'lines': [
              for (final l in (x['lines'] as List).cast<Map<String, dynamic>>())
                {'product_id': l['product_id'], 'quantity': _n(l['quantity']), 'unit_price': _n(l['unit_price'])},
            ],
          }, quotation: false);
          o['quotation_id'] = x['id'];
          orders.add(o);
          x['status'] = 'converted';
          x['sales_order_id'] = o['id'];
          return {'message': '${x['number']} became order ${o['number']}.', 'data': _orderJson(o, full: true)};
      }
    }

    if (head == 'orders') {
      if (r.length == 1 && method == 'GET') {
        final statuses = '${query['status'] ?? ''}'.split(',').where((s) => s.isNotEmpty).toList();
        return _page([
          for (final o in orders.reversed)
            if ((statuses.isEmpty || statuses.contains(o['status'])) &&
                (query['customer_id'] == null || '${o['customer_id']}' == '${query['customer_id']}') &&
                _match(o, q))
              _orderJson(o),
        ]);
      }
      if (r.length == 2 && r[1] == 'counts') {
        final out = <String, int>{};
        for (final o in orders) {
          out['${o['status']}'] = (out['${o['status']}'] ?? 0) + 1;
        }
        return {'data': out};
      }
      if (r.length == 1 && method == 'POST') {
        need('sales.order');
        final o = _document(body, quotation: false);
        orders.add(o);
        return {'data': _orderJson(o, full: true)};
      }
      final o = _find(orders, r[1], 'Order');
      if (r.length == 2) return {'data': _orderJson(o, full: true)};
      return _orderAction(o, r[2], need, body);
    }

    if (head == 'invoices') {
      if (r.length == 1 && method == 'GET') {
        final today = _day(0);
        return _page([
          for (final i in invoices.reversed)
            if ((query['status'] == null || i['status'] == query['status']) &&
                (query['customer_id'] == null || '${i['customer_id']}' == '${query['customer_id']}') &&
                (query['open_only'] == null || (i['status'] == 'posted' && _balance(i) > 0.004)) &&
                (query['overdue'] == null || (i['status'] == 'posted' && _balance(i) > 0.004 && '${i['due_date']}'.compareTo(today) < 0)) &&
                _match(i, q))
              _invoiceJson(i)..remove('lines'),
        ]);
      }
      final i = _find(invoices, r[1], 'Invoice');
      if (r.length == 2) return {'data': _invoiceJson(i, full: true)};
      need('sales.invoice');
      if (i['status'] != 'draft') _invalid('${i['number']} is ${i['status']}; only a draft can be ${r[2] == 'post' ? 'posted' : 'cancelled'}.');
      if (r[2] == 'post') {
        i['status'] = 'posted';
        i['posted_at'] = _iso(0);
        i['poster'] = {'id': 0, 'name': 'You'};
        return {'message': '${i['number']} posted.', 'data': _invoiceJson(i)};
      }
      i['status'] = 'cancelled';
      return {'message': '${i['number']} cancelled.', 'data': _invoiceJson(i)};
    }

    if (head == 'receipts') {
      if (r.length == 1 && method == 'GET') {
        return _page([
          for (final x in receipts.reversed)
            if ((query['status'] == null || x['status'] == query['status']) && _match(x, q)) _receiptJson(x),
        ]);
      }
      if (r.length == 1 && method == 'POST') {
        need('sales.receipt');
        return _recordReceipt(body, email);
      }
      final x = _find(receipts, r[1], 'Receipt');
      if (r.length == 2) return {'data': _receiptJson(x)};
      need('dispatch.verify');
      if (x['status'] != 'recorded') _invalid('${x['number']} is ${x['status']}.');
      if (x['recorded_by_email'] == email) _invalid('You recorded this payment, so someone else in finance must verify it.');
      if (r[2] == 'verify') {
        _verify(x);
        return {'message': '${x['number']} verified and posted.', 'data': _receiptJson(x)};
      }
      final reason = '${body['reason'] ?? ''}'.trim();
      if (reason.length < 3) _invalid('Give a reason of at least 3 characters.', 'reason');
      x['status'] = 'rejected';
      x['rejection_reason'] = reason;
      return {'message': '${x['number']} rejected.', 'data': _receiptJson(x)};
    }
    return unhandled;
  }

  /// A new draft order or quotation from the form's body.
  Map<String, dynamic> _document(Map<String, dynamic> body, {required bool quotation}) {
    final customer = body['customer_id'];
    if (customer == null || !customers.any((c) => c['id'] == customer)) _invalid('Choose the customer.', 'customer_id');
    final lines = (body['lines'] as List? ?? const []).cast<Map>();
    if (lines.isEmpty) _invalid('Add at least one line.', 'lines');
    final id = quotation ? quotations.length + 1 : orders.length + 1;
    final doc = <String, dynamic>{
      'id': id, 'number': _number(quotation ? 'QUO' : 'SO'), 'customer_id': customer, 'status': 'draft', 'notes': body['notes'],
      'created_by': 0, 'created_at': _iso(0),
      if (quotation) ...{
        'quote_date': '${body['quote_date'] ?? _day(0).substring(0, 10)}T00:00:00.000000Z',
        'valid_until': body['valid_until'] == null ? null : '${body['valid_until']}T00:00:00.000000Z',
        'sales_order_id': null, 'creator': {'id': 0, 'name': 'You'},
      } else ...{
        'quotation_id': null, 'warehouse_id': body['warehouse_id'],
        'order_date': '${body['order_date'] ?? _day(0).substring(0, 10)}T00:00:00.000000Z',
        'required_date': body['required_date'] == null ? null : '${body['required_date']}T00:00:00.000000Z',
        'payment_mode': null, 'delivery_address': body['delivery_address'], 'policy_check': null, 'override_reason': null,
        'submitted_at': null, 'approved_at': null, 'payment_verified_at': null, 'rejection_reason': null,
      },
      'lines': [
        for (var n = 0; n < lines.length; n++)
          () {
            final l = lines[n];
            final p = l['product_id'] as int;
            final qty = _n(l['quantity']);
            if (qty <= 0) _invalid('The quantity must be greater than 0.', 'lines.$n.quantity');
            final line = _line(p, qty, l['unit_price'] == null ? _price(customer as int, p) : _n(l['unit_price']), discount: _n(l['discount_percent']));
            return quotation
                ? {...line, 'quotation_id': id, 'quantity': qty.toStringAsFixed(3)}
                : {
                    ...line, 'sales_order_id': id, 'quantity_ordered': qty.toStringAsFixed(3), 'quantity_approved': null,
                    'quantity_loaded': '0.000', 'quantity_received': '0.000', 'quantity_invoiced': '0.000',
                  };
          }(),
      ],
    };
    _total(doc);
    return doc;
  }

  Object? _orderAction(Map<String, dynamic> o, String action, void Function(String) need, Map<String, dynamic> body) {
    void expect(List<String> from, String verb) {
      if (!from.contains(o['status'])) _invalid('${o['number']} is ${'${o['status']}'.replaceAll('_', ' ')} and cannot be $verb.');
    }

    final lines = (o['lines'] as List).cast<Map<String, dynamic>>();
    switch (action) {
      case 'submit':
        need('sales.order');
        expect(['draft'], 'submitted');
        o['status'] = 'submitted';
        o['submitted_at'] = _iso(0);
        return {'message': '${o['number']} submitted for approval.', 'data': _orderJson(o)};
      case 'approve':
        need('sales.approve');
        expect(['submitted'], 'approved');
        final policy = _policy(o);
        final reason = '${body['override_reason'] ?? ''}'.trim();
        if (policy['passed'] != true && reason.length < 5) {
          _invalid('This order is outside the credit policy. Give a reason to approve it anyway.', 'override_reason');
        }
        final quantities = (body['quantities'] as Map?) ?? const {};
        for (final l in lines) {
          final q = quantities['${l['id']}'];
          final approved = q == null ? _n(l['quantity_ordered']) : _n(q);
          if (approved > _n(l['quantity_ordered'])) _invalid('You cannot approve more than was ordered.');
          l['quantity_approved'] = approved.toStringAsFixed(3);
        }
        final prepay = policy['mode'] == 'prepayment';
        o
          ..['status'] = prepay ? 'awaiting_payment' : 'ready'
          ..['payment_mode'] = prepay ? 'prepayment' : 'credit'
          ..['approved_at'] = _iso(0)
          ..['policy_check'] = policy
          ..['override_reason'] = reason.isEmpty ? null : reason;
        if (prepay) _invoice(o, daysAgo: 0);
        return {
          'message': prepay
              ? '${o['number']} approved. It waits for payment verification before loading.'
              : '${o['number']} approved and released for loading.',
          'data': _orderJson(o),
        };
      case 'reject':
        need('sales.approve');
        expect(['submitted'], 'rejected');
        final reason = '${body['reason'] ?? ''}'.trim();
        if (reason.length < 3) _invalid('Give a reason of at least 3 characters.', 'reason');
        o['status'] = 'rejected';
        o['rejection_reason'] = reason;
        return {'message': '${o['number']} rejected.', 'data': _orderJson(o)};
      case 'cancel':
        need('sales.approve');
        expect(['draft', 'submitted', 'awaiting_payment', 'ready'], 'cancelled');
        o['status'] = 'cancelled';
        return {'message': '${o['number']} cancelled.', 'data': _orderJson(o)};
      case 'invoice':
        need('sales.invoice');
        if (lines.every((l) => _n(l['quantity_invoiced']) >= _n(l['quantity_approved']))) _invalid('${o['number']} has nothing left to invoice.');
        final inv = _invoice(o, status: 'draft', daysAgo: 0, loadingId: body['loading_order_id'] as int?);
        inv['poster'] = null;
        return {'message': 'Invoice ${inv['number']} prepared.', 'data': _invoiceJson(inv)};
    }
    return unhandled;
  }

  Map<String, dynamic> _recordReceipt(Map<String, dynamic> body, String email) {
    final customer = body['customer_id'];
    if (customer == null) _invalid('Choose the customer.', 'customer_id');
    final allocations = (body['allocations'] as List? ?? const []).cast<Map>();
    if (allocations.isEmpty) _invalid('Apply the money to at least one invoice.', 'allocations');
    for (var n = 0; n < allocations.length; n++) {
      final i = invoices.firstWhere((x) => x['id'] == allocations[n]['sales_invoice_id']);
      if (_n(allocations[n]['amount']) > _balance(i) + 0.004) {
        _invalid('More than the ${_balance(i).toStringAsFixed(2)} still owed on ${i['number']}.', 'allocations.$n.amount');
      }
    }
    final total = allocations.fold(0.0, (s, a) => s + _n(a['amount']));
    final id = receipts.length + 1;
    final x = <String, dynamic>{
      'id': id, 'number': _number('RCT'), 'customer_id': customer, 'account_id': body['account_id'],
      'receipt_date': '${body['receipt_date'] ?? _day(0).substring(0, 10)}T00:00:00.000000Z', 'amount': _money(total),
      'method': body['method'] ?? 'cash', 'reference': body['reference'], 'status': 'recorded', 'notes': body['notes'],
      'created_by': 0, 'creator': {'id': 0, 'name': 'You'}, 'verifier': null, 'verified_at': null, 'rejection_reason': null,
      'recorded_by_email': email, 'created_at': _iso(0),
      'allocations': [
        for (final a in allocations)
          {'id': 100 + id, 'sales_receipt_id': id, 'sales_invoice_id': a['sales_invoice_id'], 'amount': _money(_n(a['amount']))},
      ],
    };
    receipts.add(x);
    return {'message': 'Receipt ${x['number']} recorded. Someone else in finance must verify it.', 'data': _receiptJson(x)};
  }

  void _verify(Map<String, dynamic> x) {
    x['status'] = 'verified';
    x['verified_at'] = _iso(0);
    x['verifier'] = {'id': 0, 'name': 'You'};
    for (final a in (x['allocations'] as List).cast<Map<String, dynamic>>()) {
      final i = invoices.firstWhere((v) => v['id'] == a['sales_invoice_id']);
      i['amount_paid'] = _money(_n(i['amount_paid']) + _n(a['amount']));
      final o = orders.firstWhere((v) => v['id'] == i['sales_order_id']);
      if (o['status'] == 'awaiting_payment' && _verifiedFor(o) >= _n(o['total']) - 0.004) {
        o['status'] = 'ready';
        o['payment_verified_at'] = _iso(0);
      }
    }
  }

  Map<String, dynamic> _statement(int id) {
    final c = _cust(id);
    final rows = <Map<String, dynamic>>[
      for (final i in invoices.where((i) => i['customer_id'] == id && i['status'] == 'posted'))
        {'date': '${i['invoice_date']}'.substring(0, 10), 'type': 'invoice', 'id': i['id'], 'number': i['number'], 'detail': 'Due ${'${i['due_date']}'.substring(0, 10)}', 'debit': _n(i['total']), 'credit': 0},
      for (final r in receipts.where((r) => r['customer_id'] == id && r['status'] == 'verified'))
        {'date': '${r['receipt_date']}'.substring(0, 10), 'type': 'receipt', 'id': r['id'], 'number': r['number'], 'detail': '${r['method']}'.replaceAll('_', ' '), 'debit': 0, 'credit': _n(r['amount'])},
    ]..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    var balance = 0.0;
    for (final r in rows) {
      balance += _n(r['debit']) - _n(r['credit']);
      r['balance'] = balance;
    }
    final aged = {'current': 0.0, 'd1_30': 0.0, 'd31_60': 0.0, 'd61_90': 0.0, 'd90_plus': 0.0};
    final today = DateTime.now();
    for (final i in invoices.where((i) => i['customer_id'] == id && i['status'] == 'posted' && _balance(i) > 0.004)) {
      final late = today.difference(DateTime.parse('${i['due_date']}'.substring(0, 10))).inDays;
      final key = late <= 0 ? 'current' : late <= 30 ? 'd1_30' : late <= 60 ? 'd31_60' : late <= 90 ? 'd61_90' : 'd90_plus';
      aged[key] = aged[key]! + _balance(i);
    }
    return {
      'customer': c, 'from': _day(90).substring(0, 10), 'to': _day(0).substring(0, 10), 'opening_balance': 0, 'lines': rows,
      'total_debit': rows.fold(0.0, (s, r) => s + _n(r['debit'])), 'total_credit': rows.fold(0.0, (s, r) => s + _n(r['credit'])),
      'closing_balance': balance, 'aged': {...aged, 'total': aged.values.fold(0.0, (s, v) => s + v)},
    };
  }

  Map<String, dynamic> _overview() {
    final month = _day(0).substring(0, 7);
    final today = _day(0);
    final pipeline = <String, Map<String, dynamic>>{};
    for (final o in orders) {
      final cell = pipeline.putIfAbsent('${o['status']}', () => {'count': 0, 'value': 0.0});
      cell['count'] = (cell['count'] as int) + 1;
      cell['value'] = (cell['value'] as double) + _n(o['total']);
    }
    final open = invoices.where((i) => i['status'] == 'posted' && _balance(i) > 0.004);
    return {
      'sales_this_month': orders
          .where((o) => '${o['order_date']}'.startsWith(month) && !['draft', 'rejected', 'cancelled'].contains(o['status']))
          .fold(0.0, (s, o) => s + _n(o['subtotal'])),
      'invoiced_this_month': invoices.where((i) => '${i['invoice_date']}'.startsWith(month)).fold(0.0, (s, i) => s + _n(i['total'])),
      'received_this_month': receipts
          .where((r) => r['status'] == 'verified' && '${r['receipt_date']}'.startsWith(month))
          .fold(0.0, (s, r) => s + _n(r['amount'])),
      'receivables': open.fold(0.0, (s, i) => s + _balance(i)),
      'overdue': open.where((i) => '${i['due_date']}'.compareTo(today) < 0).fold(0.0, (s, i) => s + _balance(i)),
      'open_quotations': quotations.where((x) => x['status'] == 'draft' || x['status'] == 'sent').length,
      'awaiting_verification': receipts.where((r) => r['status'] == 'recorded').length,
      'awaiting_payment': orders.where((o) => o['status'] == 'awaiting_payment').length,
      'open_discrepancies': loadings.where((l) => l['discrepancy_status'] == 'open').length,
      'pipeline': pipeline,
      'recent_orders': [for (final o in orders.reversed.take(6)) _orderJson(o)],
    };
  }

  Object? _dispatch(String method, List<String> r, void Function(String) need, String email, Map<String, dynamic> body, Map<String, dynamic> query) {
    final head = r.isEmpty ? '' : r.first;
    if (method == 'GET' && head == 'lookups') {
      return {
        'data': {
          'warehouses': _warehouses,
          'ready_orders': [
            for (final o in orders.reversed.where((o) => o['status'] == 'ready' || o['status'] == 'loading'))
              {'id': o['id'], 'number': o['number'], 'customer_id': o['customer_id'], 'status': o['status'], 'warehouse_id': o['warehouse_id'], 'delivery_address': o['delivery_address'], 'customer': {'id': o['customer_id'], 'name': _cust(o['customer_id'])['name']}},
          ],
        },
      };
    }
    if (method == 'GET' && head == 'verification') {
      need('dispatch.verify');
      return {
        'data': {
          'receipts': [for (final x in receipts.where((x) => x['status'] == 'recorded')) _receiptJson(x)],
          'awaiting_payment': [for (final o in orders.where((o) => o['status'] == 'awaiting_payment')) {..._orderJson(o), 'verified_payments': _verifiedFor(o)}],
          'ready': [for (final o in orders.where((o) => o['status'] == 'ready')) _orderJson(o)],
        },
      };
    }
    if (head != 'loading-orders') return unhandled;
    if (r.length == 1 && method == 'GET') {
      final stage = query['stage'];
      return _page([
        for (final l in loadings.reversed)
          if ((query['status'] == null || l['status'] == query['status']) &&
              (stage != 'in_transit' || l['status'] == 'dispatched') &&
              (stage != 'discrepancies' || l['discrepancy_status'] != null) &&
              (query['sales_order_id'] == null || '${l['sales_order_id']}' == '${query['sales_order_id']}') &&
              _match(l, query['q'] as String?))
            _loadingJson(l)..remove('lines'),
      ]);
    }
    if (r.length == 1 && method == 'POST') {
      need('dispatch.load');
      return _createLoading(body);
    }
    final l = _find(loadings, r[1], 'Loading order');
    if (r.length == 2) return {'data': _loadingJson(l)};
    final lines = (l['lines'] as List).cast<Map<String, dynamic>>();
    final order = orders.firstWhere((o) => o['id'] == l['sales_order_id']);
    final orderLines = (order['lines'] as List).cast<Map<String, dynamic>>();
    void expect(String status, String verb) {
      if (l['status'] != status) _invalid('${l['number']} is ${l['status']} and cannot be $verb.');
    }

    String? name() {
      final n = '${body['name'] ?? ''}'.trim();
      return n.isEmpty ? null : n;
    }

    switch (r[2]) {
      case 'loaded':
        need('dispatch.load');
        expect('open', 'changed');
        final q = (body['quantities'] as Map?) ?? const {};
        for (final x in lines) {
          final v = q['${x['id']}'];
          if (v != null && _n(v) > _n(x['quantity_approved'])) {
            _invalid('${x['product']['name']}: more than the ${_n(x['quantity_approved'])} approved. A truck may carry less than approved, never more.');
          }
          x['quantity_loaded'] = v == null ? null : _n(v).toStringAsFixed(3);
        }
        return {'message': 'Loaded quantities saved.', 'data': _loadingJson(l)};
      case 'confirm-loading':
        need('dispatch.load');
        expect('open', 'confirmed as loaded');
        if (lines.any((x) => x['quantity_loaded'] == null)) _invalid('Enter the quantity actually loaded on every line of ${l['number']} first.');
        for (final x in lines) {
          final ol = orderLines.firstWhere((o) => o['id'] == x['sales_order_line_id']);
          ol['quantity_loaded'] = (_n(ol['quantity_loaded']) + _n(x['quantity_loaded'])).toStringAsFixed(3);
        }
        l
          ..['status'] = 'loaded'
          ..['loaded_at'] = _iso(0)
          ..['loader'] = {'id': 0, 'name': 'You'}
          ..['stock_document'] = {'id': 900 + (l['id'] as int), 'number': _number('ISS'), 'status': 'posted'};
        return {'message': 'Loading confirmed; stock issued on ${l['stock_document']['number']}.', 'data': _loadingJson(l)};
      case 'confirm-driver':
        need('dispatch.load');
        expect('loaded', 'confirmed by the driver');
        final n = name() ?? l['driver_name'];
        if (n == null) _invalid("Enter the driver's name.", 'name');
        l['driver_confirmed_name'] = n;
        l['driver_confirmed_at'] = _iso(0);
        return {'message': 'Driver confirmation recorded.', 'data': _loadingJson(l)};
      case 'confirm-security':
        need('dispatch.gatepass');
        expect('loaded', 'confirmed by security');
        l['security_confirmed_name'] = name() ?? 'Gate';
        l['security_confirmed_at'] = _iso(0);
        return {'message': 'Security confirmation recorded.', 'data': _loadingJson(l)};
      case 'delivery-note':
        need('dispatch.load');
        expect('loaded', 'given a delivery note');
        if (l['driver_confirmed_at'] == null || l['security_confirmed_at'] == null) {
          _invalid('The driver and security must both confirm the load on ${l['number']} before the delivery note is issued.');
        }
        l['delivery_note_number'] = _number('DN');
        l['delivery_note_issued_at'] = _iso(0);
        return {'message': 'Delivery note ${l['delivery_note_number']} issued.', 'data': _loadingJson(l)};
      case 'gate-pass':
        need('dispatch.gatepass');
        expect('loaded', 'given a gate pass');
        if (l['delivery_note_number'] == null) _invalid('Issue the delivery note for ${l['number']} before the gate pass.');
        l
          ..['status'] = 'dispatched'
          ..['gate_pass_number'] = _number('GP')
          ..['gate_pass_issued_at'] = _iso(0)
          ..['gate_pass_issuer'] = {'id': 0, 'name': 'You'};
        order['status'] = 'dispatched';
        return {'message': 'Gate pass ${l['gate_pass_number']} issued.', 'data': _loadingJson(l)};
      case 'deliver':
        need('dispatch.deliver');
        expect('dispatched', 'marked delivered');
        final who = '${body['received_by_name'] ?? ''}'.trim();
        if (who.length < 2) _invalid('Enter who received the goods.', 'received_by_name');
        final q = (body['quantities'] as Map?) ?? const {};
        var short = false;
        for (final x in lines) {
          final got = _n(q['${x['id']}'] ?? x['quantity_loaded']);
          if (got < 0 || got > _n(x['quantity_loaded'])) {
            _invalid('${x['product']['name']}: the customer can receive between 0 and the ${_n(x['quantity_loaded'])} loaded.');
          }
          if (got < _n(x['quantity_loaded'])) short = true;
          x['quantity_received'] = got.toStringAsFixed(3);
          final ol = orderLines.firstWhere((o) => o['id'] == x['sales_order_line_id']);
          ol['quantity_received'] = (_n(ol['quantity_received']) + got).toStringAsFixed(3);
        }
        l
          ..['status'] = 'delivered'
          ..['received_by_name'] = who
          ..['received_date'] = '${body['received_date']}T00:00:00.000000Z'
          ..['delivery_remark'] = body['remark']
          ..['pod_recorded_at'] = _iso(0)
          ..['discrepancy_status'] = short ? 'open' : null;
        if (_remaining(order).values.every((v) => v <= 0) &&
            loadings.where((x) => x['sales_order_id'] == order['id'] && x['status'] != 'cancelled').every((x) => x['status'] == 'delivered')) {
          order['status'] = 'delivered';
        }
        return {'message': short ? 'Delivery recorded with a shortfall. It needs a decision.' : 'Delivery recorded.', 'data': _loadingJson(l)};
      case 'resolve':
        need('dispatch.resolve');
        if (l['discrepancy_status'] != 'open') _invalid('${l['number']} has no open delivery discrepancy.');
        final note = '${body['note'] ?? ''}'.trim();
        if (note.length < 3) _invalid('Say what happened, in at least 3 characters.', 'note');
        final decision = body['decision'] == 'write_off' ? 'written_off' : 'returned';
        l
          ..['discrepancy_status'] = decision
          ..['discrepancy_note'] = note
          ..['discrepancy_resolved_at'] = _iso(0)
          ..['resolver'] = {'id': 0, 'name': 'You'};
        if (decision == 'returned') l['return_document'] = {'id': 950 + (l['id'] as int), 'number': _number('GRN'), 'status': 'posted'};
        return {'message': 'Discrepancy resolved.', 'data': _loadingJson(l)};
      case 'cancel':
        need('dispatch.load');
        expect('open', 'cancelled');
        l['status'] = 'cancelled';
        if (!loadings.any((x) => x['sales_order_id'] == order['id'] && x['status'] != 'cancelled')) order['status'] = 'ready';
        return {'message': '${l['number']} cancelled.', 'data': _loadingJson(l)};
    }
    return unhandled;
  }

  Map<String, dynamic> _createLoading(Map<String, dynamic> body) {
    final order = orders.where((o) => o['id'] == body['sales_order_id']).firstOrNull ?? (throw ApiException(404, 'Order not found.'));
    if (order['status'] == 'awaiting_payment') _invalid('${order['number']} waits for its payment to be verified.');
    if (!['ready', 'loading', 'dispatched'].contains(order['status'])) {
      _invalid('${order['number']} is ${order['status']}. Only an approved order released for loading can be loaded.');
    }
    if (body['warehouse_id'] == null) _invalid('Choose an active warehouse to load from.', 'warehouse_id');
    final remaining = _remaining(order);
    final q = (body['quantities'] as Map?) ?? const {};
    final id = loadings.length + 1;
    final lines = <Map<String, dynamic>>[];
    for (final ol in (order['lines'] as List).cast<Map<String, dynamic>>()) {
      final left = remaining['${ol['id']}'] ?? 0;
      final take = q.containsKey('${ol['id']}') ? _n(q['${ol['id']}']) : left;
      if (take > left + 0.00001) _invalid('${ol['product']['name']}: at most $left may still be loaded on ${order['number']}.');
      if (take <= 0) continue;
      lines.add({
        'id': _nextLine++, 'sales_order_line_id': ol['id'], 'product_id': ol['product_id'],
        'quantity_ordered': ol['quantity_ordered'], 'quantity_approved': take.toStringAsFixed(3),
        'quantity_loaded': null, 'quantity_received': null, 'product': _productJson(ol['product_id'] as int),
      });
    }
    if (lines.isEmpty) _invalid('Nothing is left to load on ${order['number']}.');
    String? s(String k) => '${body[k] ?? ''}'.trim().isEmpty ? null : '${body[k]}'.trim();
    final l = <String, dynamic>{
      'id': id, 'number': _number('LO'), 'sales_order_id': order['id'], 'customer_id': order['customer_id'],
      'warehouse_id': body['warehouse_id'], 'status': 'open',
      'planned_date': '${body['planned_date'] ?? _day(0).substring(0, 10)}T00:00:00.000000Z',
      'vehicle_number': s('vehicle_number'), 'driver_name': s('driver_name'), 'destination': s('destination'), 'notes': null,
      'loaded_at': null, 'loader': null, 'driver_confirmed_name': null, 'driver_confirmed_at': null,
      'security_confirmed_name': null, 'security_confirmed_at': null, 'delivery_note_number': null, 'delivery_note_issued_at': null,
      'gate_pass_number': null, 'gate_pass_issued_at': null, 'gate_pass_issuer': null, 'received_by_name': null, 'received_date': null,
      'delivery_remark': null, 'pod_recorded_at': null, 'discrepancy_status': null, 'discrepancy_note': null,
      'discrepancy_resolved_at': null, 'stock_document': null, 'return_document': null,
      'creator': {'id': 0, 'name': 'You'}, 'created_at': _iso(0), 'lines': lines,
    };
    loadings.add(l);
    order['status'] = 'loading';
    return {'message': 'Loading order ${l['number']} created.', 'data': _loadingJson(l)};
  }
}
