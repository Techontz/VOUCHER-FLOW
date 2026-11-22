import '../services/api_service.dart';

/// The in-app stand-in for /api/erp/production, /api/erp/crm and
/// /api/erp/files, answering with the same JSON shapes as the Laravel
/// controllers (ProductionOrderController, QcController, BomController,
/// LeadController, OpportunityController, ActivityController,
/// FolderController, DocumentController). Actions change the fixture, so a
/// released order, a moved deal or a completed follow-up reads back the way
/// it would against the server.
class MockOps {
  MockOps() {
    _seed();
  }

  /// Returned by [handle] for a path this fixture does not answer.
  static const unhandled = Object();

  static const production = [
    'production.view', 'production.manage', 'production.plan', 'production.issue', //
    'production.receive', 'production.qc', 'production.close',
  ];
  static const crm = ['crm.view', 'crm.view_all', 'crm.manage', 'crm.assign'];
  static const documents = ['documents.view', 'documents.upload', 'documents.manage', 'documents.delete'];

  /// What a built-in role holds in these three modules (backend
  /// app/Support/Erp/Modules/Production.php and Crm.php, trimmed).
  static List<String> rolePermissions(String role) => switch (role) {
    'company_admin' => [...production, ...crm, ...documents],
    'ceo' || 'director' => ['production.view', 'crm.view', 'crm.view_all', 'crm.assign', 'documents.view', 'documents.upload'],
    'finance' => ['production.view', 'production.close', 'documents.view', 'documents.upload'],
    'hod' || 'manager' => ['crm.view', 'crm.view_all', 'crm.assign', 'documents.view', 'documents.upload'],
    _ => const [],
  };

  static String _today([int days = 0]) {
    final d = DateTime.now().add(Duration(days: days));
    return '${d.year}-${'${d.month}'.padLeft(2, '0')}-${'${d.day}'.padLeft(2, '0')}T00:00:00.000000Z';
  }

  static String _at([int days = 0, int hour = 9]) {
    final d = DateTime.now().add(Duration(days: days));
    return DateTime.utc(d.year, d.month, d.day, hour).toIso8601String();
  }

  /* ═════════════════════════════════════════════════════ the dataset ══ */

  final orders = <Map<String, dynamic>>[];
  final receipts = <Map<String, dynamic>>[];
  final boms = <Map<String, dynamic>>[];
  final leads = <Map<String, dynamic>>[];
  final deals = <Map<String, dynamic>>[];
  final activities = <Map<String, dynamic>>[];
  final folders = <Map<String, dynamic>>[];
  final files = <Map<String, dynamic>>[];
  int _next = 100;

  static const _p500 = {'id': 5, 'sku': 'FG-W500-24', 'name': 'Watercom 500ml × 24', 'unit': {'id': 1, 'code': 'CTN', 'name': 'Carton'}, 'track_batches': true, 'track_expiry': true};
  static const _p1500 = {'id': 6, 'sku': 'FG-W1500-12', 'name': 'Watercom 1.5L × 12', 'unit': {'id': 1, 'code': 'CTN', 'name': 'Carton'}, 'track_batches': true, 'track_expiry': true};
  static const _main = {'id': 1, 'code': 'MAIN', 'name': 'Factory store Mbezi'};
  static const _fgw = {'id': 2, 'code': 'FGW', 'name': 'Finished goods warehouse'};
  static const _zuberi = {'id': 75, 'name': 'Zuberi Mwakyusa'};
  static const _hassan = {'id': 63, 'name': 'Hassan Juma'};
  static const _zawadi = {'id': 78, 'name': 'Zawadi Mrema'};
  static const _neema = {'id': 2, 'name': 'Neema Shirima'};

