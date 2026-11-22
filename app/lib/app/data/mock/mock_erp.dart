import '../services/api_service.dart';
import 'mock_finance.dart';
import 'mock_ops.dart';
import 'mock_people.dart';
import 'mock_sales.dart';
import 'mock_seed.dart';

/// The in-app stand-in for /api/erp: the configuration, and the Inventory
/// app's warehouses, products, balances and stock documents, answering the
/// same paths with the same JSON shapes as the Laravel controllers
/// (Erp\SetupController, StockController, StockDocumentController …).
///
/// Posting really moves the mock's balances, so a count or a GRN made
/// offline reads back the way it would against the server.
class MockErp {
  MockErp() {
    _seed();
  }

  /// Returned by [handle] for a path this fixture does not answer.
  static const unhandled = Object();

  /// The Fleet and HR apps' endpoints.
  final people = MockPeople();

  /// Production, CRM and Documents (/erp/production, /erp/crm, /erp/files).
  final ops = MockOps();

  /// Sales and Dispatch (/erp/sales, /erp/dispatch, /erp/customers).
  final sales = MockSales();

  /// Procurement, Finance and Assets (/erp/procurement, /erp/suppliers,
  /// /erp/finance, /erp/journals, /erp/trial-balance, /erp/assets).
  final finance = MockFinance();

  /// Every module this release ships.
  static const liveModules = [
    'vouchflow', 'inventory', 'sales', 'procurement', 'accounting', //
    'production', 'dispatch', 'fleet', 'hr', 'crm', 'assets', 'documents',
  ];

  /// What the demo company runs, and what its plan would allow on top.
  List<String> modules = ['vouchflow', 'inventory', 'sales', 'procurement', 'accounting'];
  List<String>? licensedModules = [
    'vouchflow', 'inventory', 'sales', 'procurement', 'accounting', //
    'production', 'hr', 'fleet',
  ];
  bool isSetUp = true;

  /// Tests set a person's permissions here (by email) to try a role.
  final permissionsFor = <String, List<String>>{};

  static const _inventoryAll = [
    'inventory.view', 'inventory.manage', 'inventory.receive', 'inventory.issue', //
    'inventory.transfer', 'inventory.adjust', 'inventory.post', 'inventory.reverse',
  ];

  /// The permissions a role starts with, as the backend's built-in roles
  /// grant them (trimmed to the modules the fixture runs).
  List<String> _permissions(String role, String email) {
    final set = permissionsFor[email];
    if (set != null) return set;
    return switch (role) {
      'company_admin' => [
        'erp.configure', 'roles.manage', ..._inventoryAll, //
        'customers.view', 'customers.manage', 'suppliers.view', 'suppliers.manage',
        'accounting.view', 'accounting.manage', 'accounting.post', 'accounting.reverse',
        'sales.view', 'procurement.view', ...MockSales.permissions,
      ],
      'ceo' || 'director' => ['inventory.view', 'sales.view', 'accounting.view'],
      'finance' => ['inventory.view', 'accounting.view', 'accounting.post'],
      'hod' || 'manager' => ['inventory.view', 'inventory.issue'],
      // Requesters and cashiers run VouchFlow alone.
      _ => const [],
    };
  }

  /* ════════════════════════════════════════════════════════ the dataset ══ */

  final _warehouses = <Map<String, dynamic>>[];
  final _products = <Map<String, dynamic>>[];
  final _balances = <_Balance>[];
  final _documents = <Map<String, dynamic>>[];
  final _movements = <Map<String, dynamic>>[];
  int _nextBalance = 1, _nextDocument = 1, _nextLine = 1, _nextMovement = 1;
  final _sequence = <String, int>{};

  static const _units = {
    1: {'id': 1, 'code': 'CTN', 'name': 'Carton', 'allows_decimals': false},
    2: {'id': 2, 'code': 'PCS', 'name': 'Piece', 'allows_decimals': false},
    3: {'id': 3, 'code': 'KG', 'name': 'Kilogram', 'allows_decimals': true},
  };

  static const _categories = {
    1: 'Preforms & caps',
    2: 'Labels & packaging',
    3: 'Bottled water',
    4: 'Chemicals',
  };

