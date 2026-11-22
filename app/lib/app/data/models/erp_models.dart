import 'package:intl/intl.dart';

/*
 * The shapes the /api/erp endpoints return, as the web's lib/erp.ts types
 * them. Decimals arrive as strings ("40.0000"); every reader here turns them
 * into numbers once, so screens never parse.
 */

double _d(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

double? _dn(dynamic v) => v == null ? null : _d(v);

int _i(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

int? _in(dynamic v) => v == null ? null : _i(v);

String? _s(dynamic v) {
  if (v == null) return null;
  final s = '$v';
  return s.isEmpty ? null : s;
}

/// A calendar date from the API ("2026-11-12T00:00:00.000000Z"). Only the
/// day is read, so a midnight UTC date never becomes yesterday on a phone
/// west of Greenwich.
DateTime? _date(dynamic v) {
  final s = _s(v);
  if (s == null || s.length < 10) return null;
  return DateTime.tryParse(s.substring(0, 10));
}

DateTime? _time(dynamic v) {
  final s = _s(v);
  return s == null ? null : DateTime.tryParse(s)?.toLocal();
}

Map<String, dynamic>? _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : null;

List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) read) =>
    (v is List ? v : const [])
        .whereType<Map>()
        .map((e) => read(Map<String, dynamic>.from(e)))
        .toList();

List<String> _strings(dynamic v) =>
    (v is List ? v : const []).map((e) => '$e').toList();

/* ─────────────────────────────────────────────────────── configuration ── */

/// The company's ERP set-up and the caller's resolved permissions
/// (GET /erp/config). The app never decides what a person may do: it reads
/// [permissions] and hides what the API would refuse anyway.
class ErpConfig {
  const ErpConfig({
    required this.businessType,
    required this.businessLabel,
    required this.isSetUp,
    required this.modules,
    required this.licensedModules,
    required this.liveModules,
    required this.permissions,
    required this.baseCurrency,
    required this.allowNegativeStock,
    required this.expiryAlertDays,
  });

  factory ErpConfig.fromJson(Map<String, dynamic> json) {
    final settings = _map(json['settings']) ?? const {};
    return ErpConfig(
      businessType: '${json['business_type'] ?? ''}',
      businessLabel: _s(json['business_label']),
      isSetUp: json['is_set_up'] == true,
      modules: _strings(json['modules']),
      licensedModules: json['licensed_modules'] is List
          ? _strings(json['licensed_modules'])
          : null,
      liveModules: _strings(json['live_modules']),
      permissions: _strings(json['permissions']),
      baseCurrency: _s(settings['base_currency']) ?? 'TZS',
      allowNegativeStock: settings['allow_negative_stock'] == true,
      expiryAlertDays: _in(settings['expiry_alert_days']) ?? 60,
    );
  }

  final String businessType;
  final String? businessLabel;
  final bool isSetUp;

  /// Switched on for the company; always a subset of [licensedModules].
  final List<String> modules;

  /// What the subscription allows; null when the API does not say.
  final List<String>? licensedModules;

  /// What this release ships.
  final List<String> liveModules;
  final List<String> permissions;

  final String baseCurrency;
  final bool allowNegativeStock;
  final int expiryAlertDays;

  bool can(String permission) => permissions.contains(permission);
  bool has(String module) => modules.contains(module);
}

/* ────────────────────────────────────────────────────────── references ── */

/// A small embedded record: `{id, code?, name}` (a warehouse, a supplier, a
/// person).
class ErpRef {
  const ErpRef(this.id, this.name, [this.code]);

  static ErpRef? fromJson(dynamic json) {
    final m = _map(json);
    if (m == null) return null;
    return ErpRef(_i(m['id']), '${m['name'] ?? ''}', _s(m['code']));
  }

  final int id;
  final String name;
  final String? code;
}

class ErpUnit {
  const ErpUnit({
    required this.id,
    required this.code,
    required this.name,
    this.allowsDecimals = false,
  });

  static ErpUnit? fromJson(dynamic json) {
    final m = _map(json);
    if (m == null) return null;
    return ErpUnit(
      id: _i(m['id']),
      code: '${m['code'] ?? ''}',
      name: '${m['name'] ?? m['code'] ?? ''}',
      allowsDecimals: m['allows_decimals'] == true,
    );
  }

