import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart';
import '../../data/models/finance_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/procurement_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart' show showToast;
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;
import '../erp/erp_widgets.dart';
import '../finance/fin_widgets.dart';
import '../inventory/inventory_widgets.dart' show pickProduct;

/// Raises a purchase requisition, as the web's RequisitionForm does: why it
/// is needed, by when, and the lines (a stocked product, or a service
/// described in words) with an estimated price. It is sent for approval on
/// save, or kept as a draft.
class RequisitionFormPage extends StatefulWidget {
  const RequisitionFormPage({super.key});

  @override
  State<RequisitionFormPage> createState() => _RequisitionFormPageState();
}

class _RequisitionFormPageState extends State<RequisitionFormPage> {
  final _repo = ProcurementRepository.to;
  final _justification = TextEditingController();
  final _lines = <RequisitionLineDraft>[];
  DateTime? _neededBy;
  List<ErpProduct>? _products;
  bool _busy = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _justification.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    try {
      final p = await _repo.products();
      if (mounted) setState(() => _products = p);
    } catch (_) {
      // Without the catalogue a requisition can still ask for services.
      if (mounted) setState(() => _products = const []);
    }
  }

  Future<void> _addProduct() async {
    final p = await pickProduct(
      context,
      products: _products ?? const [],
      added: {for (final l in _lines) ?l.product?.id},
    );
    if (p == null) return;
    setState(() => _lines.add(RequisitionLineDraft(product: p, price: p.costPrice > 0 ? ErpFmt.qty(p.costPrice).replaceAll(',', '') : '')));
  }

  void _addService() => setState(() => _lines.add(RequisitionLineDraft()));

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _neededBy ?? now.add(const Duration(days: 7)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) setState(() => _neededBy = picked);
  }

  Future<void> _save({required bool submit}) async {
    FocusScope.of(context).unfocus();
    final justification = _justification.text.trim();
    if (justification.length < 5) {
      setState(() => _error = ApiException(422, 'prc.justificationShort'.tr, {'justification': ['prc.justificationShort'.tr]}));
      return;
    }
    final lines = _lines.where((l) => (l.quantityValue ?? 0) > 0 && (!l.isService || l.description.trim().isNotEmpty)).toList();
    if (lines.isEmpty) {
      setState(() => _error = ApiException(422, 'prc.noLines'.tr));
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final r = await _repo.createRequisition(justification: justification, lines: lines, neededBy: _neededBy, submit: submit);
      showToast(submit ? 'prc.requisitionSubmitted'.tr : 'prc.requisitionSaved'.tr, body: r.number);
      Get.offNamed(Routes.prcRequisition, arguments: r.id);
    } on ApiException catch (e) {
      if (mounted) setState(() { _busy = false; _error = e; });
    } catch (_) {
      if (mounted) setState(() { _busy = false; _error = ApiException(0, 'state.offline'.tr); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return VouchFlowPushedScaffold(
      title: 'prc.newRequisition'.tr,
      body: ErpGate(
        module: 'procurement',
        permission: 'procurement.request',
        builder: (context) => _products == null ? const VfLoadingView() : _form(context),
      ),
      bottomBar: _products == null
          ? null
          : FinActionBar(
              children: [
                VouchFlowButton(
                  label: 'prc.saveDraft'.tr,
                  variant: VfButtonVariant.secondary,
                  onPressed: _busy ? null : () => _save(submit: false),
                ),
                VouchFlowButton(
                  label: 'prc.submitForApproval'.tr,
                  icon: PhosphorIconsRegular.paperPlaneTilt,
                  loading: _busy,
                  onPressed: _busy ? null : () => _save(submit: true),
                ),
              ],
            ),
    );
  }

  Widget _form(BuildContext context) {
    final t = context.vf;
    final total = _lines.fold<double>(0, (s, l) => s + (l.quantityValue ?? 0) * l.priceValue);
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
                  color: t.infoStrong.withValues(alpha: t.isDark ? .18 : .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(PhosphorIconsRegular.notePencil, size: 24, color: t.infoStrong),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text('prc.newRequisitionHint'.tr, style: VfType.small.copyWith(color: t.text2))),
            ],
          ),
        ),
        VouchFlowPanel(
          title: 'inv.details'.tr,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              VouchFlowTextField(
                label: 'prc.justification'.tr,
                required: true,
                controller: _justification,
                placeholder: 'prc.justificationHint'.tr,
                maxLines: 3,
                minLines: 2,
                maxLength: 2000,
                error: _error?.field('justification'),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 14),
              VouchFlowTextField(
                label: 'prc.neededByLabel'.tr,
                hint: 'inv.optional'.tr,
                readOnly: true,
                key: ValueKey(_neededBy),
                initialValue: _neededBy == null ? '' : dashDate(_neededBy),
                placeholder: 'prc.pickDate'.tr,
                suffix: Icon(PhosphorIconsRegular.calendarBlank, size: 18, color: t.muted),
                onTap: _pickDate,
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'prc.lines'.tr,
          trailing: total > 0
              ? Text(finMoney(total), style: VfType.small.copyWith(color: t.text, fontWeight: FontWeight.w600))
              : null,
          padded: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _lines.length; i++)
                _LineEditor(
                  key: ObjectKey(_lines[i]),
                  line: _lines[i],
                  divider: i > 0,
                  onChanged: () => setState(() {}),
                  onRemove: () => setState(() => _lines.removeAt(i)),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, _lines.isEmpty ? 14 : 6, 16, 16),
                child: Row(
                  children: [
                    if (_products!.isNotEmpty) ...[
                      Expanded(
                        child: VouchFlowButton(
                          label: 'prc.addProduct'.tr,
                          icon: PhosphorIconsBold.plus,
                          variant: VfButtonVariant.secondary,
                          expand: true,
                          onPressed: _addProduct,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: VouchFlowButton(
                        label: 'prc.addService'.tr,
                        icon: PhosphorIconsBold.plus,
                        variant: VfButtonVariant.secondary,
                        expand: true,
                        onPressed: _addService,
                      ),
                    ),
                  ],
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

/// One line: the product (or a description of the service), how many, and
/// the price expected.
class _LineEditor extends StatelessWidget {
  const _LineEditor({super.key, required this.line, required this.divider, required this.onChanged, required this.onRemove});

  final RequisitionLineDraft line;
  final bool divider;
  final VoidCallback onChanged, onRemove;

  static final _number = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final p = line.product;
    return Container(
      decoration: BoxDecoration(
        border: divider ? Border(top: BorderSide(color: t.border.withValues(alpha: .7), width: .6)) : null,
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(p == null ? PhosphorIconsRegular.wrench : PhosphorIconsRegular.package, size: 18, color: t.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  p == null ? 'prc.serviceLine'.tr : p.name,
                  style: VfType.bodyStrong.copyWith(color: t.text, fontSize: 14.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              VouchFlowIconButton(
                icon: PhosphorIconsRegular.trash,
                tooltip: 'prc.removeLine'.tr,
                onPressed: onRemove,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (p == null) ...[
                  const SizedBox(height: 6),
                  VouchFlowTextField(
                    label: 'prc.description'.tr,
                    required: true,
                    initialValue: line.description,
                    placeholder: 'prc.descriptionHint'.tr,
                    maxLength: 255,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (v) {
                      line.description = v;
                      onChanged();
                    },
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: VouchFlowTextField(
                        label: p?.unitCode.isNotEmpty == true ? '${'prc.quantity'.tr} (${p!.unitCode})' : 'prc.quantity'.tr,
                        required: true,
                        initialValue: line.quantity,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: _number,
                        onChanged: (v) {
                          line.quantity = v;
                          onChanged();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: VouchFlowTextField(
                        label: 'prc.estPrice'.tr,
                        initialValue: line.price,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: _number,
                        onChanged: (v) {
                          line.price = v;
                          onChanged();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
