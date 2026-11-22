import 'erp_models.dart' show ErpRef;

/*
 * The shapes the Production (/erp/production), CRM (/erp/crm) and Documents
 * (/erp/files) endpoints return, read once here so screens never parse.
 * Decimals arrive as strings ("400.000"); dates as ISO strings, of which
 * calendar dates keep only their day.
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

/// "2026-11-12", the API's date format.
String opsDay(DateTime d) =>
    '${d.year}-${'${d.month}'.padLeft(2, '0')}-${'${d.day}'.padLeft(2, '0')}';

/* ══════════════════════════════════════════════════════════ production ══ */

abstract class PrdStatus {
  static const planned = 'planned';
  static const released = 'released';
  static const inProgress = 'in_progress';
  static const completed = 'completed';
  static const closed = 'closed';
  static const cancelled = 'cancelled';

  static const all = [planned, released, inProgress, completed, closed, cancelled];
}

abstract class PrdReceiptStatus {
  static const pending = 'pending_qc';
  static const released = 'released';
  static const rejected = 'rejected';
}

/// GET /erp/production/overview.
class ProductionOverview {
  const ProductionOverview({
    required this.byStatus,
    required this.openOrders,
    required this.todayProduced,
    required this.todayReleased,
    required this.qcPending,
    required this.periodProduced,
    required this.periodReleased,
    required this.periodRejected,
    required this.periodWastage,
    required this.yieldPercent,
    required this.wastagePercent,
    required this.materialsIssued,
    required this.trend,
    required this.byProduct,
    required this.recent,
  });

  factory ProductionOverview.fromJson(Map<String, dynamic> j) {
    final today = _map(j['today']) ?? const {};
    final period = _map(j['period']) ?? const {};
    final status = _map(j['by_status']) ?? const {};
    return ProductionOverview(
      byStatus: {for (final e in status.entries) e.key: _i(e.value)},
      openOrders: _i(j['open_orders']),
      todayProduced: _d(today['produced']),
      todayReleased: _d(today['released']),
      qcPending: _i(j['qc_pending']),
      periodProduced: _d(period['produced']),
      periodReleased: _d(period['released']),
      periodRejected: _d(period['rejected']),
      periodWastage: _d(period['wastage']),
      yieldPercent: _dn(period['yield_percent']),
      wastagePercent: _dn(period['wastage_percent']),
      materialsIssued: _d(period['materials_issued_value']),
      trend: _list(j['trend'], (t) => (date: _date(t['date']), produced: _d(t['produced']), released: _d(t['released']))),
      byProduct: _list(
        j['by_product'],
        (p) => (name: '${p['name'] ?? ''}', produced: _d(p['produced']), released: _d(p['released']), yieldPercent: _dn(p['yield_percent'])),
      ),
      recent: _list(j['recent_orders'], ProductionOrder.fromJson),
    );
  }

  final Map<String, int> byStatus;
  final int openOrders, qcPending;
  final double todayProduced, todayReleased;
  final double periodProduced, periodReleased, periodRejected, periodWastage, materialsIssued;
  final double? yieldPercent, wastagePercent;
  final List<({DateTime? date, double produced, double released})> trend;
  final List<({String name, double produced, double released, double? yieldPercent})> byProduct;
  final List<ProductionOrder> recent;
}

/// A material line of an order: what the bill of materials needs, what has
/// been issued and what the store holds.
class PrdRequirement {
  const PrdRequirement({
    required this.productId,
    required this.name,
    required this.sku,
    required this.unit,
    required this.trackBatches,
    required this.allowsDecimals,
    required this.required,
    required this.issued,
    required this.remaining,
    required this.available,
    required this.shortfall,
    required this.sufficient,
    required this.batches,
  });

  factory PrdRequirement.fromJson(Map<String, dynamic> j) {
    final p = _map(j['product']) ?? const {};
    return PrdRequirement(
      productId: _i(j['product_id']),
      name: '${p['name'] ?? ''}',
      sku: '${p['sku'] ?? ''}',
      unit: '${p['unit'] ?? ''}',
      trackBatches: p['track_batches'] == true,
      allowsDecimals: p['allows_decimals'] == true,
      required: _d(j['required_quantity']),
      issued: _d(j['issued_quantity']),
      remaining: _d(j['remaining_quantity']),
      available: _d(j['available_quantity']),
      shortfall: _d(j['shortfall_quantity']),
      sufficient: j['sufficient'] != false,
      batches: _list(j['batches'], (b) => (batch: '${b['batch_number'] ?? ''}', quantity: _d(b['quantity']), expiry: _date(b['expiry_date']))),
    );
  }