  Map<String, dynamic> _order(int id, Map<String, dynamic> product, String status, num planned, num released, int startIn) => {
    'id': id,
    'number': 'PRD-2026-${'$id'.padLeft(6, '0')}',
    'product_id': product['id'],
    'bom_id': product['id'] == 5 ? 2 : 3,
    'planned_quantity': '$planned.000',
    'produced_quantity': '${released == 0 ? 0 : released + 9}.000',
    'good_quantity': '${released == 0 ? 0 : released + 4}.000',
    'released_quantity': '$released.000',
    'rejected_quantity': released == 0 ? '0.000' : '5.000',
    'wastage_quantity': released == 0 ? '0.000' : '4.000',
    'planned_start': _today(startIn),
    'planned_end': _today(startIn + 2),
    'status': status,
    'reference': id == 7 ? 'Festive season stock' : null,
    'notes': null,
    'created_at': _at(-5),
    'released_at': status == 'planned' ? null : _at(startIn),
    'started_at': status == 'in_progress' ? _at(startIn, 10) : null,
    'product': product,
    'bom': {'id': product['id'] == 5 ? 2 : 3, 'version': product['id'] == 5 ? 2 : 1, 'name': '${product['name']} v1', 'work_centre': {'id': 1, 'code': 'LINE-1', 'name': 'Line 1: 500ml blow, fill and cap'}},
    'materials_warehouse': _main,
    'output_warehouse': _fgw,
    'creator': _zuberi,
    'releaser': status == 'planned' ? null : _zuberi,
  };