  /// The supplier list a GRN offers.
  static const _suppliers = [
    {'id': 1, 'code': 'SUP-001', 'name': 'Plastico East Africa'},
    {'id': 2, 'code': 'SUP-002', 'name': 'Kibo Labels Ltd'},
  ];

  void _seed() {
    _warehouses.addAll([
      _warehouse(1, 'MAIN', 'Factory store Mbezi', 'warehouse', 'Dar es Salaam'),
      _warehouse(2, 'FGW', 'Finished goods warehouse', 'warehouse', 'Dar es Salaam'),
      _warehouse(3, 'ARU', 'Arusha depot', 'depot', 'Arusha'),
    ]);
    _products.addAll([
      _product(1, 'RM-PRF-28', 'PET preform 28g', 'raw_material', 1, 2, 95, 0, 20000, batches: true),
      _product(2, 'RM-CAP-28', 'Bottle cap 28mm', 'raw_material', 1, 2, 18, 0, 20000, batches: true),
      _product(3, 'PK-LBL-500', 'Label: 500ml', 'packaging', 2, 2, 12, 0, 20000),
      _product(4, 'PK-SHR-24', 'Shrink film roll', 'packaging', 2, 3, 5200, 0, 50),
      _product(5, 'FG-W500-24', 'Watercom 500ml × 24', 'finished_good', 3, 1, 3450, 7200, 200, batches: true, expiry: true),
      _product(6, 'FG-W1500-12', 'Watercom 1.5L × 12', 'finished_good', 3, 1, 4100, 8400, 150, batches: true, expiry: true),
      _product(7, 'FG-W19L', 'Watercom 19L dispenser jar', 'finished_good', 3, 2, 3500, 6000, 80, batches: true, expiry: true),
      _product(8, 'CH-CHL-25', 'Chlorine tablets', 'raw_material', 4, 3, 14500, 0, 10),
    ]);

    // Opening balances, posted as one opening document per warehouse so
    // the ledger and the balances agree.
    final openings = {
      1: [
        (1, 'PRF-2410', 76000.0, 96.5),
        (2, 'CAP-2410', 106915.0, 18.0),
        (3, '', 18500.0, 12.0),
        (4, '', 42.0, 5200.0),
        (8, '', 6.0, 14500.0),
      ],
      2: [
        (5, 'W500-261101', 640.0, 3450.0),
        (6, 'W15-261028', 410.0, 4100.0),
        (7, 'WC261023', 40.0, 3500.0),
      ],
      3: [
        (5, 'W500-261020', 180.0, 3400.0),
        (6, 'W15-261015', 96.0, 4050.0),
      ],
    };
    for (final entry in openings.entries) {
      final doc = _newDocument('opening', {
        'warehouse_id': entry.key,
        'document_date': iso(20).substring(0, 10),
        'reference': 'Opening balances',
        'lines': [
          for (final (p, batch, qty, cost) in entry.value)
            {
              'product_id': p,
              'quantity': qty,
              'unit_cost': cost,
              'batch_number': batch,
              'expiry_date': _productById(p)['track_expiry'] == true ? iso(-300).substring(0, 10) : null,
            },
        ],
      }, creator: 'Neema Shirima');
      _post(doc, 'Neema Shirima');
    }

    // A few everyday documents.
    final grn = _newDocument('grn', {
      'warehouse_id': 1,
      'supplier_id': 1,
      'document_date': iso(3).substring(0, 10),
      'reference': 'PO-2026-0041',
      'lines': [
        {'product_id': 1, 'quantity': 12000, 'unit_cost': 98, 'batch_number': 'PRF-2411'},
      ],
    }, creator: 'Baraka Mollel');
    _post(grn, 'Neema Shirima');

    final issue = _newDocument('issue', {
      'warehouse_id': 2,
      'document_date': iso(1).substring(0, 10),
      'reference': 'SO-2026-000014',
      'reason': 'Loaded for SO-2026-000014',
      'lines': [
        {'product_id': 5, 'quantity': 120, 'batch_number': 'W500-261101'},
        {'product_id': 7, 'quantity': 8, 'batch_number': 'WC261023'},
      ],
    }, creator: 'Baraka Mollel');
    _post(issue, 'Neema Shirima');

    final transfer = _newDocument('transfer', {
      'warehouse_id': 2,
      'to_warehouse_id': 3,
      'document_date': iso(0).substring(0, 10),
      'reference': 'TRF to Arusha',
      'lines': [
        {'product_id': 6, 'quantity': 60, 'batch_number': 'W15-261028'},
      ],
    }, creator: 'Baraka Mollel');
    _post(transfer, 'Neema Shirima');

    // One draft waiting to be posted.
    _newDocument('grn', {
      'warehouse_id': 1,
      'supplier_id': 2,
      'document_date': iso(0).substring(0, 10),
      'reference': 'INV-KL-2231',
      'lines': [
        {'product_id': 3, 'quantity': 25000, 'unit_cost': 11.5},
      ],
    }, creator: 'Baraka Mollel');
  }

