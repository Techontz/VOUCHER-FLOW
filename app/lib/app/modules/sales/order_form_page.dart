import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart';
import '../../data/models/sales_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/sales_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart' show showToast;
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;
import '../erp/erp_widgets.dart';
import 'sales_widgets.dart';

/// Prepares a sales order or a quotation on the phone (the web's
/// SalesDocumentForm): pick the customer, add products at the customer's
/// prices, adjust quantities, and save a draft, or, for an order, save it
/// and send it for approval in one go. Opened with {'quotation': bool,
/// 'customerId': int?} as the argument.
class SalesDocumentFormPage extends StatefulWidget {
  const SalesDocumentFormPage({super.key, this.quotation, this.customerId});

  final bool? quotation;
  final int? customerId;

  @override
  State<SalesDocumentFormPage> createState() => _SalesDocumentFormPageState();
}

class _SalesDocumentFormPageState extends State<SalesDocumentFormPage> {
  late final Map _args = Get.arguments is Map ? Get.arguments as Map : const {};
  late final bool _quotation = widget.quotation ?? _args['quotation'] == true;
  late final _draft = SalesDocumentDraft(quotation: _quotation);
  final _repo = SalesRepository.to;

  SalesLookups? _lookups;
  String? _loadError;
  Map<int, double> _prices = const {};
  bool _busy = false;
  ApiException? _error;
  final _address = TextEditingController();
  final _notes = TextEditingController();

  SalesCustomer? get _customer => _lookups?.customers.where((c) => c.id == _draft.customerId).firstOrNull;

  @override
  void initState() {
    super.initState();
    if (_quotation) _draft.untilDate = DateTime.now().add(const Duration(days: 14));
    _load();
  }