  void _seed() {
    orders.addAll([
      _order(7, _p500, 'in_progress', 800, 543, -3),
      _order(8, _p1500, 'released', 300, 0, 0),
      _order(10, _p500, 'planned', 700, 0, 3),
      _order(4, _p500, 'completed', 500, 492, -12),
    ]);
    receipts.addAll([
      {
        'id': 7, 'production_order_id': 7, 'number': 'PRC-2026-000007', 'receipt_date': _today(-2),
        'produced_quantity': '300.000', 'good_quantity': '296.000', 'rejected_quantity': '2.000', 'wastage_quantity': '2.000',
        'released_quantity': '296.000', 'batch_number': 'W500-261110-A', 'expiry_date': _today(363), 'is_final': false,
        'status': 'released', 'unit_cost': '3464.12', 'recorder': {'id': 60, 'name': 'Neema Swai'},
        'qc': {'decision': 'release', 'parameters': [{'name': 'pH', 'value': '7.2', 'passed': true, 'target': '6.5 to 8.5'}], 'inspector': {'id': 76, 'name': 'Salome Kisanga'}},
        'stock_document': {'id': 41, 'number': 'GRN-2026-000018', 'status': 'posted'},
      },
      {
        'id': 9, 'production_order_id': 7, 'number': 'PRC-2026-000009', 'receipt_date': _today(),
        'produced_quantity': '400.000', 'good_quantity': '395.000', 'rejected_quantity': '3.000', 'wastage_quantity': '2.000',
        'released_quantity': '0.000', 'batch_number': 'W500-261112-B', 'expiry_date': _today(365), 'is_final': false,
        'status': 'pending_qc', 'unit_cost': null, 'recorder': {'id': 60, 'name': 'Neema Swai'}, 'qc': null,
      },
    ]);
    boms.addAll([
      {
        'id': 2, 'product_id': 5, 'version': 2, 'name': 'Watercom 500ml × 24 v2', 'output_quantity': '100.000',
        'labour_cost': '18000.00', 'overhead_cost': '12000.00', 'is_active': true, 'lines_count': 2, 'orders_count': 6,
        'notes': '24 bottles per carton.', 'product': _p500, 'work_centre': {'id': 1, 'code': 'LINE-1', 'name': 'Line 1: 500ml blow, fill and cap'},
        'standard_cost': 3473.0417,
        'lines': [
          {'product_id': 1, 'quantity': '2400.0000', 'scrap_percent': '1.50', 'product': {'id': 1, 'sku': 'RM-PRF-28', 'name': 'PET preform 28g', 'unit': {'code': 'PCS'}}},
          {'product_id': 2, 'quantity': '2400.0000', 'scrap_percent': '1.00', 'product': {'id': 2, 'sku': 'RM-CAP-28', 'name': 'Bottle cap 28mm', 'unit': {'code': 'PCS'}}},
        ],
        'standard': {'materials': 3173.04, 'conversion': 300, 'unit_cost': 3473.04, 'lines': [
          {'product_id': 1, 'per_unit': 24.36, 'cost_per_unit': 2351.75},
          {'product_id': 2, 'per_unit': 24.24, 'cost_per_unit': 432.24},
        ]},
        'versions': [{'id': 2, 'version': 2, 'is_active': true}, {'id': 1, 'version': 1, 'is_active': false}],
      },
    ]);

    leads.addAll([
      {
        'id': 7, 'number': 'LEAD-2026-000007', 'contact_name': 'Neema Laizer', 'company_name': 'Laizer Safari Camps',
        'phone': '+255 768 223 145', 'email': 'neema.laizer@example.co.tz', 'region': 'Arusha', 'source': 'trade_show',
        'status': 'contacted', 'estimated_value': '11000000.00', 'notes': null, 'lost_reason': null, 'owner': _zawadi,
        'customer': null, 'opportunity_id': null, 'opportunity': null, 'created_at': _at(-9),
      },
      {
        'id': 17, 'number': 'LEAD-2026-000017', 'contact_name': 'Sophia Temba', 'company_name': 'Temba Mini Market',
        'phone': '+255 754 100 200', 'email': null, 'region': 'Dar es Salaam', 'source': 'walk_in',
        'status': 'new', 'estimated_value': '2500000.00', 'notes': null, 'lost_reason': null, 'owner': _zawadi,
        'customer': null, 'opportunity_id': null, 'opportunity': null, 'created_at': _at(-4),
      },
    ]);
    deals.addAll([
      _deal(6, 'Kariakoo Wholesalers: Q1 volume contract', 'negotiation', 42000000, 70, 12, 'Kariakoo Wholesalers Ltd', _hassan),
      _deal(7, 'Serena Hotel: 19L dispensers', 'prospecting', 9600000, 10, 55, 'Serena Hotel Dar es Salaam', _hassan),
      _deal(2, 'Said & Sons Wholesale: monthly water supply', 'proposal', 18500000, 40, 20, 'Said & Sons Wholesale', _hassan),
      _deal(3, 'Mollel General Supplies: monthly supply', 'won', 6800000, 100, -3, 'Mollel General Supplies', _zawadi),
    ]);
    activities.addAll([
      _activity(1, 'call', 'Confirm delivery schedule with procurement', _at(0, 10), opp: 6),
      _activity(3, 'visit', 'Site visit: Laizer Safari Camps', _at(0, 11), lead: 7),
      _activity(7, 'call', 'Chase signed agreement', _at(-5, 10), opp: 2),
    ]);

    folders.addAll([
      {'id': 1, 'parent_id': null, 'name': 'Company', 'description': 'Registration, profile and statutory records', 'documents_count': 1},
      {'id': 3, 'parent_id': null, 'name': 'Licences & permits', 'description': 'TBS, TMDA, business licence, fire and water permits', 'documents_count': 2},
    ]);
    files.addAll([
      _file(6, 3, 'Fire safety certificate', 'certificate', issued: -370, expires: -5, name: 'fire-safety-certificate.pdf'),
      _file(7, 3, 'TBS product certification', 'licence', issued: -340, expires: 24, name: 'tbs-certification.pdf'),
      _file(2, 1, 'Certificate of incorporation', 'certificate', issued: -2000, name: 'incorporation.pdf'),
    ]);
  }

  Map<String, dynamic> _deal(int id, String title, String stage, num value, int probability, int closeIn, String customer, Map owner) => {
    'id': id, 'number': 'OPP-2026-${'$id'.padLeft(6, '0')}', 'title': title, 'stage': stage, 'value': '$value.00',
    'probability': probability, 'expected_close_date': _today(closeIn), 'owner': owner, 'customer_id': id + 10,
    'customer': {'id': id + 10, 'code': 'CUS-00$id', 'name': customer, 'phone': '+255 22 211 0000', 'email': null},
    'lead': null, 'lead_id': null, 'close_reason': null, 'close_note': null, 'notes': null, 'created_at': _at(-30),
    'closed_at': stage == 'won' || stage == 'lost' ? _at(-3) : null,
  };