  Map<String, dynamic> _warehouse(int id, String code, String name, String type, String branch) => {
    'id': id,
    'company_id': 1,
    'code': code,
    'name': name,
    'type': type,
    'branch': branch,
    'location': null,
    'manager_user_id': null,
    'is_active': true,
    'manager': null,
  };

  Map<String, dynamic> _product(
    int id,
    String sku,
    String name,
    String type,
    int category,
    int unit,
    double cost,
    double sale,
    double reorder, {
    bool batches = false,
    bool expiry = false,
  }) => {
    'id': id,
    'company_id': 1,
    'sku': sku,
    'barcode': null,
    'name': name,
    'brand': null,
    'type': type,
    'category_id': category,
    'unit_id': unit,
    'cost_price': cost.toStringAsFixed(2),
    'sale_price': sale.toStringAsFixed(2),
    'reorder_level': reorder.toStringAsFixed(4),
    'track_batches': batches,
    'track_expiry': expiry,
    'track_serials': false,
    'custom_fields': null,
    'is_active': true,
  };

  /* ══════════════════════════════════════════════════════════ dispatch ══ */

  /// Answers one /erp request for [role]/[email], or [unhandled].
  Object? handle(
    String method,
    String path, {
    required String role,
    required String email,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
  }) {
    final perms = [..._permissions(role, email), if (!permissionsFor.containsKey(email)) ...MockOps.rolePermissions(role), if (!permissionsFor.containsKey(email)) ...MockPeople.rolePermissions(role), if (!permissionsFor.containsKey(email)) ...MockFinance.rolePermissions(role)];
    void need(String permission) {
      if (!perms.contains(permission)) {
        throw ApiException(403, 'Your role does not allow this.');
      }
    }

    void inventory() {
      if (!modules.contains('inventory')) {
        throw ApiException(403, 'The inventory module is not switched on for your company.');
      }
      need('inventory.view');
    }

    final seg = path.replaceFirst(RegExp(r'^/+'), '').split('/');
    // seg[0] == 'erp'
    final rest = seg.skip(1).toList();
    final head = rest.isEmpty ? '' : rest.first;
    // Fleet and HR live in their own fixture (mock_people.dart).
    if (head == 'fleet' || head == 'hr') {
      return people.handle(method, rest, perms: perms, modules: modules, email: email, body: body, query: query) ?? unhandled;
    }

    if (method == 'GET' && head == 'config') return {'data': _config(perms)};
    if (method == 'GET' && head == 'overview') return {'data': _overview(perms)};
    if (head == 'sales' || head == 'dispatch' || head == 'customers') {
      final answer = sales.handle(method, rest, perms: perms, modules: modules, email: email, body: body, query: query);
      if (!identical(answer, MockSales.unhandled)) return answer;
    }

    final money = finance.handle(method, rest, perms: perms, modules: modules, body: body, query: query);
    if (!identical(money, MockFinance.unhandled)) return money;

    if (head == 'suppliers' && method == 'GET') {
      if (!modules.contains('procurement')) throw ApiException(403, 'Procurement is not switched on.');
      need('suppliers.view');
      return {'data': _suppliers, 'current_page': 1, 'last_page': 1, 'total': _suppliers.length};
    }

    if (head == 'warehouses' && method == 'GET' && rest.length == 1) {
      inventory();
      return {'data': [for (final w in _warehouses) _warehouseJson(w)]};
    }

    if (head == 'products' && method == 'GET') {
      inventory();
      if (rest.length == 2) return {'data': _productDetail(int.tryParse(rest[1]) ?? 0)};
      return _productIndex(query);
    }

    if (head == 'stock' && method == 'GET' && rest.length == 2) {
      inventory();
      return switch (rest[1]) {
        'balances' => _balanceIndex(query),
        'movements' => _movementIndex(query),
        'alerts' => {'data': _alerts()},
        _ => unhandled,
      };
    }

    if (head == 'stock-documents') {
      inventory();
      if (rest.length == 1 && method == 'GET') return _documentIndex(query);
      if (rest.length == 1 && method == 'POST') return _store(body, perms);
      final id = int.tryParse(rest.length > 1 ? rest[1] : '');
      final doc = _documents.where((d) => d['id'] == id).firstOrNull;
      if (doc == null) throw ApiException(404, 'Stock document not found.');
      if (rest.length == 2 && method == 'GET') return {'data': _documentJson(doc, detailed: true)};
      if (rest.length == 3 && method == 'POST') {
        switch (rest[2]) {
          case 'post':
            need('inventory.post');
            if (doc['status'] != 'draft') throw ApiException(422, 'Only a draft can be posted.');
            _post(doc, 'You');
            return {'message': '${doc['number']} posted.', 'data': _documentJson(doc, detailed: true)};
          case 'reverse':
            need('inventory.reverse');
            final reason = '${body['reason'] ?? ''}'.trim();
            if (reason.length < 3) {
              throw ApiException(422, 'Give a reason of at least 3 characters.', {
                'reason': ['Give a reason of at least 3 characters.'],
              });
            }
            final reversal = _reverse(doc, reason);
            return {'message': '${doc['number']} reversed by ${reversal['number']}.', 'data': _documentJson(reversal, detailed: true)};
          case 'cancel':
            need(_preparePermission['${doc['type']}']!);
            if (doc['status'] != 'draft') throw ApiException(422, 'Only a draft can be cancelled.');
            doc['status'] = 'cancelled';
            return {'message': 'Draft cancelled.', 'data': _documentJson(doc, detailed: true)};
        }
      }
    }

    final fromOps = ops.handle(method, rest, perms: perms, modules: modules, body: body, query: query);
    if (!identical(fromOps, MockOps.unhandled)) return fromOps;
    return unhandled;
  }