  final int id;
  final String code, name;
  final bool allowsDecimals;
}

/* ───────────────────────────────────────────────────────── inventory ── */

class ErpWarehouse {
  const ErpWarehouse({
    required this.id,
    required this.code,
    required this.name,
    this.type = 'warehouse',
    this.branch,
    this.isActive = true,
    this.stockValue,
    this.productsHeld,
  });

  factory ErpWarehouse.fromJson(Map<String, dynamic> json) => ErpWarehouse(
    id: _i(json['id']),
    code: '${json['code'] ?? ''}',
    name: '${json['name'] ?? ''}',
    type: '${json['type'] ?? 'warehouse'}',
    branch: _s(json['branch']),
    isActive: json['is_active'] != false,
    stockValue: _dn(json['stock_value']),
    productsHeld: _in(json['products_held']),
  );

  final int id;
  final String code, name, type;
  final String? branch;
  final bool isActive;
  final double? stockValue;
  final int? productsHeld;
}

class ErpProduct {
  const ErpProduct({
    required this.id,
    required this.sku,
    required this.name,
    this.barcode,
    this.brand,
    this.type = 'stock',
    this.category,
    this.unit,
    this.costPrice = 0,
    this.salePrice = 0,
    this.reorderLevel = 0,
    this.trackBatches = false,
    this.trackExpiry = false,
    this.trackSerials = false,
    this.isActive = true,
    this.onHand,
  });

  factory ErpProduct.fromJson(Map<String, dynamic> json) => ErpProduct(
    id: _i(json['id']),
    sku: '${json['sku'] ?? ''}',
    name: '${json['name'] ?? ''}',
    barcode: _s(json['barcode']),
    brand: _s(json['brand']),
    type: '${json['type'] ?? 'stock'}',
    category: ErpRef.fromJson(json['category']),
    unit: ErpUnit.fromJson(json['unit']),
    costPrice: _d(json['cost_price']),
    salePrice: _d(json['sale_price']),
    reorderLevel: _d(json['reorder_level']),
    trackBatches: json['track_batches'] == true,
    trackExpiry: json['track_expiry'] == true,
    trackSerials: json['track_serials'] == true,
    isActive: json['is_active'] != false,
    onHand: _dn(json['on_hand']),
  );

  final int id;
  final String sku, name, type;
  final String? barcode, brand;
  final ErpRef? category;
  final ErpUnit? unit;
  final double costPrice, salePrice, reorderLevel;
  final bool trackBatches, trackExpiry, trackSerials, isActive;
  final double? onHand;

  String get unitCode => unit?.code ?? '';

  /// Services are never counted, received or issued.
  bool get isStocked => type != 'service';

  bool get isLow => reorderLevel > 0 && (onHand ?? 0) <= reorderLevel;
}

/// GET /erp/products/{id}: the product with where it is held and its recent
/// movements.
class ErpProductDetail {
  const ErpProductDetail({
    required this.product,
    required this.onHand,
    required this.stockValue,
    required this.balances,
    required this.movements,
  });

  factory ErpProductDetail.fromJson(Map<String, dynamic> json) =>
      ErpProductDetail(
        product: ErpProduct.fromJson(json),
        onHand: _d(json['on_hand']),
        stockValue: _d(json['stock_value']),
        balances: _list(json['balances'], ErpStockBalance.fromJson),
        movements: _list(json['movements'], ErpStockMovement.fromJson),
      );

  final ErpProduct product;
  final double onHand, stockValue;
  final List<ErpStockBalance> balances;
  final List<ErpStockMovement> movements;
}

/// One product's quantity in one warehouse and batch.
class ErpStockBalance {
  const ErpStockBalance({
    required this.id,
    required this.productId,
    required this.warehouseId,
    required this.batchNumber,
    required this.quantity,
    required this.averageCost,
    this.expiryDate,
    this.value,
    this.productName,
    this.productSku,
    this.unitCode,
    this.reorderLevel,
    this.warehouse,
    this.expired = false,
  });

