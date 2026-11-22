import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/dev_hooks.dart';
import '../../core/theme.dart';
import '../../data/models/erp_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/inventory_repository.dart';
import '../../data/services/session_service.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart' show showToast;
import '../../widgets/vf/vf.dart';
import '../erp/erp_widgets.dart';
import 'inventory_widgets.dart';

/// The count in progress. It outlives the Count tab, so a storekeeper who
/// glances at Stock mid-count comes back to every line still there; it is
/// cleared once saved, and whenever someone else signs in.
class StockCountController extends GetxController {
  StockCountController({InventoryRepository? repo}) : _repo = repo ?? InventoryRepository.to;

  final InventoryRepository _repo;

  static StockCountController get to =>
      Get.isRegistered<StockCountController>() ? Get.find() : Get.put(StockCountController());

  final warehouses = <ErpWarehouse>[].obs;
  final warehouseId = RxnInt();
  final lines = <StockLineDraft>[].obs;
  final loading = true.obs;
  final saving = false.obs;
  final error = RxnString();
  List<ErpProduct> products = const [];

  int? _owner;

  /// Starts afresh for [userId] when the count belongs to someone else.
  Future<void> openFor(int? userId) async {
    if (_owner != userId) {
      _owner = userId;
      lines.clear();
      warehouseId.value = null;
      warehouses.clear();
      products = const [];
    }
    if (warehouses.isEmpty) {
      await load();
      _devPrefill();
    }
  }

  /// Development only: starts with the count [DevHooks.count] describes.
  void _devPrefill() {
    final spec = DevHooks.count;
    if (spec == null || !spec.contains(':') || lines.isNotEmpty) return;
    final [wh, items] = spec.split(':');
    warehouseId.value = int.tryParse(wh);
    for (final item in items.split(',').reversed) {
      final [id, qty] = [...item.split('='), ''].take(2).toList();
      final p = products.firstWhereOrNull((p) => '${p.id}' == id);
      if (p != null) add(p).quantity = qty;
    }
  }

  Future<void> load() async {
    loading.value = true;
    error.value = null;
    try {
      final results = await Future.wait([
        _repo.warehouses(activeOnly: true),
        _repo.products(activeOnly: true),
      ]);
      warehouses.assignAll(results[0] as List<ErpWarehouse>);
      products = (results[1] as ErpPage<ErpProduct>).data.where((p) => p.isStocked).toList();
      if (warehouseId.value == null && warehouses.length == 1) warehouseId.value = warehouses.first.id;
    } on ApiException catch (e) {
      error.value = e.message;
    } catch (_) {
      error.value = 'state.offline'.tr;
    } finally {
      loading.value = false;
    }
  }

  /// Adds [p] to the top of the count, where the eye already is. A product
  /// counted per batch may appear once per batch; any other product is
  /// counted once, so choosing it again returns its existing line.
  StockLineDraft add(ErpProduct p) {
    if (!p.trackBatches) {
      final existing = lines.firstWhereOrNull((l) => l.product.id == p.id);
      if (existing != null) return existing;
    }
    final line = StockLineDraft(product: p);
    lines.insert(0, line);
    return line;
  }

  void remove(StockLineDraft line) => lines.remove(line);

  /// Tells the list a line's figures changed (they are plain fields).
  void touch() => lines.refresh();

  bool get complete => lines.isNotEmpty && lines.every((l) => l.quantityValue != null && l.quantityValue! >= 0);

  /// Saves the count as a draft and, when [post], posts it. Returns the
  /// document's id, or null with [error] set.
  Future<int?> save({bool post = false}) async {
    final wh = warehouseId.value;
    if (wh == null || !complete) {
      error.value = 'inv.count.missing'.tr;
      return null;
    }
    saving.value = true;
    error.value = null;
    try {
      final doc = await _repo.create(
        StockDocumentDraft(type: ErpDocType.count, warehouseId: wh, lines: lines.toList()),
      );
      if (post) await _repo.post(doc.id);
      lines.clear();
      return doc.id;
    } on ApiException catch (e) {
      error.value = e.message;
      return null;
    } catch (_) {
      error.value = 'state.offline'.tr;
      return null;
    } finally {
      saving.value = false;
    }
  }
}