  final int productId;
  final String name, sku, unit;
  final bool trackBatches, allowsDecimals, sufficient;
  final double required, issued, remaining, available, shortfall;
  final List<({String batch, double quantity, DateTime? expiry})> batches;
}

class QcParameter {
  QcParameter({required this.name, this.target = '', this.value = '', this.passed = true});

  factory QcParameter.fromJson(Map<String, dynamic> j) => QcParameter(
    name: '${j['name'] ?? ''}',
    target: '${j['target'] ?? ''}',
    value: '${j['value'] ?? ''}',
    passed: j['passed'] != false,
  );

  String name, target, value;
  bool passed;

  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'target': target.trim().isEmpty ? null : target.trim(),
    'value': value.trim().isEmpty ? null : value.trim(),
    'passed': passed,
  };
}

/// One output recorded on an order, waiting for or past its quality check.
class PrdReceipt {
  const PrdReceipt({
    required this.id,
    required this.number,
    required this.status,
    required this.produced,
    required this.good,
    required this.rejected,
    required this.wastage,
    required this.released,
    required this.isFinal,
    this.date,
    this.batch,
    this.expiry,
    this.unitCost,
    this.orderId,
    this.orderNumber,
    this.productName,
    this.recorder,
    this.inspector,
    this.decision,
    this.parameters = const [],
    this.stockDocument,
    this.notes,
  });

  factory PrdReceipt.fromJson(Map<String, dynamic> j) {
    final order = _map(j['order']);
    final qc = _map(j['qc']);
    return PrdReceipt(
      id: _i(j['id']),
      number: '${j['number'] ?? ''}',
      status: '${j['status'] ?? PrdReceiptStatus.pending}',
      produced: _d(j['produced_quantity']),
      good: _d(j['good_quantity']),
      rejected: _d(j['rejected_quantity']),
      wastage: _d(j['wastage_quantity']),
      released: _d(j['released_quantity']),
      isFinal: j['is_final'] == true,
      date: _date(j['receipt_date']),
      batch: _s(j['batch_number']),
      expiry: _date(j['expiry_date']),
      unitCost: _dn(j['unit_cost']),
      orderId: _in(j['production_order_id']) ?? _in(order?['id']),
      orderNumber: _s(order?['number']),
      productName: _name(order?['product']),
      recorder: _name(j['recorder']),
      inspector: _name(qc?['inspector']),
      decision: _s(qc?['decision']),
      parameters: _list(qc?['parameters'], QcParameter.fromJson),
      stockDocument: _s(_map(j['stock_document'])?['number']),
      notes: _s(j['notes']),
    );
  }

  final int id;
  final String number, status;
  final double produced, good, rejected, wastage, released;
  final bool isFinal;
  final DateTime? date, expiry;
  final String? batch, orderNumber, productName, recorder, inspector, decision, stockDocument, notes;
  final double? unitCost;
  final int? orderId;
  final List<QcParameter> parameters;

  bool get isPending => status == PrdReceiptStatus.pending;
}

class PrdIssue {
  const PrdIssue({required this.id, required this.number, this.date, this.creator, required this.value, required this.lines});

  factory PrdIssue.fromJson(Map<String, dynamic> j) => PrdIssue(
    id: _i(j['id']),
    number: '${j['number'] ?? ''}',
    date: _date(j['document_date']),
    creator: _name(j['creator']),
    value: _d(j['value']),
    lines: _list(j['lines'], (l) => (name: _name(l['product']) ?? '', quantity: _d(l['quantity']), batch: _s(l['batch_number']))),
  );

  final int id;
  final String number;
  final DateTime? date;
  final String? creator;
  final double value;
  final List<({String name, double quantity, String? batch})> lines;
}