  Map<String, dynamic> _activity(int id, String type, String subject, String due, {int? lead, int? opp}) => {
    'id': id, 'type': type, 'subject': subject, 'notes': null, 'due_at': due, 'completed_at': null, 'outcome': null,
    'lead_id': lead, 'opportunity_id': opp, 'customer_id': null, 'owner': _hassan,
    'lead': lead == null ? null : {'id': lead, 'number': 'LEAD-2026-${'$lead'.padLeft(6, '0')}', 'contact_name': leads.where((l) => l['id'] == lead).firstOrNull?['contact_name'] ?? 'Neema Laizer'},
    'opportunity': opp == null ? null : {'id': opp, 'number': 'OPP-2026-${'$opp'.padLeft(6, '0')}', 'title': deals.where((d) => d['id'] == opp).firstOrNull?['title']},
    'customer': null,
  };

  Map<String, dynamic> _file(int id, int folder, String title, String type, {int? issued, int? expires, required String name}) => {
    'id': id, 'folder_id': folder, 'title': title, 'document_type': type, 'tags': <String>[], 'description': null,
    'reference': 'REF-$id', 'issued_on': issued == null ? null : _today(issued), 'expires_on': expires == null ? null : _today(expires),
    'current_version': 1, 'owner': _neema, 'creator': _neema, 'created_at': _at(-20),
    'folder': {'id': folder, 'name': folders.firstWhere((f) => f['id'] == folder)['name']},
    'latest_version': {'version': 1, 'original_name': name, 'mime_type': 'application/pdf', 'size_bytes': 48210, 'created_at': _at(-20)},
  };

  Map<String, dynamic> _page(List<Map<String, dynamic>> rows) => {'data': rows, 'current_page': 1, 'last_page': 1, 'total': rows.length};

  /* ════════════════════════════════════════════════════════ dispatch ══ */

  /// Answers one request under /erp ([rest] is the path after it), or
  /// [unhandled].
  Object? handle(
    String method,
    List<String> rest, {
    required List<String> perms,
    required List<String> modules,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
  }) {
    if (rest.isEmpty) return unhandled;
    void gate(String module, String permission) {
      if (!modules.contains(module)) throw ApiException(403, 'This module is not switched on for your company.');
      if (!perms.contains(permission)) throw ApiException(403, 'Your role does not allow this.');
    }

    final head = rest.first;
    final tail = rest.skip(1).toList();
    if (head == 'production') {
      gate('production', 'production.view');
      return _production(method, tail, perms, body, query);
    }
    if (head == 'crm') {
      gate('crm', 'crm.view');
      return _crm(method, tail, perms, body, query);
    }
    if (head == 'files') {
      gate('documents', 'documents.view');
      return _files(method, tail, query);
    }
    return unhandled;
  }

  void _need(List<String> perms, String p) {
    if (!perms.contains(p)) throw ApiException(403, 'Your role does not allow this.');
  }

  /* ─────────────────────────────────────────────────────── production ── */

  Map<String, dynamic> _orderDetail(Map<String, dynamic> o) {
    final released = double.parse('${o['released_quantity']}');
    final planned = double.parse('${o['planned_quantity']}');
    return {
      ...o,
      'receipts': [for (final r in receipts) if (r['production_order_id'] == o['id']) r],
      'requirements': [
        {
          'product_id': 1, 'product': {'id': 1, 'sku': 'RM-PRF-28', 'name': 'PET preform 28g', 'track_batches': true, 'unit': 'PCS', 'allows_decimals': false},
          'required_quantity': planned * 24.36, 'issued_quantity': released * 24, 'remaining_quantity': (planned * 24.36 - released * 24).clamp(0, 1e9),
          'available_quantity': 76000, 'shortfall_quantity': 0, 'sufficient': true,
          'batches': [{'batch_number': 'PRF-2410', 'expiry_date': null, 'quantity': 40000}],
        },
        {
          'product_id': 2, 'product': {'id': 2, 'sku': 'RM-CAP-28', 'name': 'Bottle cap 28mm', 'track_batches': false, 'unit': 'PCS', 'allows_decimals': false},
          'required_quantity': planned * 24.24, 'issued_quantity': released * 24, 'remaining_quantity': (planned * 24.24 - released * 24).clamp(0, 1e9),
          'available_quantity': 9000, 'shortfall_quantity': 1000, 'sufficient': planned * 24.24 - released * 24 <= 9000,
          'batches': <Map>[],
        },
      ],
      'issues': released == 0
          ? <Map>[]
          : [
              {'id': 40, 'number': 'ISS-2026-000018', 'document_date': _today(-3), 'status': 'posted', 'creator': {'id': 60, 'name': 'Neema Swai'}, 'value': 1494041.35,
               'lines': [{'product': {'id': 1, 'name': 'PET preform 28g'}, 'quantity': 11693, 'batch_number': 'B261108'}]},
            ],
      'costing': {
        'standard_unit_cost': 3464.12, 'material_cost': 2489950.34, 'conversion_cost': 210000, 'actual_total': 2699950.34,
        'actual_unit_cost': released == 0 ? null : 4972.28, 'received_value': released * 3464.12, 'wip_balance': 818933.18,
        'variance_value': null, 'yield_percent': released == 0 ? null : 77.6,
      },
    };
  }