  static const _preparePermission = {
    'opening': 'inventory.receive',
    'grn': 'inventory.receive',
    'issue': 'inventory.issue',
    'transfer': 'inventory.transfer',
    'adjustment': 'inventory.adjust',
    'count': 'inventory.adjust',
  };

  Map<String, dynamic> _config(List<String> perms) => {
    'business_type': 'beverage',
    'business_label': 'Beverage factory & depot',
    'is_set_up': isSetUp,
    'setup_completed_at': isSetUp ? iso(30) : null,
    'modules': modules,
    'licensed_modules': licensedModules,
    'live_modules': liveModules,
    'settings': {
      'allow_negative_stock': false,
      'costing_method': 'weighted_average',
      'base_currency': 'TZS',
      'default_tax_rate': 18,
      'fiscal_year_start': '01-01',
      'expiry_alert_days': 60,
      'product_fields': [],
      'product_defaults': {'track_expiry': true, 'track_batches': true, 'track_serials': false},
    },
    'permissions': isSetUp ? perms : perms.where((p) => p == 'erp.configure').toList(),
  };

  Map<String, dynamic> _overview(List<String> perms) {
    final out = <String, dynamic>{'is_set_up': isSetUp, 'modules': modules};
    if (modules.contains('inventory') && perms.contains('inventory.view')) {
      final days = <String, int>{};
      for (final m in _movements) {
        final day = '${m['movement_date']}'.substring(0, 10);
        days[day] = (days[day] ?? 0) + 1;
      }
      final recent = _documents.reversed.where((d) => d['type'] != 'opening').take(6);
      out['inventory'] = {
        'stock_value': _balances.fold<double>(0, (s, b) => s + b.qty * b.cost),
        'products': _products.where((p) => p['is_active'] == true).length,
        'warehouses': _warehouses.length,
        'low_stock': _lowStock().length,
        'drafts': _documents.where((d) => d['status'] == 'draft').length,
        'movements_7d': [
          for (var i = 6; i >= 0; i--)
            if (days[iso(i).substring(0, 10)] case final n?) {'day': iso(i).substring(0, 10), 'count': n},
        ],
        'recent': [
          for (final d in recent)
            {
              'id': d['id'],
              'number': d['number'],
              'type': d['type'],
              'status': d['status'],
              'warehouse_id': d['warehouse_id'],
              'document_date': '${d['document_date']}T00:00:00.000000Z',
              'warehouse': _ref(_warehouseById(d['warehouse_id'] as int)),
            },
        ],
      };
    }
    return out;
  }