class ProductionOrder {
  const ProductionOrder({
    required this.id,
    required this.number,
    required this.status,
    required this.productName,
    required this.planned,
    this.productId,
    this.productSku,
    this.unit = '',
    this.trackBatches = false,
    this.trackExpiry = false,
    this.produced = 0,
    this.good = 0,
    this.released = 0,
    this.rejected = 0,
    this.wastage = 0,
    this.plannedStart,
    this.plannedEnd,
    this.reference,
    this.notes,
    this.bom,
    this.bomVersion,
    this.workCentre,
    this.materialsWarehouse,
    this.outputWarehouse,
    this.creator,
    this.releaser,
    this.completer,
    this.closer,
    this.canceller,
    this.createdAt,
    this.releasedAt,
    this.startedAt,
    this.completedAt,
    this.closedAt,
    this.cancelledAt,
    this.cancelReason,
    this.requirements = const [],
    this.receipts = const [],
    this.issues = const [],
    this.costing,
  });

  factory ProductionOrder.fromJson(Map<String, dynamic> j) {
    final product = _map(j['product']) ?? const {};
    final bom = _map(j['bom']);
    final costing = _map(j['costing']);
    return ProductionOrder(
      id: _i(j['id']),
      number: '${j['number'] ?? ''}',
      status: '${j['status'] ?? PrdStatus.planned}',
      productId: _in(j['product_id']),
      productName: '${product['name'] ?? ''}',
      productSku: _s(product['sku']),
      unit: '${_map(product['unit'])?['code'] ?? ''}',
      trackBatches: product['track_batches'] == true,
      trackExpiry: product['track_expiry'] == true,
      planned: _d(j['planned_quantity']),
      produced: _d(j['produced_quantity']),
      good: _d(j['good_quantity']),
      released: _d(j['released_quantity']),
      rejected: _d(j['rejected_quantity']),
      wastage: _d(j['wastage_quantity']),
      plannedStart: _date(j['planned_start']),
      plannedEnd: _date(j['planned_end']),
      reference: _s(j['reference']),
      notes: _s(j['notes']),
      bom: bom == null ? null : ErpRef(_i(bom['id']), '${bom['name'] ?? ''}'),
      bomVersion: _in(bom?['version']),
      workCentre: _map(bom?['work_centre']) == null
          ? null
          : '${bom!['work_centre']['code']} · ${bom['work_centre']['name']}',
      materialsWarehouse: _name(j['materials_warehouse']),
      outputWarehouse: _name(j['output_warehouse']),
      creator: _name(j['creator']),
      releaser: _name(j['releaser']),
      completer: _name(j['completer']),
      closer: _name(j['closer']),
      canceller: _name(j['canceller']),
      createdAt: _time(j['created_at']),
      releasedAt: _time(j['released_at']),
      startedAt: _time(j['started_at']),
      completedAt: _time(j['completed_at']),
      closedAt: _time(j['closed_at']),
      cancelledAt: _time(j['cancelled_at']),
      cancelReason: _s(j['cancel_reason']),
      requirements: _list(j['requirements'], PrdRequirement.fromJson),
      receipts: _list(j['receipts'], PrdReceipt.fromJson),
      issues: _list(j['issues'], PrdIssue.fromJson),
      costing: costing == null ? null : PrdCosting.fromJson(costing),
    );
  }

  final int id;
  final String number, status, productName, unit;
  final int? productId;
  final String? productSku;
  final bool trackBatches, trackExpiry;
  final double planned, produced, good, released, rejected, wastage;
  final DateTime? plannedStart, plannedEnd;
  final String? reference, notes, workCentre, materialsWarehouse, outputWarehouse;
  final ErpRef? bom;
  final int? bomVersion;
  final String? creator, releaser, completer, closer, canceller, cancelReason;
  final DateTime? createdAt, releasedAt, startedAt, completedAt, closedAt, cancelledAt;
  final List<PrdRequirement> requirements;
  final List<PrdReceipt> receipts;
  final List<PrdIssue> issues;
  final PrdCosting? costing;

  /// Released or in progress: materials can be issued and output recorded.
  bool get onFloor => status == PrdStatus.released || status == PrdStatus.inProgress;
  bool get hasFinal => receipts.any((r) => r.isFinal);

  /// How far the run is, released against planned, 0 to 1.
  double get progress => planned <= 0 ? 0 : (released / planned).clamp(0, 1).toDouble();
}

class PrdCosting {
  const PrdCosting({
    this.standardUnit,
    required this.material,
    required this.conversion,
    required this.actualTotal,
    this.actualUnit,
    required this.received,
    required this.wip,
    this.variance,
    this.yieldPercent,
  });

