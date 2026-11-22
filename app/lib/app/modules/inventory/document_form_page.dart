import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/inventory_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart' show showToast;
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;
import '../erp/erp_widgets.dart';
import 'inventory_widgets.dart';

/// Prepares a goods received note, a stock issue or a transfer, exactly as
/// the web's DocumentForm does: the fields follow the type and the product
/// (a GRN asks for cost, a batch-tracked product for its batch, a
/// perishable one for its expiry), and saving leaves a draft; nothing
/// moves until it is posted. Opened with {'type': 'grn' | 'issue' |
/// 'transfer'} as the argument.
class DocumentFormPage extends StatefulWidget {
  const DocumentFormPage({super.key, this.type});

  final String? type;

  @override
  State<DocumentFormPage> createState() => _DocumentFormPageState();
}

class _DocumentFormPageState extends State<DocumentFormPage> {
  late final String _type = widget.type ?? '${(Get.arguments as Map?)?['type'] ?? ErpDocType.grn}';
  final _repo = InventoryRepository.to;
  final _erp = ErpService.to;

  List<ErpWarehouse>? _warehouses;
  List<ErpProduct> _products = const [];
  List<ErpRef> _suppliers = const [];
  String? _loadError;

  late final _draft = StockDocumentDraft(type: _type);
  final _reference = TextEditingController();
  final _reason = TextEditingController();
  bool _busy = false;
  ApiException? _error;