/// The Count tab: pick the warehouse, find each product on the shelf, key
/// in what you count, save the count as a draft (and post it, when your
/// role posts). Built for one hand on a warehouse floor: big targets, the
/// newest line on top, steppers beside every figure.
///
/// It is a blind count: the system quantity is not shown, so what is keyed
/// in is what is on the shelf. The difference appears once posted.
class StockCountPage extends StatelessWidget {
  const StockCountPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'inventory',
    permission: 'inventory.adjust',
    builder: (_) => const _Count(),
  );
}

class _Count extends StatefulWidget {
  const _Count();

  @override
  State<_Count> createState() => _CountState();
}

class _CountState extends State<_Count> {
  final c = StockCountController.to;
  final _erp = ErpService.to;

  /// Showing every warehouse again mid-count, to move to another.
  bool _choosing = false;

  @override
  void initState() {
    super.initState();
    final me = Get.isRegistered<SessionService>() ? Get.find<SessionService>().user.value?.id : null;
    c.openFor(me);
  }

  Future<void> _pickWarehouse(int id) async {
    if (id == c.warehouseId.value) return;
    if (c.lines.isNotEmpty) {
      final ok = await showVouchFlowDialog<bool>(
        context,
        dialog: VouchFlowDialog(
          icon: PhosphorIconsRegular.warehouse,
          tone: VfTone.warn,
          title: 'inv.count.changeWarehouse'.tr,
          subtitle: 'inv.count.changeWarehouseSub'.tr,
          actions: [
            Builder(
              builder: (ctx) => VouchFlowButton(
                label: 'action.cancel'.tr,
                variant: VfButtonVariant.secondary,
                onPressed: () => Navigator.of(ctx).pop(false),
              ),
            ),
            Builder(
              builder: (ctx) => VouchFlowButton(
                label: 'inv.count.change'.tr,
                variant: VfButtonVariant.dangerSolid,
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
            ),
          ],
        ),
      );
      if (ok != true) return;
      c.lines.clear();
    }
    c.warehouseId.value = id;
  }

  Future<void> _add() async {
    final p = await pickProduct(
      context,
      products: c.products,
      added: {for (final l in c.lines) l.product.id},
      title: 'inv.count.search'.tr,
    );
    if (p == null) return;
    c.add(p);
  }

  Future<void> _save({required bool post}) async {
    FocusScope.of(context).unfocus();
    if (post) {
      final wh = c.warehouses.firstWhereOrNull((w) => w.id == c.warehouseId.value);
      final ok = await showVouchFlowDialog<bool>(
        context,
        dialog: VouchFlowDialog(
          icon: PhosphorIconsRegular.checkCircle,
          title: '${'inv.saveAndPost'.tr}?',
          subtitle: 'inv.postSub'.tr,
          summary: [
            VfSummaryRow('inv.type'.tr, docTypeLabel(ErpDocType.count)),
            VfSummaryRow('inv.warehouse'.tr, wh?.name ?? ''),
            VfSummaryRow('inv.lines'.tr, '${c.lines.length}'),
          ],
          actions: [
            Builder(
              builder: (ctx) => VouchFlowButton(
                label: 'action.back'.tr,
                variant: VfButtonVariant.secondary,
                onPressed: () => Navigator.of(ctx).pop(false),
              ),
            ),
            Builder(
              builder: (ctx) => VouchFlowButton(
                label: 'inv.saveAndPost'.tr,
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    final id = await c.save(post: post);
    if (id == null) return;
    showToast(post ? 'inv.status.posted'.tr : 'inv.saved'.tr);
    await Get.toNamed(Routes.erpDocument, arguments: id);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Obx(() {
      if (c.loading.value && c.warehouses.isEmpty) return const VfLoadingView();
      if (c.error.value != null && c.warehouses.isEmpty) {
        return ErpPageBody(
          children: [VouchFlowErrorState(message: c.error.value!, onRetry: c.load, retryLabel: 'action.retry'.tr)],
        );
      }
      final lines = c.lines.toList();
      final wh = c.warehouseId.value;
      final canPost = _erp.can('inventory.post');
      return Column(
        children: [
          Expanded(
            child: ErpPageBody(
              children: [
                // Once counting has begun the hint and the warehouse list
                // fold away, so the lines keep the screen.
                ErpPageTitle('inv.count.title'.tr, subtitle: lines.isEmpty ? 'inv.count.hint'.tr : null),
                _Section(label: 'inv.count.where'.tr),
                VouchFlowPanel(
                  padded: false,
                  child: Column(
                    children: [
                      for (final (i, w) in c.warehouses
                          .where((w) => _choosing || lines.isEmpty || w.id == wh)
                          .indexed)
                        _WarehouseChoice(
                          warehouse: w,
                          selected: w.id == wh,
                          divider: i > 0,
                          collapsed: !_choosing && lines.isNotEmpty,
                          onTap: () async {
                            if (!_choosing && lines.isNotEmpty) {
                              setState(() => _choosing = true);
                              return;
                            }
                            await _pickWarehouse(w.id);
                            if (mounted) setState(() => _choosing = false);
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (wh != null) ...[
                  _FindButton(onTap: _add),
                  const SizedBox(height: 14),
                  if (lines.isEmpty)
                    DecoratedBox(
                      decoration: vfCardDecoration(t),
                      child: VouchFlowEmptyState(
                        icon: PhosphorIconsRegular.listNumbers,
                        title: 'inv.count.empty'.tr,
                        body: 'inv.count.emptyBody'.tr,
                      ),
                    )
                  else ...[
                    _Section(
                      label: lines.length == 1
                          ? 'inv.count.oneItem'.tr
                          : 'inv.count.items'.trParams({'n': '${lines.length}'}),
                    ),
                    for (final line in lines) ...[
                      _CountLine(
                        key: ObjectKey(line),
                        line: line,
                        onChanged: c.touch,
                        onRemove: () => c.remove(line),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ],
              ],
            ),
          ),
          if (wh != null && lines.isNotEmpty)
            _SaveBar(
              busy: c.saving.value,
              error: c.error.value,
              ready: c.complete,
              canPost: canPost,
              onSave: () => _save(post: false),
              onPost: () => _save(post: true),
            ),
        ],
      );
    });
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
    child: Text(
      label,
      style: VfType.label.copyWith(color: context.vf.text2, fontWeight: FontWeight.w600),
    ),
  );
}

class _WarehouseChoice extends StatelessWidget {
  const _WarehouseChoice({
    required this.warehouse,
    required this.selected,
    required this.divider,
    required this.onTap,
    this.collapsed = false,
  });

  final ErpWarehouse warehouse;
  final bool selected, divider;

  /// The only row shown mid-count: it offers to change instead of a tick.
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: VouchFlowListRow(
        divider: divider,
        icon: PhosphorIconsRegular.warehouse,
        iconColor: selected ? t.primary : t.muted,
        title: warehouse.name,
        subtitle: [warehouse.code, ?warehouse.branch].join(' · '),
        onTap: onTap,
        trailing: collapsed
            ? VouchFlowPanelAction(label: 'inv.count.changeShort'.tr, onTap: onTap)
            : Icon(
                selected ? PhosphorIconsFill.checkCircle : PhosphorIconsRegular.circle,
                size: 22,
                color: selected ? t.primary : t.borderStrong,
              ),
      ),
    );
  }
}

/// A search bar that opens the product picker: the count's main action.
class _FindButton extends StatelessWidget {
  const _FindButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Semantics(
      button: true,
      label: 'inv.count.search'.tr,
      excludeSemantics: true,
      child: Material(
        color: t.isDark ? t.glassFill : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VfSize.radiusL),
          side: BorderSide(color: t.primaryBorder, width: 1.2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                const SizedBox(width: 16),
                Icon(PhosphorIconsRegular.magnifyingGlass, size: 20, color: t.primaryText),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('inv.count.search'.tr, style: VfType.body.copyWith(color: t.text2)),
                ),
                Container(
                  width: 36,
                  height: 36,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(color: t.primary, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(PhosphorIconsBold.plus, size: 18, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One counted product: its name, the batch when it is counted per batch,
/// and the counted figure between a minus and a plus.
class _CountLine extends StatefulWidget {
  const _CountLine({super.key, required this.line, required this.onChanged, required this.onRemove});

  final StockLineDraft line;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  State<_CountLine> createState() => _CountLineState();
}

class _CountLineState extends State<_CountLine> {
  late final _qty = TextEditingController(text: widget.line.quantity);
  late final _batch = TextEditingController(text: widget.line.batchNumber);

  @override
  void dispose() {
    _qty.dispose();
    _batch.dispose();
    super.dispose();
  }

  void _step(int delta) {
    final now = double.tryParse(_qty.text.trim()) ?? 0;
    final next = (now + delta).clamp(0, double.infinity);
    _qty.text = ErpFmt.qty(next).replaceAll(',', '');
    widget.line.quantity = _qty.text;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final p = widget.line.product;
    return DecoratedBox(
      decoration: vfCardDecoration(t),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 6, 14),
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
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Row(
                children: [
                  if (p.trackBatches) ...[
                    Expanded(
                      child: TextField(
                        controller: _batch,
                        textCapitalization: TextCapitalization.characters,
                        style: VfType.body.copyWith(color: t.text),
                        decoration: vfInputDecoration(
                          context,
                          hintText: 'inv.batch'.tr,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        ),
                        onChanged: (v) {
                          widget.line.batchNumber = v;
                          widget.onChanged();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                  ] else
                    const Spacer(),
                  _Stepper(icon: PhosphorIconsBold.minus, tooltip: '-1', onTap: () => _step(-1)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 104,
                    child: TextField(
                      controller: _qty,
                      textAlign: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      style: VfType.figureS.copyWith(
                        color: t.text,
                        fontSize: 17,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      decoration: vfInputDecoration(
                        context,
                        hintText: '0',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      ).copyWith(
                        labelText: 'inv.counted'.tr,
                        floatingLabelBehavior: FloatingLabelBehavior.never,
                      ),
                      onChanged: (v) {
                        widget.line.quantity = v;
                        widget.onChanged();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  _Stepper(icon: PhosphorIconsBold.plus, tooltip: '+1', onTap: () => _step(1)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: t.primarySoft,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.square(dimension: 46, child: Icon(icon, size: 18, color: t.primaryText)),
        ),
      ),
    );
  }
}

/// Save (and post) under the list, above the tab bar.
class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.busy,
    required this.error,
    required this.ready,
    required this.canPost,
    required this.onSave,
    required this.onPost,
  });

  final bool busy, ready, canPost;
  final String? error;
  final VoidCallback onSave, onPost;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.fromLTRB(VfSize.pagePad, 10, VfSize.pagePad, 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.isDark ? t.glassBorder : t.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(PhosphorIconsRegular.warningCircle, size: 16, color: t.dangerStrong),
                  const SizedBox(width: 6),
                  Expanded(child: Text(error!, style: VfType.small.copyWith(color: t.dangerStrong))),
                ],
              ),
            ),
          VouchFlowActions(
            reverseWhenStacked: false,
            children: [
              VouchFlowButton(
                label: 'inv.saveDraft'.tr,
                icon: PhosphorIconsRegular.floppyDisk,
                variant: canPost ? VfButtonVariant.secondary : VfButtonVariant.primary,
                loading: busy && !canPost,
                onPressed: busy || !ready ? null : onSave,
              ),
              if (canPost)
                VouchFlowButton(
                  label: 'inv.saveAndPost'.tr,
                  icon: PhosphorIconsRegular.checkCircle,
                  loading: busy,
                  onPressed: busy || !ready ? null : onPost,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