  factory PrdCosting.fromJson(Map<String, dynamic> j) => PrdCosting(
    standardUnit: _dn(j['standard_unit_cost']),
    material: _d(j['material_cost']),
    conversion: _d(j['conversion_cost']),
    actualTotal: _d(j['actual_total']),
    actualUnit: _dn(j['actual_unit_cost']),
    received: _d(j['received_value']),
    wip: _d(j['wip_balance']),
    variance: _dn(j['variance_value']),
    yieldPercent: _dn(j['yield_percent']),
  );

  final double? standardUnit, actualUnit, variance, yieldPercent;
  final double material, conversion, actualTotal, received, wip;
}

class PrdBom {
  const PrdBom({
    required this.id,
    required this.name,
    required this.version,
    required this.productName,
    required this.output,
    required this.isActive,
    this.unit = '',
    this.productSku,
    this.workCentre,
    this.labour = 0,
    this.overhead = 0,
    this.standardCost,
    this.linesCount = 0,
    this.ordersCount = 0,
    this.notes,
    this.lines = const [],
    this.materialsPerUnit,
    this.conversionPerUnit,
    this.versions = const [],
  });

  factory PrdBom.fromJson(Map<String, dynamic> j) {
    final product = _map(j['product']) ?? const {};
    final wc = _map(j['work_centre']);
    final standard = _map(j['standard']);
    final costs = {
      for (final l in _list(standard?['lines'], (m) => m)) _i(l['product_id']): l,
    };
    return PrdBom(
      id: _i(j['id']),
      name: '${j['name'] ?? ''}',
      version: _i(j['version']),
      productName: '${product['name'] ?? ''}',
      productSku: _s(product['sku']),
      unit: '${_map(product['unit'])?['code'] ?? ''}',
      output: _d(j['output_quantity']),
      isActive: j['is_active'] == true,
      workCentre: wc == null ? null : '${wc['code']} · ${wc['name']}',
      labour: _d(j['labour_cost']),
      overhead: _d(j['overhead_cost']),
      standardCost: _dn(j['standard_cost']) ?? _dn(standard?['unit_cost']),
      linesCount: _in(j['lines_count']) ?? (j['lines'] is List ? (j['lines'] as List).length : 0),
      ordersCount: _i(j['orders_count']),
      notes: _s(j['notes']),
      materialsPerUnit: _dn(standard?['materials']),
      conversionPerUnit: _dn(standard?['conversion']),
      lines: _list(j['lines'], (l) {
        final p = _map(l['product']) ?? const {};
        final cost = costs[_i(l['product_id'])];
        return PrdBomLine(
          name: '${p['name'] ?? ''}',
          sku: '${p['sku'] ?? ''}',
          unit: '${_map(p['unit'])?['code'] ?? ''}',
          quantity: _d(l['quantity']),
          scrap: _d(l['scrap_percent']),
          perUnit: _dn(cost?['per_unit']),
          costPerUnit: _dn(cost?['cost_per_unit']),
        );
      }),
      versions: _list(j['versions'], (v) => (id: _i(v['id']), version: _i(v['version']), active: v['is_active'] == true)),
    );
  }

  final int id, version, linesCount, ordersCount;
  final String name, productName, unit;
  final String? productSku, workCentre, notes;
  final double output, labour, overhead;
  final double? standardCost, materialsPerUnit, conversionPerUnit;
  final bool isActive;
  final List<PrdBomLine> lines;
  final List<({int id, int version, bool active})> versions;
}

class PrdBomLine {
  const PrdBomLine({
    required this.name,
    required this.sku,
    required this.unit,
    required this.quantity,
    required this.scrap,
    this.perUnit,
    this.costPerUnit,
  });

  final String name, sku, unit;
  final double quantity, scrap;
  final double? perUnit, costPerUnit;
}

/// GET /erp/production/options: what the plan form picks from.
class PrdOptions {
  const PrdOptions({required this.finished, required this.warehouses});

  factory PrdOptions.fromJson(Map<String, dynamic> j) => PrdOptions(
    finished: _list(j['finished'], (p) => (id: _i(p['id']), name: '${p['name'] ?? ''}', sku: '${p['sku'] ?? ''}', unit: '${_map(p['unit'])?['code'] ?? ''}')),
    warehouses: _list(j['warehouses'], (w) => ErpRef(_i(w['id']), '${w['name'] ?? ''}', _s(w['code']))),
  );