  factory ErpStockBalance.fromJson(Map<String, dynamic> json) {
    final p = _map(json['product']);
    final quantity = _d(json['quantity']);
    final cost = _d(json['average_cost']);
    return ErpStockBalance(
      id: _i(json['id']),
      productId: _i(json['product_id']),
      warehouseId: _i(json['warehouse_id']),
      batchNumber: '${json['batch_number'] ?? ''}',
      expiryDate: _date(json['expiry_date']),
      quantity: quantity,
      averageCost: cost,
      value: _dn(json['value']) ?? quantity * cost,
      productName: _s(p?['name']),
      productSku: _s(p?['sku']),
      unitCode: _s(_map(p?['unit'])?['code']),
      reorderLevel: _dn(p?['reorder_level']),
      warehouse: ErpRef.fromJson(json['warehouse']),
      expired: json['expired'] == true,
    );
  }

  final int id, productId, warehouseId;
  final String batchNumber;
  final DateTime? expiryDate;
  final double quantity, averageCost;
  final double? value;
  final String? productName, productSku, unitCode;
  final double? reorderLevel;
  final ErpRef? warehouse;
  final bool expired;
}

class ErpStockMovement {
  const ErpStockMovement({
    required this.id,
    required this.productId,
    required this.type,
    required this.quantity,
    required this.value,
    required this.balanceAfter,
    required this.reference,
    this.batchNumber = '',
    this.unitCost = 0,
    this.reason,
    this.movementDate,
    this.documentId,
    this.productName,
    this.warehouse,
    this.creator,
  });

  factory ErpStockMovement.fromJson(Map<String, dynamic> json) =>
      ErpStockMovement(
        id: _i(json['id']),
        productId: _i(json['product_id']),
        type: '${json['type'] ?? ''}',
        quantity: _d(json['quantity']),
        unitCost: _d(json['unit_cost']),
        value: _d(json['value']),
        balanceAfter: _d(json['balance_after']),
        reference: '${json['reference'] ?? ''}',
        batchNumber: '${json['batch_number'] ?? ''}',
        reason: _s(json['reason']),
        movementDate: _date(json['movement_date']),
        documentId: _in(json['stock_document_id']),
        productName: _s(_map(json['product'])?['name']),
        warehouse: ErpRef.fromJson(json['warehouse']),
        creator: ErpRef.fromJson(json['creator']),
      );

  final int id, productId;
  final String type, reference, batchNumber;
  final double quantity, unitCost, value, balanceAfter;
  final String? reason, productName;
  final DateTime? movementDate;
  final int? documentId;
  final ErpRef? warehouse, creator;
}

/// The kinds of stock document, the permission that prepares each, and the
/// statuses one passes through, exactly as the API checks them.
abstract class ErpDocType {
  static const grn = 'grn';
  static const issue = 'issue';
  static const transfer = 'transfer';
  static const adjustment = 'adjustment';
  static const count = 'count';
  static const opening = 'opening';

  static const all = [grn, issue, transfer, adjustment, count, opening];

  static const preparePermission = {
    opening: 'inventory.receive',
    grn: 'inventory.receive',
    issue: 'inventory.issue',
    transfer: 'inventory.transfer',
    adjustment: 'inventory.adjust',
    count: 'inventory.adjust',
  };

  /// Types whose lines carry a unit cost.
  static bool costed(String type) =>
      type == grn || type == opening || type == adjustment;
}

abstract class ErpDocStatus {
  static const draft = 'draft';
  static const posted = 'posted';
  static const cancelled = 'cancelled';
  static const reversed = 'reversed';
}

class ErpDocumentLine {
  const ErpDocumentLine({
    required this.id,
    required this.productId,
    required this.quantity,
    this.unitCost,
    this.batchNumber,
    this.expiryDate,
    this.serialNumber,
    this.systemQuantity,
    this.note,
    this.productName,
    this.productSku,
    this.unitCode,
  });

  factory ErpDocumentLine.fromJson(Map<String, dynamic> json) {
    final p = _map(json['product']);
    return ErpDocumentLine(
      id: _i(json['id']),
      productId: _i(json['product_id']),
      quantity: _d(json['quantity']),
      unitCost: _dn(json['unit_cost']),
      batchNumber: _s(json['batch_number']),
      expiryDate: _date(json['expiry_date']),
      serialNumber: _s(json['serial_number']),
      systemQuantity: _dn(json['system_quantity']),
      note: _s(json['note']),
      productName: _s(p?['name']),
      productSku: _s(p?['sku']),
      unitCode: _s(_map(p?['unit'])?['code']),
    );
  }