  /* ════════════════════════════════════════════════════════ inventory ══ */

  Map<String, dynamic> _warehouseById(int id) => _warehouses.firstWhere((w) => w['id'] == id);

  Map<String, dynamic> _productById(int id) {
    final p = _products.where((p) => p['id'] == id).firstOrNull;
    if (p == null) throw ApiException(404, 'Product not found.');
    return p;
  }

  Map<String, dynamic> _ref(Map<String, dynamic> m) => {'id': m['id'], 'code': m['code'], 'name': m['name']};

  double _onHand(int productId, [int? warehouseId]) => _balances
      .where((b) => b.productId == productId && (warehouseId == null || b.warehouseId == warehouseId))
      .fold<double>(0, (s, b) => s + b.qty);

  Map<String, dynamic> _warehouseJson(Map<String, dynamic> w) {
    final held = _balances.where((b) => b.warehouseId == w['id'] && b.qty != 0);
    return {
      ...w,
      'stock_value': held.fold<double>(0, (s, b) => s + b.qty * b.cost),
      'products_held': held.map((b) => b.productId).toSet().length,
    };
  }

  Map<String, dynamic> _productJson(Map<String, dynamic> p) => {
    ...p,
    'on_hand': _onHand(p['id'] as int).toStringAsFixed(4),
    'category': {'id': p['category_id'], 'name': _categories[p['category_id']]},
    'unit': _units[p['unit_id']],
  };

  bool _matches(Map<String, dynamic> p, String q) =>
      '${p['name']}'.toLowerCase().contains(q) || '${p['sku']}'.toLowerCase().contains(q);