  final List<({int id, String name, String sku, String unit})> finished;
  final List<ErpRef> warehouses;
}

/// What POST /orders creates.
class PrdOrderDraft {
  int? productId;
  String quantity = '';
  int? materialsWarehouseId;
  int? outputWarehouseId;
  DateTime start = DateTime.now();
  DateTime end = DateTime.now().add(const Duration(days: 1));
  String reference = '';
  String notes = '';

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'planned_quantity': double.tryParse(quantity.trim()) ?? 0,
    'materials_warehouse_id': materialsWarehouseId,
    'output_warehouse_id': outputWarehouseId,
    'planned_start': opsDay(start),
    'planned_end': opsDay(end),
    'reference': reference.trim().isEmpty ? null : reference.trim(),
    'notes': notes.trim().isEmpty ? null : notes.trim(),
  };
}

/* ═════════════════════════════════════════════════════════════════ crm ══ */

abstract class CrmStage {
  static const prospecting = 'prospecting';
  static const proposal = 'proposal';
  static const negotiation = 'negotiation';
  static const won = 'won';
  static const lost = 'lost';

  static const all = [prospecting, proposal, negotiation, won, lost];
  static const open = [prospecting, proposal, negotiation];

  static const winReasons = ['price', 'quality', 'relationship', 'delivery', 'credit_terms', 'other'];
  static const lossReasons = ['price', 'competitor', 'no_budget', 'no_decision', 'timing', 'stock', 'other'];
}

abstract class CrmLeadStatus {
  static const all = ['new', 'contacted', 'qualified', 'lost', 'converted'];

  /// What a person may set by hand; converting goes through its own action.
  static const settable = ['new', 'contacted', 'qualified', 'lost'];
  static const sources = ['referral', 'walk_in', 'phone', 'website', 'social_media', 'trade_show', 'field_visit', 'other'];
}

abstract class CrmActivityType {
  static const all = ['call', 'meeting', 'visit', 'task'];
}

class CrmActivity {
  const CrmActivity({
    required this.id,
    required this.type,
    required this.subject,
    this.notes,
    this.dueAt,
    this.completedAt,
    this.outcome,
    this.owner,
    this.leadId,
    this.leadName,
    this.opportunityId,
    this.opportunityTitle,
    this.customer,
  });

  factory CrmActivity.fromJson(Map<String, dynamic> j) {
    final lead = _map(j['lead']);
    final opp = _map(j['opportunity']);
    return CrmActivity(
      id: _i(j['id']),
      type: '${j['type'] ?? 'task'}',
      subject: '${j['subject'] ?? ''}',
      notes: _s(j['notes']),
      dueAt: _time(j['due_at']),
      completedAt: _time(j['completed_at']),
      outcome: _s(j['outcome']),
      owner: _name(j['owner']),
      leadId: _in(j['lead_id']),
      leadName: _s(lead?['contact_name']),
      opportunityId: _in(j['opportunity_id']),
      opportunityTitle: _s(opp?['title']),
      customer: _name(j['customer']),
    );
  }

  final int id;
  final String type, subject;
  final String? notes, outcome, owner, leadName, opportunityTitle, customer;
  final DateTime? dueAt, completedAt;
  final int? leadId, opportunityId;

  bool get isDone => completedAt != null;

  bool overdue(DateTime now) =>
      !isDone && dueAt != null && dueAt!.isBefore(DateTime(now.year, now.month, now.day));

  /// The record it belongs to, for a list row.
  String? get linkedTo => opportunityTitle ?? leadName ?? customer;
}

class CrmOverview {
  const CrmOverview({
    required this.stages,
    required this.openValue,
    required this.weightedValue,
    required this.wonCount,
    required this.wonValue,
    required this.lostCount,
    required this.leads,
    required this.dueToday,
    required this.overdue,
  });

  factory CrmOverview.fromJson(Map<String, dynamic> j) {
    final won = _map(j['won_this_month']) ?? const {};
    final lost = _map(j['lost_this_month']) ?? const {};
    final leads = _map(j['leads']) ?? const {};
    return CrmOverview(
      stages: _list(j['stages'], CrmStageTotal.fromJson),
      openValue: _d(j['open_value']),
      weightedValue: _d(j['weighted_value']),
      wonCount: _i(won['count']),
      wonValue: _d(won['value']),
      lostCount: _i(lost['count']),
      leads: {for (final e in leads.entries) e.key: _i(e.value)},
      dueToday: _list(j['due_today'], CrmActivity.fromJson),
      overdue: _list(j['overdue'], CrmActivity.fromJson),
    );
  }