  final int id, productId;
  final double quantity;
  final double? unitCost, systemQuantity;
  final String? batchNumber, serialNumber, note;
  final DateTime? expiryDate;
  final String? productName, productSku, unitCode;
}

class ErpStockDocument {
  const ErpStockDocument({
    required this.id,
    required this.type,
    required this.number,
    required this.status,
    required this.warehouseId,
    this.documentDate,
    this.toWarehouseId,
    this.supplierId,
    this.reference,
    this.reason,
    this.reversalOfId,
    this.reversalOf,
    this.createdAt,
    this.postedAt,
    this.warehouse,
    this.toWarehouse,
    this.supplier,
    this.creator,
    this.poster,
    this.lines = const [],
    this.linesCount,
    this.movements = const [],
  });

  factory ErpStockDocument.fromJson(Map<String, dynamic> json) {
    final reversal = _map(json['reversal_of']);
    return ErpStockDocument(
      id: _i(json['id']),
      type: '${json['type'] ?? ''}',
      number: '${json['number'] ?? ''}',
      status: '${json['status'] ?? ErpDocStatus.draft}',
      warehouseId: _i(json['warehouse_id']),
      documentDate: _date(json['document_date']),
      toWarehouseId: _in(json['to_warehouse_id']),
      supplierId: _in(json['supplier_id']),
      reference: _s(json['reference']),
      reason: _s(json['reason']),
      reversalOfId: _in(json['reversal_of_id']),
      reversalOf: reversal == null
          ? null
          : ErpRef(_i(reversal['id']), '${reversal['number'] ?? ''}'),
      createdAt: _time(json['created_at']),
      postedAt: _time(json['posted_at']),
      warehouse: ErpRef.fromJson(json['warehouse']),
      toWarehouse: ErpRef.fromJson(json['to_warehouse']),
      supplier: ErpRef.fromJson(json['supplier']),
      creator: ErpRef.fromJson(json['creator']),
      poster: ErpRef.fromJson(json['poster']),
      lines: _list(json['lines'], ErpDocumentLine.fromJson),
      linesCount: _in(json['lines_count']),
      movements: _list(json['movements'], ErpStockMovement.fromJson),
    );
  }

  final int id, warehouseId;
  final String type, number, status;
  final DateTime? documentDate, createdAt, postedAt;
  final int? toWarehouseId, supplierId, reversalOfId, linesCount;
  final String? reference, reason;
  final ErpRef? reversalOf, warehouse, toWarehouse, supplier, creator, poster;
  final List<ErpDocumentLine> lines;
  final List<ErpStockMovement> movements;

  bool get isDraft => status == ErpDocStatus.draft;
  bool get isPosted => status == ErpDocStatus.posted;

  /// "Factory store → Arusha depot" for a transfer, the warehouse otherwise.
  String get place => [
    warehouse?.name,
    toWarehouse?.name,
  ].whereType<String>().join(' → ');
}

/// A Laravel paginator page.
class ErpPage<T> {
  const ErpPage(this.data, this.currentPage, this.lastPage, this.total);

  factory ErpPage.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) read,
  ) {
    final data = _list(json['data'], read);
    return ErpPage(
      data,
      _in(json['current_page']) ?? 1,
      _in(json['last_page']) ?? 1,
      _in(json['total']) ?? data.length,
    );
  }

  final List<T> data;
  final int currentPage, lastPage, total;

  bool get hasMore => currentPage < lastPage;
}

/// The inventory part of GET /erp/overview.
class InventoryOverview {
  const InventoryOverview({
    required this.stockValue,
    required this.products,
    required this.warehouses,
    required this.lowStock,
    required this.drafts,
    required this.movements7d,
    required this.recent,
  });

  /// Null when the caller may not see inventory (the API leaves it out).
  static InventoryOverview? fromOverview(Map<String, dynamic> json) {
    final inv = _map(json['inventory']);
    if (inv == null) return null;
    return InventoryOverview(
      stockValue: _d(inv['stock_value']),
      products: _i(inv['products']),
      warehouses: _i(inv['warehouses']),
      lowStock: _i(inv['low_stock']),
      drafts: _i(inv['drafts']),
      movements7d: {
        for (final row in _list(inv['movements_7d'], (m) => m))
          '${row['day']}'.substring(0, 10): _i(row['count']),
      },
      recent: _list(inv['recent'], ErpStockDocument.fromJson),
    );
  }