  Object? _production(String method, List<String> r, List<String> perms, Map<String, dynamic> body, Map<String, dynamic> query) {
    final what = r.isEmpty ? '' : r.first;
    if (method == 'GET' && what == 'overview') {
      final now = DateTime.now();
      return {
        'data': {
          'by_status': {for (final s in ['planned', 'released', 'in_progress', 'completed']) s: orders.where((o) => o['status'] == s).length},
          'open_orders': orders.where((o) => ['planned', 'released', 'in_progress'].contains(o['status'])).length,
          'today': {'produced': 400, 'released': 247, 'receipts': 2},
          'qc_pending': receipts.where((x) => x['status'] == 'pending_qc').length,
          'period': {'produced': 2900, 'released': 2607, 'rejected': 122, 'wastage': 23, 'yield_percent': 89.9, 'wastage_percent': 0.8, 'materials_issued_value': 9545984.63},
          'trend': [
            for (var i = 13; i >= 0; i--)
              {'date': _today(-i).substring(0, 10), 'produced': const [0, 0, 500, 0, 0, 100, 200, 0, 0, 0, 0, 300, 0, 400][13 - i], 'released': 0},
          ],
          'by_product': [
            {'name': _p500['name'], 'produced': 2300, 'released': 2117, 'yield_percent': 92},
            {'name': _p1500['name'], 'produced': 600, 'released': 490, 'yield_percent': 81.7},
          ],
          'recent_orders': [for (final o in orders) o],
          'generated': now.toIso8601String(),
        },
      };
    }
    if (method == 'GET' && what == 'options') {
      return {
        'data': {
          'finished': [_p500, _p1500],
          'warehouses': [_main, _fgw],
        },
      };
    }
    if (what == 'orders') {
      if (r.length == 1 && method == 'GET') {
        final status = query['status'];
        final q = '${query['q'] ?? ''}'.toLowerCase();
        return _page([
          for (final o in orders)
            if ((status == null ||
                    (status == 'open' ? ['planned', 'released', 'in_progress'].contains(o['status']) : o['status'] == status)) &&
                (q.isEmpty || '${o['number']} ${(o['product'] as Map)['name']}'.toLowerCase().contains(q)))
              o,
        ]);
      }
      if (r.length == 1 && method == 'POST') {
        _need(perms, 'production.plan');
        final product = body['product_id'] == 6 ? _p1500 : _p500;
        final o = _order(++_next, product, 'planned', (body['planned_quantity'] as num?) ?? 0, 0, 1);
        orders.insert(0, o);
        return {'message': '${o['number']} planned.', 'data': o};
      }
      if (r.length == 2 && r[1] == 'check' && method == 'POST') {
        final d = _orderDetail(_order(0, _p500, 'planned', (body['planned_quantity'] as num?) ?? 0, 0, 0));
        return {'data': {'bom': {'id': 2, 'version': 2}, 'standard': {'unit_cost': 3473.04}, 'requirements': d['requirements']}};
      }
      final o = orders.where((x) => '${x['id']}' == r[1]).firstOrNull;
      if (o == null) throw ApiException(404, 'Production order not found.');
      if (r.length == 2 && method == 'GET') return {'data': _orderDetail(o)};
      if (r.length == 3 && method == 'POST') {
        final status = o['status'];
        switch (r[2]) {
          case 'release':
            _need(perms, 'production.plan');
            if (status != 'planned') throw ApiException(422, '${o['number']} is not planned.');
            o['status'] = 'released';
            o['released_at'] = DateTime.now().toUtc().toIso8601String();
            o['releaser'] = _neema;
            return {'message': '${o['number']} released to production.', 'data': o};
          case 'cancel':
            _need(perms, 'production.plan');
            o['status'] = 'cancelled';
            o['cancel_reason'] = body['reason'];
            return {'message': '${o['number']} cancelled.', 'data': o};
          case 'complete':
            _need(perms, 'production.plan');
            o['status'] = 'completed';
            return {'message': '${o['number']} completed.', 'data': o};
          case 'close':
            _need(perms, 'production.close');
            o['status'] = 'closed';
            return {'message': '${o['number']} closed.', 'data': o};
          case 'issue':
            _need(perms, 'production.issue');
            o['status'] = 'in_progress';
            return {'message': 'Materials issued on ISS-2026-000099.', 'data': {'id': 99}};
          case 'receipts':
            _need(perms, 'production.receive');
            final rc = {
              'id': ++_next, 'production_order_id': o['id'], 'number': 'PRC-2026-${'$_next'.padLeft(6, '0')}', 'receipt_date': _today(),
              'produced_quantity': '${body['produced_quantity']}', 'good_quantity': '${body['good_quantity']}',
              'rejected_quantity': '${body['rejected_quantity'] ?? 0}', 'wastage_quantity': '${body['wastage_quantity'] ?? 0}',
              'released_quantity': '0', 'batch_number': body['batch_number'], 'expiry_date': body['expiry_date'],
              'is_final': body['is_final'] == true, 'status': 'pending_qc', 'recorder': _neema, 'qc': null,
            };
            receipts.add(rc);
            o['status'] = 'in_progress';
            return {'message': '${rc['number']} recorded and waiting for its quality check.', 'data': rc};
        }
      }
    }
    if (what == 'qc' && method == 'GET') {
      final status = query['status'] ?? 'pending_qc';
      return _page([
        for (final x in receipts)
          if (status == 'all' || x['status'] == status)
            {...x, 'order': {...orders.firstWhere((o) => o['id'] == x['production_order_id'])}},
      ]);
    }
    if (what == 'receipts' && r.length == 3 && r[2] == 'qc' && method == 'POST') {
      _need(perms, 'production.qc');
      final x = receipts.where((e) => '${e['id']}' == r[1]).firstOrNull;
      if (x == null) throw ApiException(404, 'Receipt not found.');
      final params = (body['parameters'] as List).cast<Map>();
      final release = body['decision'] == 'release';
      if (release && params.any((p) => p['passed'] != true)) {
        throw ApiException(422, '${params.firstWhere((p) => p['passed'] != true)['name']} failed: a batch with a failed parameter cannot be released.');
      }
      x['status'] = release ? 'released' : 'rejected';
      x['released_quantity'] = release ? x['good_quantity'] : '0';
      x['qc'] = {'decision': body['decision'], 'parameters': params, 'inspector': _neema};
      return {'message': release ? '${x['number']} released into stock.' : '${x['number']} rejected; nothing entered stock.', 'data': x['qc']};
    }
    if (what == 'boms' && method == 'GET') {
      if (r.length == 1) return _page(boms);
      final b = boms.where((e) => '${e['id']}' == r[1]).firstOrNull;
      if (b == null) throw ApiException(404, 'Bill of materials not found.');
      return {'data': b};
    }
    return unhandled;
  }