  final List<CrmStageTotal> stages;
  final double openValue, weightedValue, wonValue;
  final int wonCount, lostCount;
  final Map<String, int> leads;
  final List<CrmActivity> dueToday, overdue;
}

class CrmStageTotal {
  const CrmStageTotal({required this.stage, required this.count, required this.value, required this.weighted, this.items = const []});

  factory CrmStageTotal.fromJson(Map<String, dynamic> j) => CrmStageTotal(
    stage: '${j['stage'] ?? ''}',
    count: _i(j['count']),
    value: _d(j['value']),
    weighted: _d(j['weighted']),
    items: _list(j['items'], CrmOpportunity.fromJson),
  );

  final String stage;
  final int count;
  final double value, weighted;
  final List<CrmOpportunity> items;
}

class CrmOpportunity {
  const CrmOpportunity({
    required this.id,
    required this.number,
    required this.title,
    required this.stage,
    required this.value,
    required this.probability,
    this.expectedClose,
    this.owner,
    this.customer,
    this.customerId,
    this.customerPhone,
    this.customerEmail,
    this.leadId,
    this.leadName,
    this.closeReason,
    this.closeNote,
    this.notes,
    this.createdAt,
    this.stageChangedAt,
    this.activities = const [],
    this.history = const [],
  });

  factory CrmOpportunity.fromJson(Map<String, dynamic> j) {
    final customer = _map(j['customer']);
    final lead = _map(j['lead']);
    return CrmOpportunity(
      id: _i(j['id']),
      number: '${j['number'] ?? ''}',
      title: '${j['title'] ?? ''}',
      stage: '${j['stage'] ?? CrmStage.prospecting}',
      value: _d(j['value']),
      probability: _i(j['probability']),
      expectedClose: _date(j['expected_close_date']),
      owner: _name(j['owner']),
      customer: _s(customer?['name']),
      customerId: _in(j['customer_id']),
      customerPhone: _s(customer?['phone']),
      customerEmail: _s(customer?['email']),
      leadId: _in(j['lead_id']),
      leadName: _s(lead?['contact_name']),
      closeReason: _s(j['close_reason']),
      closeNote: _s(j['close_note']),
      notes: _s(j['notes']),
      createdAt: _time(j['created_at']),
      stageChangedAt: _time(j['stage_changed_at']),
      activities: _list(j['activities'], CrmActivity.fromJson),
      history: _list(
        j['history'],
        (h) => (who: '${h['actor_name'] ?? ''}', what: '${h['description'] ?? ''}', at: _time(h['created_at'])),
      ),
    );
  }

  final int id, probability;
  final String number, title, stage;
  final double value;
  final DateTime? expectedClose, createdAt, stageChangedAt;
  final String? owner, customer, customerPhone, customerEmail, leadName, closeReason, closeNote, notes;
  final int? customerId, leadId;
  final List<CrmActivity> activities;
  final List<({String who, String what, DateTime? at})> history;

  bool get isOpen => CrmStage.open.contains(stage);
}

class CrmLead {
  const CrmLead({
    required this.id,
    required this.number,
    required this.contactName,
    required this.status,
    required this.source,
    this.companyName,
    this.phone,
    this.email,
    this.region,
    this.estimatedValue = 0,
    this.notes,
    this.lostReason,
    this.owner,
    this.customer,
    this.opportunityId,
    this.opportunityTitle,
    this.createdAt,
    this.activities = const [],
  });

  factory CrmLead.fromJson(Map<String, dynamic> j) {
    final opp = _map(j['opportunity']);
    return CrmLead(
      id: _i(j['id']),
      number: '${j['number'] ?? ''}',
      contactName: '${j['contact_name'] ?? ''}',
      status: '${j['status'] ?? 'new'}',
      source: '${j['source'] ?? 'other'}',
      companyName: _s(j['company_name']),
      phone: _s(j['phone']),
      email: _s(j['email']),
      region: _s(j['region']),
      estimatedValue: _d(j['estimated_value']),
      notes: _s(j['notes']),
      lostReason: _s(j['lost_reason']),
      owner: _name(j['owner']),
      customer: _name(j['customer']),
      opportunityId: _in(j['opportunity_id']) ?? _in(opp?['id']),
      opportunityTitle: _s(opp?['title']),
      createdAt: _time(j['created_at']),
      activities: _list(j['activities'], CrmActivity.fromJson),
    );
  }