  Map<String, dynamic> _paginate(List<Map<String, dynamic>> rows, Map<String, dynamic> query, int perPageDefault) {
    final perPage = int.tryParse('${query['per_page'] ?? ''}') ?? perPageDefault;
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

  Map<String, dynamic> _productIndex(Map<String, dynamic> query) {
    final q = '${query['q'] ?? ''}'.trim().toLowerCase();
    final rows = _products
        .where((p) => q.isEmpty || _matches(p, q))
        .where((p) => '${query['active_only']}' != '1' || p['is_active'] == true)
        .map(_productJson)
        .toList()
      ..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
    return _paginate(rows, query, 50);
  }

  Map<String, dynamic> _productDetail(int id) {
    final p = _productById(id);
    final held = _balances.where((b) => b.productId == id && b.qty != 0).toList();
    return {
      ..._productJson(p),
      'on_hand': _onHand(id),
      'stock_value': held.fold<double>(0, (s, b) => s + b.qty * b.cost),
      'balances': [
        for (final b in held) {..._balanceJson(b), 'warehouse': _ref(_warehouseById(b.warehouseId))},
      ],
      'movements': [
        for (final m in _movements.reversed.where((m) => m['product_id'] == id).take(20)) _movementJson(m),
      ],
    };
  }

  Map<String, dynamic> _balanceJson(_Balance b) {
    final p = _productById(b.productId);
    return {
      'id': b.id,
      'company_id': 1,
      'product_id': b.productId,
      'warehouse_id': b.warehouseId,
      'batch_number': b.batch,
      'expiry_date': b.expiry == null ? null : '${b.expiry}T00:00:00.000000Z',
      'quantity': b.qty.toStringAsFixed(4),
      'average_cost': b.cost.toStringAsFixed(4),
      'product': {
        'id': p['id'],
        'sku': p['sku'],
        'name': p['name'],
        'unit_id': p['unit_id'],
        'reorder_level': p['reorder_level'],
        'unit': {'id': p['unit_id'], 'code': _units[p['unit_id']]!['code']},
      },
      'warehouse': _ref(_warehouseById(b.warehouseId)),
      'value': b.qty * b.cost,
    };
  }

  Map<String, dynamic> _balanceIndex(Map<String, dynamic> query) {
    final q = '${query['q'] ?? ''}'.trim().toLowerCase();
    final wh = int.tryParse('${query['warehouse_id'] ?? ''}');
    final product = int.tryParse('${query['product_id'] ?? ''}');
    final rows = _balances
        .where((b) => b.qty != 0 || '${query['include_zero']}' == '1')
        .where((b) => wh == null || b.warehouseId == wh)
        .where((b) => product == null || b.productId == product)
        .where((b) => q.isEmpty || _matches(_productById(b.productId), q))
        .map(_balanceJson)
        .toList()
      ..sort((a, b) => '${(a['product'] as Map)['name']}'.compareTo('${(b['product'] as Map)['name']}'));
    return _paginate(rows, query, 50);
  }

  Map<String, dynamic> _movementJson(Map<String, dynamic> m) => {
    ...m,
    'warehouse': {'id': m['warehouse_id'], 'name': _warehouseById(m['warehouse_id'] as int)['name']},
    'product': _ref(_productById(m['product_id'] as int)),
  };

  Map<String, dynamic> _movementIndex(Map<String, dynamic> query) {
    final wh = int.tryParse('${query['warehouse_id'] ?? ''}');
    final rows = _movements.reversed.where((m) => wh == null || m['warehouse_id'] == wh).map(_movementJson).toList();
    return _paginate(rows, query, 50);
  }

  List<Map<String, dynamic>> _lowStock() => [
    for (final p in _products)
      if (double.parse('${p['reorder_level']}') > 0 && _onHand(p['id'] as int) <= double.parse('${p['reorder_level']}'))
        _productJson(p),
  ];

  Map<String, dynamic> _alerts() => {'low_stock': _lowStock(), 'expiring': [], 'expiry_window_days': 60};

  /* ═══════════════════════════════════════════════════════════ documents ══ */

  static const _prefix = {
    'opening': 'OPN',
    'grn': 'GRN',
    'issue': 'ISS',
    'transfer': 'TRF',
    'adjustment': 'ADJ',
    'count': 'CNT',
  };

  Map<String, dynamic> _newDocument(String type, Map<String, dynamic> body, {required String creator}) {
    final n = (_sequence[type] ?? 0) + 1;
    _sequence[type] = n;
    final id = _nextDocument++;
    final doc = <String, dynamic>{
      'id': id,
      'company_id': 1,
      'type': type,
      'number': '${_prefix[type]}-${DateTime.now().year}-${'$n'.padLeft(6, '0')}',
      'document_date': '${body['document_date'] ?? iso(0).substring(0, 10)}'.substring(0, 10),
      'status': 'draft',
      'warehouse_id': body['warehouse_id'],
      'to_warehouse_id': body['to_warehouse_id'],
      'supplier_id': body['supplier_id'],
      'reference': body['reference'],
      'reason': body['reason'],
      'notes': null,
      'reversal_of_id': null,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'posted_at': null,
      'creator': {'id': 2, 'name': creator},
      'poster': null,
      'lines': [
        for (final raw in (body['lines'] as List))
          {
            'id': _nextLine++,
            'stock_document_id': id,
            'product_id': (raw as Map)['product_id'],
            'quantity': double.parse('${raw['quantity']}').toStringAsFixed(4),
            'unit_cost': raw['unit_cost'] == null ? null : double.parse('${raw['unit_cost']}').toStringAsFixed(2),
            'batch_number': raw['batch_number'] ?? '',
            'expiry_date': raw['expiry_date'],
            'serial_number': raw['serial_number'],
            'system_quantity': null,
            'note': raw['note'],
          },
      ],
    };
    _documents.add(doc);
    return doc;
  }

  Map<String, dynamic> _store(Map<String, dynamic> body, List<String> perms) {
    final type = '${body['type'] ?? ''}';
    final permission = _preparePermission[type];
    if (permission == null) {
      throw ApiException(422, 'The selected type is invalid.', {'type': ['The selected type is invalid.']});
    }
    if (!perms.contains(permission)) {
      throw ApiException(403, 'Your role does not allow you to prepare this kind of stock document.');
    }
    final errors = <String, List<String>>{};
    final wh = body['warehouse_id'];
    if (wh == null || !_warehouses.any((w) => w['id'] == wh)) {
      errors['warehouse_id'] = ['The warehouse field is required.'];
    }
    if (type == 'transfer' && (body['to_warehouse_id'] == null || body['to_warehouse_id'] == wh)) {
      errors['to_warehouse_id'] = ['Choose a different warehouse to move the stock to.'];
    }
    final lines = (body['lines'] as List?) ?? const [];
    if (lines.isEmpty) errors['lines'] = ['Add at least one line.'];
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i] as Map;
      if (!_products.any((p) => p['id'] == l['product_id'])) {
        errors['lines.$i.product_id'] = ['Choose a product.'];
      }
      if (double.tryParse('${l['quantity']}') == null) {
        errors['lines.$i.quantity'] = ['Enter a quantity.'];
      }
    }
    if (errors.isNotEmpty) throw ApiException(422, errors.values.first.first, errors);
    return {'data': _documentJson(_newDocument(type, body, creator: 'You'), detailed: true)};
  }

  _Balance _balance(int productId, int warehouseId, String batch, {String? expiry, double cost = 0}) {
    final found = _balances
        .where((b) => b.productId == productId && b.warehouseId == warehouseId && b.batch == batch)
        .firstOrNull;
    if (found != null) return found;
    final created = _Balance(_nextBalance++, productId, warehouseId, batch, expiry, 0, cost);
    _balances.add(created);
    return created;
  }

  void _move(Map<String, dynamic> doc, Map<String, dynamic> line, int warehouseId, double qty, String type) {
    final productId = line['product_id'] as int;
    final batch = '${line['batch_number'] ?? ''}';
    final product = _productById(productId);
    final explicit = line['unit_cost'] == null ? null : double.parse('${line['unit_cost']}');
    final b = _balance(productId, warehouseId, batch,
        expiry: line['expiry_date'] as String?, cost: explicit ?? double.parse('${product['cost_price']}'));
    if (qty > 0 && explicit != null) {
      // Weighted average: what is already there blended with what arrives.
      final total = b.qty + qty;
      b.cost = total == 0 ? explicit : (b.qty * b.cost + qty * explicit) / total;
    }
    if (qty < 0 && b.qty + qty < 0) {
      throw ApiException(422, 'Not enough ${product['name']} in stock to post this document.');
    }
    b.qty += qty;
    _movements.add({
      'id': _nextMovement++,
      'company_id': 1,
      'product_id': productId,
      'warehouse_id': warehouseId,
      'batch_number': batch,
      'expiry_date': line['expiry_date'],
      'type': type,
      'quantity': qty.toStringAsFixed(4),
      'unit_cost': b.cost.toStringAsFixed(2),
      'value': (qty * b.cost).toStringAsFixed(2),
      'balance_after': _onHand(productId, warehouseId).toStringAsFixed(4),
      'stock_document_id': doc['id'],
      'reference': doc['number'],
      'reason': doc['reason'],
      'movement_date': '${doc['document_date']}T00:00:00.000000Z',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'creator': doc['creator'],
    });
  }

  void _post(Map<String, dynamic> doc, String poster) {
    final type = doc['type'] as String;
    final wh = doc['warehouse_id'] as int;
    for (final line in (doc['lines'] as List).cast<Map<String, dynamic>>()) {
      final qty = double.parse('${line['quantity']}');
      switch (type) {
        case 'opening' || 'grn':
          _move(doc, line, wh, qty, type);
        case 'issue':
          _move(doc, line, wh, -qty, 'issue');
        case 'adjustment':
          _move(doc, line, wh, qty, 'adjustment');
        case 'transfer':
          _move(doc, line, wh, -qty, 'transfer_out');
          _move(doc, line, doc['to_warehouse_id'] as int, qty, 'transfer_in');
        case 'count':
          // Only the difference between the shelf and the books is posted.
          final batch = '${line['batch_number'] ?? ''}';
          final system = _balances
              .where((b) => b.productId == line['product_id'] && b.warehouseId == wh && b.batch == batch)
              .fold<double>(0, (s, b) => s + b.qty);
          line['system_quantity'] = system.toStringAsFixed(4);
          if (qty != system) _move(doc, line, wh, qty - system, 'count');
      }
    }
    doc['status'] = 'posted';
    doc['posted_at'] = DateTime.now().toUtc().toIso8601String();
    doc['poster'] = {'id': 2, 'name': poster};
  }

  Map<String, dynamic> _reverse(Map<String, dynamic> doc, String reason) {
    if (doc['status'] != 'posted' || doc['reversal_of_id'] != null) {
      throw ApiException(422, 'Only a posted document can be reversed.');
    }
    final type = doc['type'] as String;
    // The reversing document moves every quantity back: an adjustment of
    // the opposite sign, or a transfer the other way.
    final reversal = _newDocument(type == 'transfer' ? 'transfer' : 'adjustment', {
      'warehouse_id': type == 'transfer' ? doc['to_warehouse_id'] : doc['warehouse_id'],
      'to_warehouse_id': type == 'transfer' ? doc['warehouse_id'] : null,
      'reference': doc['number'],
      'reason': reason,
      'lines': [
        for (final m in _movements.where((m) => m['stock_document_id'] == doc['id'] && m['type'] != 'transfer_in'))
          {
            'product_id': m['product_id'],
            'quantity': -double.parse('${m['quantity']}'),
            'unit_cost': double.parse('${m['unit_cost']}'),
            'batch_number': m['batch_number'],
          },
      ],
    }, creator: 'You');
    reversal['reversal_of_id'] = doc['id'];
    _post(reversal, 'You');
    doc['status'] = 'reversed';
    return reversal;
  }

  Map<String, dynamic> _documentJson(Map<String, dynamic> d, {bool detailed = false}) {
    final to = d['to_warehouse_id'] as int?;
    final supplier = _suppliers.where((s) => s['id'] == d['supplier_id']).firstOrNull;
    final reversalOf = _documents.where((x) => x['id'] == d['reversal_of_id']).firstOrNull;
    final lines = (d['lines'] as List).cast<Map<String, dynamic>>();
    return {
      ...d,
      'document_date': '${d['document_date']}T00:00:00.000000Z',
      'lines_count': lines.length,
      'warehouse': _ref(_warehouseById(d['warehouse_id'] as int)),
      'to_warehouse': to == null ? null : _ref(_warehouseById(to)),
      'supplier': supplier,
      'reversal_of': reversalOf == null ? null : {'id': reversalOf['id'], 'number': reversalOf['number']},
      if (detailed)
        'lines': [
          for (final l in lines)
            {
              ...l,
              'product': {
                ..._ref(_productById(l['product_id'] as int)),
                'sku': _productById(l['product_id'] as int)['sku'],
                'track_batches': _productById(l['product_id'] as int)['track_batches'],
                'track_expiry': _productById(l['product_id'] as int)['track_expiry'],
                'track_serials': false,
                'unit': _units[_productById(l['product_id'] as int)['unit_id']],
              },
            },
        ]
      else
        'lines': null,
      if (detailed)
        'movements': [
          for (final m in _movements.where((m) => m['stock_document_id'] == d['id'])) _movementJson(m),
        ],
    };
  }

  Map<String, dynamic> _documentIndex(Map<String, dynamic> query) {
    final q = '${query['q'] ?? ''}'.trim().toLowerCase();
    final rows = _documents.reversed
        .where((d) => query['type'] == null || '${query['type']}'.isEmpty || d['type'] == query['type'])
        .where((d) => query['status'] == null || '${query['status']}'.isEmpty || d['status'] == query['status'])
        .where((d) =>
            q.isEmpty ||
            '${d['number']}'.toLowerCase().contains(q) ||
            '${d['reference'] ?? ''}'.toLowerCase().contains(q))
        .map((d) => _documentJson(d))
        .toList();
    return _paginate(rows, query, 30);
  }

  /// Every document, newest last, for tests to inspect.
  List<Map<String, dynamic>> get documents => List.unmodifiable(_documents);
}

class _Balance {
  _Balance(this.id, this.productId, this.warehouseId, this.batch, this.expiry, this.qty, this.cost);

  final int id, productId, warehouseId;
  final String batch;
  final String? expiry;
  double qty, cost;
}
