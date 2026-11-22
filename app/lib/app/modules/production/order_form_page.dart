import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart';
import '../../data/models/ops_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/production_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart' show showToast;
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;
import '../erp/erp_widgets.dart';
import '../erp/ops_kit.dart';

/// Plans a production order (the web's /erp/production/orders/new): the
/// finished product and quantity, where materials come from and output
/// goes, and the planned dates. A requirement check shows what the store
/// can supply before it is saved; the saved order opens next.
class ProductionOrderFormPage extends StatefulWidget {
  const ProductionOrderFormPage({super.key});

  @override
  State<ProductionOrderFormPage> createState() => _ProductionOrderFormPageState();
}

class _ProductionOrderFormPageState extends State<ProductionOrderFormPage> {
  final _repo = ProductionRepository.to;
  final _draft = PrdOrderDraft();
  final _qty = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  PrdOptions? _options;
  String? _loadError;
  bool _busy = false;
  ApiException? _error;

  ({List<PrdRequirement> requirements, double? unitCost})? _check;
  String? _checkError;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _qty.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final o = await _repo.options();
      if (!mounted) return;
      setState(() {
        _options = o;
        _draft.productId ??= o.finished.firstOrNull?.id;
        _draft.materialsWarehouseId ??= o.warehouses.firstOrNull?.id;
        _draft.outputWarehouseId ??= (o.warehouses.length > 1 ? o.warehouses[1] : o.warehouses.firstOrNull)?.id;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = opsError(e));
    }
  }

  Future<void> _runCheck() async {
    _draft.quantity = _qty.text;
    if ((double.tryParse(_qty.text) ?? 0) <= 0 || _draft.productId == null || _draft.materialsWarehouseId == null) return;
    setState(() { _checking = true; _checkError = null; });
    try {
      final c = await _repo.check(_draft);
      if (mounted) setState(() => _check = c);
    } catch (e) {
      if (mounted) setState(() { _check = null; _checkError = opsError(e); });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _pick(bool start) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _draft.start : _draft.end,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _draft.start = picked;
        if (_draft.end.isBefore(picked)) _draft.end = picked;
      } else {
        _draft.end = picked.isBefore(_draft.start) ? _draft.start : picked;
      }
    });
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    _draft
      ..quantity = _qty.text
      ..reference = _reference.text
      ..notes = _notes.text;
    setState(() { _busy = true; _error = null; });
    try {
      final order = await _repo.plan(_draft);
      showToast('prd.planned.done'.tr, body: order.number);
      Get.offNamed(Routes.prdOrder, arguments: order.id);
    } on ApiException catch (e) {
      if (mounted) setState(() { _busy = false; _error = e; });
    } catch (_) {
      if (mounted) setState(() { _busy = false; _error = ApiException(0, 'state.offline'.tr); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return VouchFlowPushedScaffold(
      title: 'prd.newOrder'.tr,
      body: ErpGate(
        module: 'production',
        permission: 'production.plan',
        builder: (context) {
          if (_options == null) {
            return _loadError == null
                ? const VfLoadingView()
                : ErpPageBody(children: [VouchFlowErrorState(message: _loadError!, onRetry: _load, retryLabel: 'action.retry'.tr)]);
          }
          return _form(context, _options!);
        },
      ),
      bottomBar: _options == null || !ErpService.to.can('production.plan')
          ? null
          : OpsActionBar(
              children: [
                VouchFlowButton(
                  label: 'prd.plan'.tr,
                  icon: PhosphorIconsRegular.calendarCheck,
                  expand: true,
                  loading: _busy,
                  onPressed: _busy || (double.tryParse(_qty.text) ?? 0) <= 0 ? null : _save,
                ),
              ],
            ),
    );
  }

  Widget _form(BuildContext context, PrdOptions o) {
    final t = context.vf;
    final product = o.finished.where((p) => p.id == _draft.productId).firstOrNull;
    final check = _check;
    final short = check?.requirements.where((r) => !r.sufficient).toList() ?? const [];
    final currency = ErpService.to.currency;
    final qty = double.tryParse(_qty.text) ?? 0;

    return ErpPageBody(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 18),
          child: Text('prd.newOrderSub'.tr, style: VfType.small.copyWith(color: t.text2)),
        ),
        if (o.finished.isEmpty)
          VouchFlowAlert(message: 'prd.noFinished'.tr, tone: VfTone.warn, icon: PhosphorIconsRegular.warning)
        else
          VouchFlowPanel(
            title: 'prd.whatToMake'.tr,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                VouchFlowDropdown<int>(
                  label: 'prd.product'.tr,
                  required: true,
                  items: [for (final p in o.finished) p.id],
                  value: _draft.productId,
                  itemLabel: (id) => o.finished.firstWhere((p) => p.id == id).name,
                  error: _error?.field('product_id'),
                  onChanged: (v) => setState(() { _draft.productId = v; _check = null; }),
                ),
                const SizedBox(height: 14),
                VouchFlowTextField(
                  label: 'prd.plannedQty'.tr,
                  required: true,
                  controller: _qty,
                  suffix: product == null || product.unit.isEmpty
                      ? null
                      : Text(product.unit, style: VfType.small.copyWith(color: t.muted)),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  error: _error?.field('planned_quantity'),
                  onChanged: (_) => setState(() => _check = null),
                ),
                const SizedBox(height: 14),
                VouchFlowDropdown<int>(
                  label: 'prd.materialsFrom'.tr,
                  required: true,
                  items: [for (final w in o.warehouses) w.id],
                  value: _draft.materialsWarehouseId,
                  itemLabel: (id) => o.warehouses.firstWhere((w) => w.id == id).name,
                  error: _error?.field('materials_warehouse_id'),
                  onChanged: (v) => setState(() { _draft.materialsWarehouseId = v; _check = null; }),
                ),
                const SizedBox(height: 14),
                VouchFlowDropdown<int>(
                  label: 'prd.outputTo'.tr,
                  required: true,
                  items: [for (final w in o.warehouses) w.id],
                  value: _draft.outputWarehouseId,
                  itemLabel: (id) => o.warehouses.firstWhere((w) => w.id == id).name,
                  error: _error?.field('output_warehouse_id'),
                  onChanged: (v) => setState(() => _draft.outputWarehouseId = v),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: VouchFlowTextField(
                        key: ValueKey(('s', _draft.start)),
                        label: 'prd.plannedStart'.tr,
                        readOnly: true,
                        initialValue: dashDate(_draft.start),
                        error: _error?.field('planned_start'),
                        onTap: () => _pick(true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: VouchFlowTextField(
                        key: ValueKey(('e', _draft.end)),
                        label: 'prd.plannedEnd'.tr,
                        readOnly: true,
                        initialValue: dashDate(_draft.end),
                        error: _error?.field('planned_end'),
                        onTap: () => _pick(false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                VouchFlowTextField(label: 'inv.reference'.tr, hint: 'inv.optional'.tr, controller: _reference, maxLength: 80),
                const SizedBox(height: 14),
                VouchFlowTextField(label: 'prd.notes'.tr, hint: 'inv.optional'.tr, controller: _notes, maxLines: 3, minLines: 1),
              ],
            ),
          ),
        erpGap,
        VouchFlowPanel(
          title: 'prd.requirementCheck'.tr,
          trailing: check == null
              ? null
              : OpsBadge(
                  short.isEmpty ? 'prd.allAvailable'.tr : 'prd.shortN'.trParams({'n': '${short.length}'}),
                  tone: short.isEmpty ? VfTone.ok : VfTone.warn,
                ),
          padded: check == null,
          child: check == null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_checkError ?? 'prd.checkHint'.tr, style: VfType.small.copyWith(color: _checkError == null ? t.muted : t.dangerStrong)),
                    const SizedBox(height: 12),
                    VouchFlowButton(
                      label: 'prd.checkMaterials'.tr,
                      icon: PhosphorIconsRegular.listMagnifyingGlass,
                      variant: VfButtonVariant.secondary,
                      loading: _checking,
                      onPressed: qty > 0 && !_checking ? _runCheck : null,
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (check.unitCost != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                        child: Text(
                          'prd.standardLine'.trParams({
                            'cost': '$currency ${ErpFmt.amount(check.unitCost!.round())}',
                            'total': '$currency ${ErpFmt.amount((check.unitCost! * qty).round())}',
                          }),
                          style: VfType.small.copyWith(color: t.text2),
                        ),
                      ),
                    for (var i = 0; i < check.requirements.length; i++)
                      VouchFlowListRow(
                        divider: i > 0 || check.unitCost != null,
                        title: check.requirements[i].name,
                        subtitle: '${'prd.inStore'.tr} ${ErpFmt.qty(check.requirements[i].available)} ${check.requirements[i].unit}',
                        trailing: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              ErpFmt.qty(check.requirements[i].required),
                              style: VfType.bodyStrong.copyWith(color: t.text, fontSize: 14.5, fontFeatures: const [FontFeature.tabularFigures()]),
                            ),
                            if (!check.requirements[i].sufficient)
                              OpsBadge('prd.short'.tr, tone: VfTone.bad)
                            else
                              Text('prd.enough'.tr, style: VfType.meta.copyWith(color: t.successStrong)),
                          ],
                        ),
                      ),
                    if (short.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                        child: Text('prd.shortHint'.tr, style: VfType.meta.copyWith(color: t.muted)),
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