  final int id;
  final String number, contactName, status, source;
  final String? companyName, phone, email, region, notes, lostReason, owner, customer, opportunityTitle;
  final double estimatedValue;
  final int? opportunityId;
  final DateTime? createdAt;
  final List<CrmActivity> activities;

  bool get isConverted => status == 'converted';
}

/// A new lead (POST /crm/leads).
class CrmLeadDraft {
  String contactName = '';
  String companyName = '';
  String phone = '';
  String email = '';
  String region = '';
  String source = 'field_visit';
  String estimatedValue = '';
  String notes = '';

  String? _opt(String v) => v.trim().isEmpty ? null : v.trim();

  Map<String, dynamic> toJson() => {
    'contact_name': contactName.trim(),
    'company_name': _opt(companyName),
    'phone': _opt(phone),
    'email': _opt(email),
    'region': _opt(region),
    'source': source,
    if (estimatedValue.trim().isNotEmpty) 'estimated_value': double.tryParse(estimatedValue.replaceAll(',', '').trim()) ?? 0,
    'notes': _opt(notes),
  };
}

/// A call, meeting, visit or task to log (POST /crm/activities), and,
/// when it already happened, its outcome for the follow-up complete call.
class CrmActivityDraft {
  CrmActivityDraft({this.leadId, this.opportunityId, this.customerId, this.type = 'call'});

  String type;
  String subject = '';
  String notes = '';
  DateTime due = DateTime.now();
  bool done = true;
  String outcome = '';
  int? leadId, opportunityId, customerId;

  Map<String, dynamic> toJson() => {
    'type': type,
    'subject': subject.trim(),
    'notes': notes.trim().isEmpty ? null : notes.trim(),
    'due_at': due.toUtc().toIso8601String(),
    'lead_id': ?leadId,
    'opportunity_id': ?opportunityId,
    'customer_id': ?customerId,
  };
}

/* ═══════════════════════════════════════════════════════════ documents ══ */

abstract class DmsType {
  static const all = [
    'general', 'contract', 'licence', 'permit', 'certificate', 'insurance', 'policy', //
    'invoice', 'receipt', 'report', 'id_document', 'vehicle', 'hr', 'other',
  ];

  static const extensions = [
    'pdf', 'jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', //
    'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp', 'rtf', 'csv', 'txt',
  ];

  static const maxBytes = 20 * 1024 * 1024;
}

class DmsFolder {
  const DmsFolder({required this.id, required this.name, this.parentId, this.description, this.documents = 0});

  factory DmsFolder.fromJson(Map<String, dynamic> j) => DmsFolder(
    id: _i(j['id']),
    name: '${j['name'] ?? ''}',
    parentId: _in(j['parent_id']),
    description: _s(j['description']),
    documents: _i(j['documents_count']),
  );

  final int id, documents;
  final String name;
  final int? parentId;
  final String? description;
}

class DmsVersion {
  const DmsVersion({required this.version, required this.name, this.mime, required this.size, this.note, this.uploader, this.at});

  factory DmsVersion.fromJson(Map<String, dynamic> j) => DmsVersion(
    version: _i(j['version']),
    name: '${j['original_name'] ?? ''}',
    mime: _s(j['mime_type']),
    size: _i(j['size_bytes']),
    note: _s(j['note']),
    uploader: _name(j['uploader']),
    at: _time(j['created_at']),
  );

  final int version, size;
  final String name;
  final String? mime, note, uploader;
  final DateTime? at;

  String get extension => name.contains('.') ? name.split('.').last.toLowerCase() : '';
}

class DmsDocument {
  const DmsDocument({
    required this.id,
    required this.title,
    required this.type,
    required this.currentVersion,
    this.folderId,
    this.folder,
    this.tags = const [],
    this.description,
    this.reference,
    this.issuedOn,
    this.expiresOn,
    this.daysLeft,
    this.owner,
    this.creator,
    this.createdAt,
    this.latest,
    this.versions = const [],
    this.breadcrumbs = const [],
    this.retained = false,
    this.retainUntil,
    this.canUpload = false,
    this.canDelete = false,
    this.links = 0,
  });