  bool get _costed => ErpDocType.costed(_type);
  bool get _transfer => _type == ErpDocType.transfer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reference.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final results = await Future.wait([
        _repo.warehouses(activeOnly: true),
        _repo.products(activeOnly: true),
      ]);
      final warehouses = results[0] as List<ErpWarehouse>;
      if (!mounted) return;
      setState(() {
        _warehouses = warehouses;
        _products = (results[1] as ErpPage<ErpProduct>).data.where((p) => p.isStocked).toList();
        _draft.warehouseId ??= warehouses.firstOrNull?.id;
      });
      if (_type == ErpDocType.grn && _erp.has('procurement') && _erp.can('suppliers.view')) {
        final s = await _repo.suppliers();
        if (mounted) setState(() => _suppliers = s);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } catch (_) {
      if (mounted) setState(() => _loadError = 'state.offline'.tr);
    }
  }

  Future<void> _addLine() async {
    final p = await pickProduct(
      context,
      products: _products,
      added: {for (final l in _draft.lines) l.product.id},
    );
    if (p == null) return;
    setState(() {
      _draft.lines.add(
        StockLineDraft(product: p, unitCost: _costed && p.costPrice > 0 ? ErpFmt.qty(p.costPrice).replaceAll(',', '') : ''),
      );
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _draft.documentDate,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (picked != null) setState(() => _draft.documentDate = picked);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_draft.lines.any((l) => l.quantityValue != null && l.quantityValue! > 0)) {
      setState(() => _error = ApiException(422, 'inv.noLines'.tr));
      return;
    }
    if (_transfer && (_draft.toWarehouseId == null || _draft.toWarehouseId == _draft.warehouseId)) {
      setState(() => _error = ApiException(422, 'inv.sameWarehouse'.tr));
      return;
    }
    _draft
      ..reference = _reference.text
      ..reason = _reason.text;
    setState(() { _busy = true; _error = null; });
    try {
      final doc = await _repo.create(_draft);
      showToast('inv.saved'.tr, body: doc.number);
      // The draft is the next thing to look at, not the form.
      Get.offNamed(Routes.erpDocument, arguments: doc.id);
    } on ApiException catch (e) {
      if (mounted) setState(() { _busy = false; _error = e; });
    } catch (_) {
      if (mounted) setState(() { _busy = false; _error = ApiException(0, 'state.offline'.tr); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return VouchFlowPushedScaffold(
      title: docTypeLabel(_type),
      body: ErpGate(
        module: 'inventory',
        permission: ErpDocType.preparePermission[_type],
        builder: (context) {
          if (_warehouses == null) {
            return _loadError == null
                ? const VfLoadingView()
                : ErpPageBody(children: [VouchFlowErrorState(message: _loadError!, onRetry: _load, retryLabel: 'action.retry'.tr)]);
          }
          return _form(context);
        },
      ),
      bottomBar: _warehouses == null ? null : _bar(context),
    );
  }

  Widget _bar(BuildContext context) {
    final t = context.vf;
    return VfGlass(
      borderRadius: BorderRadius.zero,
      fill: t.barFill,
      highlight: false,
      shadow: false,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(VfSize.pagePad, 12, VfSize.pagePad, 12),
          child: VouchFlowButton(
            label: 'inv.saveDraft'.tr,
            icon: PhosphorIconsRegular.floppyDisk,
            expand: true,
            loading: _busy,
            onPressed: _busy ? null : _save,
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final t = context.vf;
    final warehouses = _warehouses!;
    final currency = _erp.currency;
    final total = _draft.lines.fold<double>(
      0,
      (s, l) => s + (l.quantityValue ?? 0) * (double.tryParse(l.unitCost) ?? 0),
    );

    return ErpPageBody(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 18),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: docTypeTint(t, _type).withValues(alpha: t.isDark ? .18 : .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(docTypeIcon(_type), size: 24, color: docTypeTint(t, _type)),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(docTypeHint(_type), style: VfType.small.copyWith(color: t.text2))),
            ],
          ),
        ),
        VouchFlowPanel(
          title: 'inv.details'.tr,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              VouchFlowDropdown<int>(
                label: _transfer ? 'inv.from'.tr : 'inv.warehouse'.tr,
                required: true,
                items: [for (final w in warehouses) w.id],
                value: _draft.warehouseId,
                itemLabel: (id) => warehouses.firstWhere((w) => w.id == id).name,
                error: _error?.field('warehouse_id'),
                onChanged: (v) => setState(() => _draft.warehouseId = v),
              ),
              if (_transfer) ...[
                const SizedBox(height: 14),
                VouchFlowDropdown<int>(
                  label: 'inv.to'.tr,
                  required: true,
                  placeholder: 'inv.pickWarehouse'.tr,
                  items: [for (final w in warehouses) if (w.id != _draft.warehouseId) w.id],
                  value: _draft.toWarehouseId,
                  itemLabel: (id) => warehouses.firstWhere((w) => w.id == id).name,
                  error: _error?.field('to_warehouse_id'),
                  onChanged: (v) => setState(() => _draft.toWarehouseId = v),
                ),
              ],
              if (_type == ErpDocType.grn && _suppliers.isNotEmpty) ...[
                const SizedBox(height: 14),
                VouchFlowDropdown<int>(
                  label: 'inv.supplier'.tr,
                  hint: 'inv.optional'.tr,
                  placeholder: 'inv.noSupplier'.tr,
                  items: [for (final s in _suppliers) s.id],
                  value: _draft.supplierId,
                  itemLabel: (id) => _suppliers.firstWhere((s) => s.id == id).name,
                  onChanged: (v) => setState(() => _draft.supplierId = v),
                ),
              ],
              const SizedBox(height: 14),
              VouchFlowTextField(
                label: 'inv.date'.tr,
                readOnly: true,
                initialValue: dashDate(_draft.documentDate),
                key: ValueKey(_draft.documentDate),
                suffix: Icon(PhosphorIconsRegular.calendarBlank, size: 18, color: t.muted),
                onTap: _pickDate,
              ),
              const SizedBox(height: 14),
              VouchFlowTextField(
                label: 'inv.reference'.tr,
                hint: 'inv.optional'.tr,
                controller: _reference,
                maxLength: 80,
              ),
              const SizedBox(height: 14),
              VouchFlowTextField(
                label: 'inv.reason'.tr,
                hint: 'inv.optional'.tr,
                controller: _reason,
                maxLength: 255,
              ),
            ],
          ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'inv.lines'.tr,
          trailing: _costed && total > 0
              ? Text(
                  '$currency ${ErpFmt.amount(total)}',
                  style: VfType.small.copyWith(color: t.text, fontWeight: FontWeight.w600),
                )
              : null,
          padded: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _draft.lines.length; i++)
                _LineEditor(
                  key: ObjectKey(_draft.lines[i]),
                  line: _draft.lines[i],
                  index: i,
                  type: _type,
                  error: _error,
                  onChanged: () => setState(() {}),
                  onRemove: () => setState(() => _draft.lines.removeAt(i)),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, _draft.lines.isEmpty ? 14 : 4, 16, 16),
                child: VouchFlowButton(
                  label: 'inv.addProduct'.tr,
                  icon: PhosphorIconsBold.plus,
                  variant: VfButtonVariant.secondary,
                  expand: true,
                  onPressed: _addLine,
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          erpGap,
          VouchFlowAlert(message: _error!.message, tone: VfTone.bad, icon: PhosphorIconsRegular.warningCircle),
        ],
      ],
    );
  }
}