  @override
  void dispose() {
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final l = await _repo.lookups();
      if (!mounted) return;
      setState(() => _lookups = l);
      final preset = widget.customerId ?? (_args['customerId'] is int ? _args['customerId'] as int : null);
      if (preset != null && l.customers.any((c) => c.id == preset)) await _setCustomer(preset);
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } catch (_) {
      if (mounted) setState(() => _loadError = 'state.offline'.tr);
    }
  }

  String _plain(double v) => ErpFmt.qty(v).replaceAll(',', '');

  Future<void> _setCustomer(int id) async {
    final previous = _prices;
    setState(() {
      _draft.customerId = id;
      final c = _customer;
      if (!_quotation && _address.text.trim().isEmpty && c?.address != null) _address.text = c!.address!;
    });
    try {
      final prices = await _repo.prices(id);
      if (!mounted) return;
      setState(() {
        _prices = prices;
        // Lines still at the old customer's price follow the new one.
        for (final l in _draft.lines) {
          final old = previous[l.product.id] ?? l.product.salePrice;
          if (l.unitPrice.isEmpty || l.priceValue == old) {
            l.unitPrice = _plain(prices[l.product.id] ?? l.product.salePrice);
          }
        }
      });
    } catch (_) {
      // Without the price list the product's own price stands.
    }
  }

  Future<void> _pickCustomer() async {
    final l = _lookups;
    if (l == null) return;
    final id = await showVfSheet<int>(
      context,
      builder: (_) => _Picker<SalesCustomer>(
        title: 'sal.pickCustomer'.tr,
        placeholder: 'sal.searchCustomers'.tr,
        items: l.customers,
        matches: (c, q) => c.name.toLowerCase().contains(q) || c.code.toLowerCase().contains(q),
        row: (ctx, c, divider) => VouchFlowListRow(
          divider: divider,
          icon: PhosphorIconsRegular.storefront,
          iconColor: ctx.vf.successStrong,
          title: c.name,
          subtitle: [c.code, ?c.city].join(' · '),
          trailing: VouchFlowStatusBadge(
            label: c.requiresPrepayment ? 'sal.prepayment'.tr : 'sal.creditDays'.trParams({'n': '${c.paymentTermsDays}'}),
            tag: c.requiresPrepayment ? 'tag-info' : 'tag-neutral',
          ),
          onTap: () => Navigator.of(ctx).pop(c.id),
        ),
      ),
    );
    if (id != null) await _setCustomer(id);
  }

  Future<void> _addLine() async {
    final l = _lookups;
    if (l == null) return;
    final added = {for (final x in _draft.lines) x.product.id};
    final currency = ErpService.to.currency;
    final p = await showVfSheet<SalesProduct>(
      context,
      builder: (_) => _Picker<SalesProduct>(
        title: 'sal.pickProduct'.tr,
        placeholder: 'sal.searchProducts'.tr,
        // What the company sells first.
        items: [...l.products.where((p) => p.salePrice > 0 || (_prices[p.id] ?? 0) > 0), ...l.products.where((p) => p.salePrice <= 0 && (_prices[p.id] ?? 0) <= 0)],
        matches: (p, q) => p.name.toLowerCase().contains(q) || p.sku.toLowerCase().contains(q),
        row: (ctx, p, divider) => VouchFlowListRow(
          divider: divider,
          icon: PhosphorIconsRegular.package,
          title: p.name,
          subtitle: [p.sku, if (p.unitCode.isNotEmpty) p.unitCode].join(' · '),
          trailing: added.contains(p.id)
              ? VouchFlowStatusBadge(label: 'sal.inOrder'.tr, tag: 'tag-info')
              : Text(
                  '$currency ${ErpFmt.amount(_prices[p.id] ?? p.salePrice)}',
                  style: VfType.small.copyWith(color: ctx.vf.text2, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
          onTap: () => Navigator.of(ctx).pop(p),
        ),
      ),
    );
    if (p == null) return;
    setState(() {
      final existing = _draft.lines.where((x) => x.product.id == p.id).firstOrNull;
      if (existing != null) {
        existing.quantity = _plain(existing.quantityValue + 1);
      } else {
        _draft.lines.add(SalesLineDraft(product: p, quantity: '1', unitPrice: _plain(_prices[p.id] ?? p.salePrice)));
      }
    });
  }

  Future<void> _pickDate({required bool until}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: until ? (_draft.untilDate ?? now) : _draft.date,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    setState(() {
      if (until) {
        _draft.untilDate = picked;
      } else {
        _draft.date = picked;
      }
    });
  }

  Future<void> _save({bool submit = false}) async {
    FocusScope.of(context).unfocus();
    if (_draft.customerId == null) {
      setState(() => _error = ApiException(422, 'sal.pickCustomerFirst'.tr));
      return;
    }
    if (!_draft.lines.any((l) => l.quantityValue > 0)) {
      setState(() => _error = ApiException(422, 'sal.noLines'.tr));
      return;
    }
    _draft
      ..deliveryAddress = _address.text
      ..notes = _notes.text;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final (id, number) = await _repo.create(_draft);
      var message = 'sal.savedDraft'.tr;
      if (submit) {
        try {
          final m = await _repo.submitOrder(id);
          message = m.isEmpty ? 'sal.submitted'.tr : m;
        } on ApiException catch (e) {
          // Saved but not submitted: the order page says why and offers it again.
          message = e.message;
        }
      }
      showToast(message, body: submit ? null : number);
      Get.offNamed(_quotation ? Routes.salesQuotation : Routes.salesOrder, arguments: id);
    } on ApiException catch (e) {
      if (mounted) setState(() { _busy = false; _error = e; });
    } catch (_) {
      if (mounted) setState(() { _busy = false; _error = ApiException(0, 'state.offline'.tr); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return VouchFlowPushedScaffold(
      title: _quotation ? 'sal.newQuotation'.tr : 'sal.newOrder'.tr,
      body: ErpGate(
        module: 'sales',
        permission: _quotation ? 'sales.quote' : 'sales.order',
        builder: (context) {
          if (_lookups == null) {
            return _loadError == null
                ? const VfLoadingView()
                : ErpPageBody(children: [VouchFlowErrorState(message: _loadError!, onRetry: _load, retryLabel: 'action.retry'.tr)]);
          }
          return _form(context);
        },
      ),
      bottomBar: _lookups == null ? null : _bar(),
    );
  }

  Widget _bar() => SalesActionBar(
    children: [
      if (_quotation)
        VouchFlowButton(
          label: 'sal.saveQuotation'.tr,
          icon: PhosphorIconsRegular.floppyDisk,
          expand: true,
          loading: _busy,
          onPressed: _busy ? null : _save,
        )
      else ...[
        VouchFlowButton(
          label: 'sal.saveDraft'.tr,
          variant: VfButtonVariant.secondary,
          onPressed: _busy ? null : _save,
        ),
        VouchFlowButton(
          label: 'sal.saveSubmit'.tr,
          icon: PhosphorIconsRegular.paperPlaneTilt,
          loading: _busy,
          onPressed: _busy ? null : () => _save(submit: true),
        ),
      ],
    ],
  );

  Widget _form(BuildContext context) {
    final t = context.vf;
    final l = _lookups!;
    final c = _customer;
    final totals = _draft.totals(l.taxRate);

    return ErpPageBody(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 18),
          child: Text(
            _quotation ? 'sal.hint.quotation'.tr : 'sal.orderFormSub'.tr,
            style: VfType.small.copyWith(color: t.text2),
          ),
        ),
        // The customer, as one big tappable card.
        VouchFlowPanel(
          title: 'sal.customer'.tr,
          padded: false,
          child: VouchFlowListRow(
            divider: false,
            icon: c == null ? PhosphorIconsRegular.userPlus : PhosphorIconsRegular.storefront,
            iconColor: c == null ? t.primary : t.successStrong,
            title: c?.name ?? 'sal.pickCustomer'.tr,
            subtitle: c == null
                ? 'sal.pickCustomerHint'.tr
                : [
                    c.requiresPrepayment ? 'sal.prepayment'.tr : 'sal.creditDays'.trParams({'n': '${c.paymentTermsDays}'}),
                    if (c.priceList != null) c.priceList!,
                  ].join(' · '),
            trailing: Icon(PhosphorIconsBold.caretRight, size: 14, color: t.faint),
            onTap: _pickCustomer,
          ),
        ),
        if (_error?.field('customer_id') case final e?)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(e, style: VfType.meta.copyWith(color: t.dangerStrong)),
          ),
        erpGap,
        VouchFlowPanel(
          title: 'sal.lines'.tr,
          trailing: Text(
            '${_draft.lines.length}',
            style: VfType.small.copyWith(color: t.muted, fontWeight: FontWeight.w600),
          ),
          padded: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _draft.lines.length; i++)
                _LineEditor(
                  key: ObjectKey(_draft.lines[i]),
                  line: _draft.lines[i],
                  index: i,
                  taxRate: l.taxRate,
                  error: _error,
                  onChanged: () => setState(() {}),
                  onRemove: () => setState(() => _draft.lines.removeAt(i)),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, _draft.lines.isEmpty ? 14 : 10, 16, 16),
                child: VouchFlowButton(
                  label: 'sal.addProduct'.tr,
                  icon: PhosphorIconsBold.plus,
                  variant: VfButtonVariant.secondary,
                  expand: true,
                  onPressed: _addLine,
                ),
              ),
            ],
          ),
        ),
        if (_draft.lines.isNotEmpty) ...[
          erpGap,
          VouchFlowPanel(
            title: 'sal.summary'.tr,
            subtitle: 'sal.vatAt'.trParams({'rate': ErpFmt.qty(l.taxRate)}),
            child: SalesTotalsBlock(totals: totals),
          ),
        ],
        erpGap,
        VouchFlowPanel(
          title: 'sal.details'.tr,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              VouchFlowTextField(
                key: ValueKey(_draft.date),
                label: _quotation ? 'sal.quoteDate'.tr : 'sal.orderDate'.tr,
                readOnly: true,
                initialValue: dashDate(_draft.date),
                suffix: Icon(PhosphorIconsRegular.calendarBlank, size: 18, color: t.muted),
                onTap: () => _pickDate(until: false),
              ),
              const SizedBox(height: 14),
              VouchFlowTextField(
                key: ValueKey('until${_draft.untilDate}'),
                label: _quotation ? 'sal.validUntilLabel'.tr : 'sal.requiredDate'.tr,
                hint: _quotation ? null : 'sal.optional'.tr,
                readOnly: true,
                initialValue: _draft.untilDate == null ? '' : dashDate(_draft.untilDate),
                error: _error?.field(_quotation ? 'valid_until' : 'required_date'),
                suffix: Icon(PhosphorIconsRegular.calendarBlank, size: 18, color: t.muted),
                onTap: () => _pickDate(until: true),
              ),
              if (!_quotation) ...[
                const SizedBox(height: 14),
                VouchFlowDropdown<int?>(
                  label: 'sal.loadFrom'.tr,
                  hint: 'sal.optional'.tr,
                  items: [null, for (final w in l.warehouses) w.id],
                  value: _draft.warehouseId,
                  itemLabel: (id) => id == null ? 'sal.anyWarehouse'.tr : l.warehouses.firstWhere((w) => w.id == id).name,
                  onChanged: (v) => setState(() => _draft.warehouseId = v),
                ),
                const SizedBox(height: 14),
                VouchFlowTextField(
                  label: 'sal.deliveryAddress'.tr,
                  hint: 'sal.optional'.tr,
                  controller: _address,
                  maxLength: 255,
                  error: _error?.field('delivery_address'),
                ),
              ],
              const SizedBox(height: 14),
              VouchFlowTextField(
                label: 'sal.notes'.tr,
                hint: 'sal.optional'.tr,
                controller: _notes,
                maxLines: 3,
                minLines: 2,
                maxLength: 2000,
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

/// One line of the form: the product, its quantity with - and + for a
/// thumb, the price, an optional discount, and what it comes to.
class _LineEditor extends StatefulWidget {
  const _LineEditor({
    super.key,
    required this.line,
    required this.index,
    required this.taxRate,
    required this.error,
    required this.onChanged,
    required this.onRemove,
  });

  final SalesLineDraft line;
  final int index;
  final double taxRate;
  final ApiException? error;
  final VoidCallback onChanged, onRemove;

  @override
  State<_LineEditor> createState() => _LineEditorState();
}

class _LineEditorState extends State<_LineEditor> {
  late final _qty = TextEditingController(text: widget.line.quantity);

  @override
  void didUpdateWidget(covariant _LineEditor old) {
    super.didUpdateWidget(old);
    // The form may change the quantity too (adding the same product again).
    if (_qty.text != widget.line.quantity) _qty.text = widget.line.quantity;
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final l = widget.line;
    final p = l.product;
    final i = widget.index;
    final error = widget.error;
    final onChanged = widget.onChanged;
    final onRemove = widget.onRemove;
    final numbers = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    final amounts = salesLineAmounts(l.quantityValue, l.priceValue, l.discountValue, widget.taxRate);

    void step(int by) {
      final next = (l.quantityValue + by).clamp(0, 999999999);
      l.quantity = ErpFmt.qty(next).replaceAll(',', '');
      _qty.text = l.quantity;
      onChanged();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.isDark ? t.glassBorder : t.border))),
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
                tooltip: 'sal.remove'.tr,
                onPressed: onRemove,
                icon: Icon(PhosphorIconsRegular.trash, size: 19, color: t.muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 5,
                  child: VouchFlowTextField(
                    label: 'sal.quantity'.tr,
                    required: true,
                    controller: _qty,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: numbers,
                    error: error?.field('lines.$i.quantity'),
                    onChanged: (v) {
                      l.quantity = v;
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 6),
                _StepButton(icon: PhosphorIconsBold.minus, tooltip: '-1', onTap: l.quantityValue >= 1 ? () => step(-1) : null),
                const SizedBox(width: 4),
                _StepButton(icon: PhosphorIconsBold.plus, tooltip: '+1', onTap: () => step(1)),
                const SizedBox(width: 10),
                Expanded(
                  flex: 5,
                  child: VouchFlowTextField(
                    label: 'sal.unitPrice'.tr,
                    initialValue: l.unitPrice,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: numbers,
                    error: error?.field('lines.$i.unit_price'),
                    onChanged: (v) {
                      l.unitPrice = v;
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 110,
                  child: VouchFlowTextField(
                    label: 'sal.discountPct'.tr,
                    initialValue: l.discount,
                    placeholder: '0',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: numbers,
                    error: error?.field('lines.$i.discount_percent'),
                    onChanged: (v) {
                      l.discount = v;
                      onChanged();
                    },
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('sal.lineTotal'.tr, style: VfType.meta.copyWith(color: t.muted)),
                      MoneyText(amounts.total, style: VfType.bodyStrong.copyWith(fontSize: 15)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (error?.field('lines.$i.product_id') case final e?)
            Text(e, style: VfType.meta.copyWith(color: t.dangerStrong)),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: t.glassFillStrong,
          shape: CircleBorder(side: BorderSide(color: t.isDark ? t.glassBorder : t.border)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(icon, size: 15, color: onTap == null ? t.faint : t.text),
            ),
          ),
        ),
      ),
    );
  }
}

/// A searchable list in a sheet, for customers and products.
class _Picker<T> extends StatefulWidget {
  const _Picker({required this.title, required this.placeholder, required this.items, required this.matches, required this.row});

  final String title, placeholder;
  final List<T> items;
  final bool Function(T item, String q) matches;
  final Widget Function(BuildContext context, T item, bool divider) row;

  @override
  State<_Picker<T>> createState() => _PickerState<T>();
}

class _PickerState<T> extends State<_Picker<T>> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final q = _q.trim().toLowerCase();
    final rows = widget.items.where((x) => q.isEmpty || widget.matches(x, q)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(widget.title, style: VfType.sectionTitle.copyWith(color: t.text)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: VouchFlowSearchField(placeholder: widget.placeholder, onChanged: (v) => setState(() => _q = v)),
            ),
            Flexible(
              child: rows.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text('sal.noMatches'.tr, textAlign: TextAlign.center, style: VfType.small.copyWith(color: t.muted)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: rows.length,
                      itemBuilder: (ctx, i) => widget.row(ctx, rows[i], i > 0),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