  /* ────────────────────────────────────────────────────────────── crm ── */

  Object? _crm(String method, List<String> r, List<String> perms, Map<String, dynamic> body, Map<String, dynamic> query) {
    final what = r.isEmpty ? '' : r.first;
    final open = ['prospecting', 'proposal', 'negotiation'];
    double v(Map d) => double.parse('${d['value']}');
    if (method == 'GET' && what == 'overview') {
      return {
        'data': {
          'stages': [
            for (final s in ['prospecting', 'proposal', 'negotiation', 'won', 'lost'])
              {
                'stage': s,
                'count': deals.where((d) => d['stage'] == s).length,
                'value': deals.where((d) => d['stage'] == s).fold<double>(0, (a, d) => a + v(d)),
                'weighted': deals.where((d) => d['stage'] == s).fold<double>(0, (a, d) => a + v(d) * (d['probability'] as int) / 100),
              },
          ],
          'open_value': deals.where((d) => open.contains(d['stage'])).fold<double>(0, (a, d) => a + v(d)),
          'weighted_value': deals.where((d) => open.contains(d['stage'])).fold<double>(0, (a, d) => a + v(d) * (d['probability'] as int) / 100),
          'won_this_month': {'count': deals.where((d) => d['stage'] == 'won').length, 'value': deals.where((d) => d['stage'] == 'won').fold<double>(0, (a, d) => a + v(d))},
          'lost_this_month': {'count': 0, 'value': 0},
          'leads': {for (final s in ['new', 'contacted', 'qualified', 'lost', 'converted']) s: leads.where((l) => l['status'] == s).length},
          'due_today': [for (final a in activities) if (a['completed_at'] == null && '${a['due_at']}'.startsWith(_today().substring(0, 10))) a],
          'overdue': [for (final a in activities) if (a['completed_at'] == null && '${a['due_at']}'.compareTo(_today().substring(0, 10)) < 0) a],
        },
      };
    }
    if (what == 'opportunities') {
      if (r.length == 2 && r[1] == 'board' && method == 'GET') {
        return {
          'data': [
            for (final s in ['prospecting', 'proposal', 'negotiation', 'won', 'lost'])
              {
                'stage': s,
                'count': deals.where((d) => d['stage'] == s).length,
                'value': deals.where((d) => d['stage'] == s).fold<double>(0, (a, d) => a + v(d)),
                'weighted': deals.where((d) => d['stage'] == s).fold<double>(0, (a, d) => a + v(d) * (d['probability'] as int) / 100),
                'items': [for (final d in deals) if (d['stage'] == s) d],
              },
          ],
        };
      }
      final d = deals.where((x) => '${x['id']}' == (r.length > 1 ? r[1] : '')).firstOrNull;
      if (d == null) throw ApiException(404, 'Opportunity not found.');
      if (r.length == 2 && method == 'GET') {
        return {
          'data': {...d, 'activities': [for (final a in activities) if (a['opportunity_id'] == d['id']) a], 'history': <Map>[]},
        };
      }
      if (r.length == 3 && r[2] == 'stage' && method == 'POST') {
        _need(perms, 'crm.manage');
        final stage = '${body['stage']}';
        if (stage == 'lost' && body['reason'] == null) throw ApiException(422, 'Say why the deal was lost before closing it.');
        d['stage'] = stage;
        d['probability'] = const {'prospecting': 10, 'proposal': 40, 'negotiation': 70, 'won': 100, 'lost': 0}[stage];
        d['close_reason'] = stage == 'won' || stage == 'lost' ? body['reason'] : null;
        return {'message': '${d['number']} is now $stage.', 'data': d};
      }
    }
    if (what == 'leads') {
      if (r.length == 1 && method == 'GET') {
        final q = '${query['q'] ?? ''}'.toLowerCase();
        return _page([
          for (final l in leads.reversed)
            if ((query['status'] == null || l['status'] == query['status']) &&
                (q.isEmpty || '${l['contact_name']} ${l['company_name']} ${l['phone']}'.toLowerCase().contains(q)))
              l,
        ]);
      }
      if (r.length == 1 && method == 'POST') {
        _need(perms, 'crm.manage');
        if ('${body['contact_name'] ?? ''}'.trim().isEmpty) {
          throw ApiException(422, 'The contact name field is required.', {'contact_name': ['The contact name field is required.']});
        }
        final id = ++_next;
        final l = {
          ...body, 'id': id, 'number': 'LEAD-2026-${'$id'.padLeft(6, '0')}', 'status': 'new',
          'estimated_value': '${body['estimated_value'] ?? 0}', 'owner': _neema, 'created_at': DateTime.now().toUtc().toIso8601String(),
        };
        leads.add(l);
        return {'data': l};
      }
      final l = leads.where((x) => '${x['id']}' == r[1]).firstOrNull;
      if (l == null) throw ApiException(404, 'Lead not found.');
      if (r.length == 2 && method == 'GET') {
        return {'data': {...l, 'activities': [for (final a in activities) if (a['lead_id'] == l['id']) a]}};
      }
      if (r.length == 2 && method == 'PUT') {
        _need(perms, 'crm.manage');
        l.addAll(body);
        return {'data': l};
      }
    }
    if (what == 'activities') {
      if (r.length == 1 && method == 'GET') {
        final status = query['status'];
        final today = _today().substring(0, 10);
        return _page([
          for (final a in activities)
            if ((query['type'] == null || a['type'] == query['type']) &&
                switch (status) {
                  'open' => a['completed_at'] == null,
                  'done' => a['completed_at'] != null,
                  'today' => a['completed_at'] == null && '${a['due_at']}'.startsWith(today),
                  'overdue' => a['completed_at'] == null && '${a['due_at']}'.compareTo(today) < 0,
                  _ => true,
                })
              a,
        ]);
      }
      if (r.length == 1 && method == 'POST') {
        _need(perms, 'crm.manage');
        final a = _activity(++_next, '${body['type']}', '${body['subject']}', '${body['due_at']}', lead: body['lead_id'] as int?, opp: body['opportunity_id'] as int?)
          ..['notes'] = body['notes']
          ..['owner'] = _neema;
        activities.add(a);
        return {'data': a};
      }
      final a = activities.where((x) => '${x['id']}' == r[1]).firstOrNull;
      if (a == null) throw ApiException(404, 'Activity not found.');
      if (r.length == 3 && r[2] == 'complete' && method == 'POST') {
        _need(perms, 'crm.manage');
        a['completed_at'] = DateTime.now().toUtc().toIso8601String();
        a['outcome'] = body['outcome'];
        return {'data': a};
      }
    }
    return unhandled;
  }