  factory DmsDocument.fromJson(Map<String, dynamic> j) {
    final latest = _map(j['latest_version']);
    final can = _map(j['can']) ?? const {};
    final versions = _list(j['versions'], DmsVersion.fromJson)..sort((a, b) => b.version.compareTo(a.version));
    return DmsDocument(
      id: _i(j['id']),
      title: '${j['title'] ?? ''}',
      type: '${j['document_type'] ?? 'general'}',
      currentVersion: _i(j['current_version']),
      folderId: _in(j['folder_id']),
      folder: _name(j['folder']),
      tags: (j['tags'] is List ? j['tags'] as List : const []).map((e) => '$e').toList(),
      description: _s(j['description']),
      reference: _s(j['reference']),
      issuedOn: _date(j['issued_on']),
      expiresOn: _date(j['expires_on']),
      daysLeft: _in(j['days_left']),
      owner: _name(j['owner']),
      creator: _name(j['creator']),
      createdAt: _time(j['created_at']),
      latest: latest == null ? versions.firstOrNull : DmsVersion.fromJson(latest),
      versions: versions,
      breadcrumbs: _list(j['breadcrumbs'], (b) => ErpRef(_i(b['id']), '${b['name'] ?? ''}')),
      retained: j['retained'] == true,
      retainUntil: _date(j['retain_until']),
      canUpload: can['upload'] == true,
      canDelete: can['delete'] == true,
      links: j['links'] is List ? (j['links'] as List).length : 0,
    );
  }

  final int id, currentVersion, links;
  final String title, type;
  final int? folderId, daysLeft;
  final String? folder, description, reference, owner, creator;
  final List<String> tags;
  final DateTime? issuedOn, expiresOn, createdAt, retainUntil;
  final DmsVersion? latest;
  final List<DmsVersion> versions;
  final List<ErpRef> breadcrumbs;
  final bool retained, canUpload, canDelete;

  /// Days until it expires (negative once expired), from [daysLeft] when the
  /// API gave it, otherwise from today.
  int? daysToExpiry(DateTime today) {
    if (daysLeft != null) return daysLeft;
    if (expiresOn == null) return null;
    return expiresOn!.difference(DateTime(today.year, today.month, today.day)).inDays;
  }
}

/// One level of the library (GET /files/browse).
class DmsListing {
  const DmsListing({this.folder, required this.breadcrumbs, required this.folders, required this.documents, required this.hasMore});

  factory DmsListing.fromJson(Map<String, dynamic> j) {
    final docs = _map(j['documents']) ?? const {};
    final folder = _map(j['folder']);
    return DmsListing(
      folder: folder == null ? null : DmsFolder.fromJson(folder),
      breadcrumbs: _list(j['breadcrumbs'], (b) => ErpRef(_i(b['id']), '${b['name'] ?? ''}')),
      folders: _list(j['folders'], DmsFolder.fromJson),
      documents: _list(docs['data'], DmsDocument.fromJson),
      hasMore: (_in(docs['current_page']) ?? 1) < (_in(docs['last_page']) ?? 1),
    );
  }

  final DmsFolder? folder;
  final List<ErpRef> breadcrumbs;
  final List<DmsFolder> folders;
  final List<DmsDocument> documents;
  final bool hasMore;
}

/// What an upload sends besides the file.
class DmsUploadDraft {
  String title = '';
  int? folderId;
  String type = 'general';
  String reference = '';
  String tags = '';
  String description = '';
  DateTime? issuedOn;
  DateTime? expiresOn;

  Map<String, String> toFields() => {
    if (title.trim().isNotEmpty) 'title': title.trim(),
    'folder_id': ?folderId?.toString(),
    'document_type': type,
    if (reference.trim().isNotEmpty) 'reference': reference.trim(),
    if (tags.trim().isNotEmpty) 'tags': tags.trim(),
    if (description.trim().isNotEmpty) 'description': description.trim(),
    if (issuedOn != null) 'issued_on': opsDay(issuedOn!),
    if (expiresOn != null) 'expires_on': opsDay(expiresOn!),
  };
}