/// One line of the form: product, quantity, and the cost, batch and expiry
/// fields this type and product need.
class _LineEditor extends StatefulWidget {
  const _LineEditor({
    super.key,
    required this.line,
    required this.index,
    required this.type,
    required this.error,
    required this.onChanged,
    required this.onRemove,
  });

  final StockLineDraft line;
  final int index;
  final String type;
  final ApiException? error;
  final VoidCallback onChanged, onRemove;

  @override
  State<_LineEditor> createState() => _LineEditorState();
}

class _LineEditorState extends State<_LineEditor> {
  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.line.expiryDate ?? now.add(const Duration(days: 365)),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) {
      widget.line.expiryDate = picked;
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final l = widget.line;
    final p = l.product;
    final i = widget.index;
    final costed = ErpDocType.costed(widget.type);
    final expiry = p.trackExpiry && costed;
    final numbers = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.isDark ? t.glassBorder : t.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: VfType.bodyStrong.copyWith(color: t.text, height: 1.3)),
                    Text(
                      [p.sku, if (p.unitCode.isNotEmpty) p.unitCode].join(' · '),
                      style: VfType.meta.copyWith(color: t.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'inv.remove'.tr,
                onPressed: widget.onRemove,
                icon: Icon(PhosphorIconsRegular.trash, size: 19, color: t.muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: VouchFlowTextField(
                    label: 'inv.quantity'.tr,
                    required: true,
                    initialValue: l.quantity,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: numbers,
                    error: widget.error?.field('lines.$i.quantity'),
                    onChanged: (v) {
                      l.quantity = v;
                      widget.onChanged();
                    },
                  ),
                ),
                if (costed) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: VouchFlowTextField(
                      label: 'inv.unitCost'.tr,
                      initialValue: l.unitCost,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: numbers,
                      error: widget.error?.field('lines.$i.unit_cost'),
                      onChanged: (v) {
                        l.unitCost = v;
                        widget.onChanged();
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (p.trackBatches || expiry) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (p.trackBatches)
                    Expanded(
                      child: VouchFlowTextField(
                        label: 'inv.batch'.tr,
                        initialValue: l.batchNumber,
                        textCapitalization: TextCapitalization.characters,
                        error: widget.error?.field('lines.$i.batch_number'),
                        onChanged: (v) => l.batchNumber = v,
                      ),
                    ),
                  if (p.trackBatches && expiry) const SizedBox(width: 10),
                  if (expiry)
                    Expanded(
                      child: VouchFlowTextField(
                        key: ValueKey(l.expiryDate),
                        label: 'inv.expiry'.tr,
                        readOnly: true,
                        initialValue: l.expiryDate == null ? '' : dashDate(l.expiryDate),
                        suffix: Icon(PhosphorIconsRegular.calendarBlank, size: 18, color: t.muted),
                        error: widget.error?.field('lines.$i.expiry_date'),
                        onTap: _pickExpiry,
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (widget.error?.field('lines.$i.product_id') case final e?)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(e, style: VfType.meta.copyWith(color: t.dangerStrong)),
            ),
        ],
      ),
    );
  }
}