  /* ──────────────────────────────────────────────────────────── files ── */

  Object? _files(String method, List<String> r, Map<String, dynamic> query) {
    if (method != 'GET') return unhandled;
    final what = r.isEmpty ? '' : r.first;
    int? days(Map f) {
      final e = f['expires_on'];
      if (e == null) return null;
      final d = DateTime.parse('$e'.substring(0, 10));
      final n = DateTime.now();
      return d.difference(DateTime(n.year, n.month, n.day)).inDays;
    }

    switch (what) {
      case 'folders':
        return {'data': folders};
      case 'browse':
        final id = int.tryParse('${query['folder_id'] ?? ''}');
        final folder = folders.where((f) => f['id'] == id).firstOrNull;
        return {
          'folder': folder,
          'breadcrumbs': folder == null ? <Map>[] : [{'id': folder['id'], 'name': folder['name']}],
          'folders': [for (final f in folders) if (f['parent_id'] == id) f],
          'documents': _page([for (final f in files) if (f['folder_id'] == id) f]),
        };
      case 'documents':
        if (r.length == 1) {
          final q = '${query['q'] ?? ''}'.toLowerCase();
          return _page([
            for (final f in files)
              if ((q.isEmpty || '${f['title']}'.toLowerCase().contains(q)) &&
                  (query['document_type'] == null || f['document_type'] == query['document_type']))
                f,
          ]);
        }
        final f = files.where((x) => '${x['id']}' == r[1]).firstOrNull;
        if (f == null) throw ApiException(404, 'Document not found.');
        return {
          'data': {
            ...f,
            'versions': [{...f['latest_version'] as Map, 'uploader': _neema}],
            'breadcrumbs': [f['folder']],
            'retained': false,
            'can': {'upload': true, 'manage': true, 'delete': true},
          },
        };
      case 'expiring':
        final window = int.tryParse('${query['days'] ?? 30}') ?? 30;
        final rows = [for (final f in files) if (days(f) != null && days(f)! <= window) {...f, 'days_left': days(f)}]
          ..sort((a, b) => (a['days_left'] as int).compareTo(b['days_left'] as int));
        return {'data': rows, 'days': window};
    }
    return unhandled;
  }
}