  final double stockValue;
  final int products, warehouses, lowStock, drafts;

  /// Movements per day ("2026-11-12" → 19), days without any left out.
  final Map<String, int> movements7d;
  final List<ErpStockDocument> recent;
}

class StockAlerts {
  const StockAlerts(this.lowStock, this.expiring, this.windowDays);

  factory StockAlerts.fromJson(Map<String, dynamic> json) => StockAlerts(
    _list(json['low_stock'], ErpProduct.fromJson),
    _list(json['expiring'], ErpStockBalance.fromJson),
    _in(json['expiry_window_days']) ?? 60,
  );

  final List<ErpProduct> lowStock;
  final List<ErpStockBalance> expiring;
  final int windowDays;
}

/* ───────────────────────────────────────────────────────────── drafts ── */

/// One line of a document being prepared, in the request's shape.
class StockLineDraft {
  StockLineDraft({
    required this.product,
    this.quantity = '',
    this.unitCost = '',
    this.batchNumber = '',
    this.expiryDate,
  });

  ErpProduct product;
  String quantity, unitCost, batchNumber;
  DateTime? expiryDate;

  double? get quantityValue => double.tryParse(quantity.trim());

  Map<String, dynamic> toJson() => {
    'product_id': product.id,
    'quantity': quantityValue ?? 0,
    'unit_cost': unitCost.trim().isEmpty ? null : double.tryParse(unitCost),
    'batch_number': batchNumber.trim().isEmpty ? null : batchNumber.trim(),
    'expiry_date': expiryDate == null
        ? null
        : DateFormat('yyyy-MM-dd').format(expiryDate!),
    'serial_number': null,
    'note': null,
  };
}

/// POST /erp/stock-documents, the payload the web's DocumentForm sends.
class StockDocumentDraft {
  StockDocumentDraft({
    required this.type,
    this.warehouseId,
    this.toWarehouseId,
    this.supplierId,
    DateTime? documentDate,
    this.reference = '',
    this.reason = '',
    List<StockLineDraft>? lines,
  }) : documentDate = documentDate ?? DateTime.now(),
       lines = lines ?? [];

  final String type;
  int? warehouseId, toWarehouseId, supplierId;
  DateTime documentDate;
  String reference, reason;
  final List<StockLineDraft> lines;

  Map<String, dynamic> toJson() => {
    'type': type,
    'warehouse_id': warehouseId,
    'to_warehouse_id': type == ErpDocType.transfer ? toWarehouseId : null,
    'supplier_id': type == ErpDocType.grn ? supplierId : null,
    'document_date': DateFormat('yyyy-MM-dd').format(documentDate),
    'reference': reference.trim().isEmpty ? null : reference.trim(),
    'reason': reason.trim().isEmpty ? null : reason.trim(),
    'lines': [
      for (final l in lines)
        if (l.quantityValue != null) l.toJson(),
    ],
  };
}

/* ────────────────────────────────────────────────────────── formatting ── */

/// Quantities and money as the web's `qty` and `amount` print them.
abstract class ErpFmt {
  static final _qty = NumberFormat('#,##0.####', 'en_US');
  static final _whole = NumberFormat('#,##0', 'en_US');
  static final _cents = NumberFormat('#,##0.00', 'en_US');

  /// Up to four decimals, trailing zeros dropped: 12, 12.5, 0.125.
  static String qty(num? value) => _qty.format(value ?? 0);

  /// Two decimals only when there are cents.
  static String amount(num? value) {
    final v = value ?? 0;
    return (v % 1 == 0 ? _whole : _cents).format(v);
  }

  /// "TZS 46.8M", for figures that must fit a card.
  static String compactMoney(num value, String currency) {
    final v = value.abs();
    String n(double x) => x
        .toStringAsFixed(x >= 100 ? 0 : 1)
        .replaceFirst(RegExp(r'\.0$'), '');
    final short = v >= 1e9
        ? '${n(v / 1e9)}B'
        : v >= 1e6
        ? '${n(v / 1e6)}M'
        : v >= 1e3
        ? '${n(v / 1e3)}K'
        : _whole.format(v);
    return '$currency ${value < 0 ? '-' : ''}$short';
  }

  /// A signed quantity: "+12", "-3".
  static String signed(num value) =>
      '${value > 0 ? '+' : value < 0 ? '-' : ''}${qty(value.abs())}';
}
