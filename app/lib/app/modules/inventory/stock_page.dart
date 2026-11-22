import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/inventory_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;
import '../erp/erp_widgets.dart';
import 'inventory_widgets.dart';

/// Stock: what is held where (search, a warehouse filter, one row per
/// product, warehouse and batch) and what needs attention (low stock,
/// batches about to expire). The web's /erp/stock, its two phone-sized tabs.
class StockPage extends StatelessWidget {
  const StockPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'inventory',
    permission: 'inventory.view',
    builder: (_) => const _Stock(),
  );
}

class _Stock extends StatefulWidget {
  const _Stock();

  @override
  State<_Stock> createState() => _StockState();
}

class _StockState extends State<_Stock> {
  final _repo = InventoryRepository.to;
  int _tab = 0;

  List<ErpWarehouse> _warehouses = const [];
  int? _warehouse;
  String _q = '';
  Timer? _debounce;

  final _rows = <ErpStockBalance>[];
  int _page = 1;
  bool _more = false, _loading = true, _loadingMore = false;
  String? _error;
  int _generation = 0;

  StockAlerts? _alerts;
  String? _alertsError;

  @override
  void initState() {
    super.initState();
    _repo.warehouses().then((w) {
      if (mounted) setState(() => _warehouses = w);
    }).catchError((_) {});
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final generation = more ? _generation : ++_generation;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = _rows.isEmpty;
        _error = null;
      }
    });
    try {
      final page = await _repo.balances(
        q: _q.trim().isEmpty ? null : _q.trim(),
        warehouseId: _warehouse,
        page: more ? _page + 1 : 1,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        if (!more) _rows.clear();
        _rows.addAll(page.data);
        _page = page.currentPage;
        _more = page.hasMore;
      });
    } on ApiException catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _error = 'state.offline'.tr);
    } finally {
      if (mounted && generation == _generation) {
        setState(() { _loading = false; _loadingMore = false; });
      }
    }
  }

  Future<void> _loadAlerts() async {
    try {
      final a = await _repo.alerts();
      if (mounted) setState(() { _alerts = a; _alertsError = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _alertsError = e.message);
    } catch (_) {
      if (mounted) setState(() => _alertsError = 'state.offline'.tr);
    }
  }

  void _search(String v) {
    _q = v;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), _load);
  }

  void _openProduct(int id) => Get.toNamed(Routes.erpProduct, arguments: id);

  @override
  Widget build(BuildContext context) {
    final tabs = Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: VouchFlowTabs(
        labels: ['inv.balances'.tr, 'inv.alerts'.tr],
        icons: const [PhosphorIconsRegular.stack, PhosphorIconsRegular.bellRinging],
        current: _tab,
        onChanged: (i) {
          setState(() => _tab = i);
          if (i == 1 && _alerts == null) _loadAlerts();
        },
      ),
    );
    return ErpPageBody(
      onRefresh: () => _tab == 0 ? _load() : _loadAlerts(),
      children: [
        ErpPageTitle('inv.nav.stock'.tr),
        tabs,
        if (_tab == 0) ..._balances(context) else ..._alertsView(context),
      ],
    );
  }

  List<Widget> _balances(BuildContext context) {
    final currency = ErpService.to.currency;
    return [
      VouchFlowSearchField(placeholder: 'inv.searchStock'.tr, onChanged: _search),
      const SizedBox(height: 10),
      if (_warehouses.length > 1) ...[
        WarehouseFilter(
          warehouses: _warehouses,
          selected: _warehouse,
          onChanged: (id) {
            setState(() => _warehouse = id);
            _load();
          },
        ),
        const SizedBox(height: 14),
      ],
      if (_loading)
        const VfLoadingView(inline: true)
      else if (_error != null && _rows.isEmpty)
        VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)
      else if (_rows.isEmpty)
        VouchFlowEmptyState(icon: PhosphorIconsRegular.stack, title: 'inv.noBalances'.tr)
      else
        VouchFlowPanel(
          padded: false,
          child: Column(
            children: [
              for (var i = 0; i < _rows.length; i++)
                _BalanceRow(
                  balance: _rows[i],
                  divider: i > 0,
                  showWarehouse: _warehouse == null,
                  currency: currency,
                  onTap: () => _openProduct(_rows[i].productId),
                ),
              if (_more)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: _loadingMore
                      ? const VfLoader(size: 28)
                      : VouchFlowButton(
                          label: 'erp.loadMore'.tr,
                          variant: VfButtonVariant.ghost,
                          compact: true,
                          onPressed: () => _load(more: true),
                        ),
                ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _alertsView(BuildContext context) {
    final t = context.vf;
    final a = _alerts;
    if (_alertsError != null && a == null) {
      return [VouchFlowErrorState(message: _alertsError!, onRetry: _loadAlerts, retryLabel: 'action.retry'.tr)];
    }
    if (a == null) return const [VfLoadingView(inline: true)];
    if (a.lowStock.isEmpty && a.expiring.isEmpty) {
      return [VouchFlowEmptyState(icon: PhosphorIconsRegular.checkCircle, title: 'inv.noAlerts'.tr)];
    }
    return [
      VouchFlowPanel(
        title: 'inv.belowReorder'.tr,
        trailing: _Count(a.lowStock.length),
        padded: false,
        child: a.lowStock.isEmpty
            ? _quiet(context, 'inv.noAlerts'.tr)
            : Column(
                children: [
                  for (var i = 0; i < a.lowStock.length; i++)
                    VouchFlowListRow(
                      divider: i > 0,
                      icon: PhosphorIconsRegular.warning,
                      iconColor: t.warningStrong,
                      title: a.lowStock[i].name,
                      subtitle: '${a.lowStock[i].sku} · ${'inv.reorderAt'.trParams({'n': ErpFmt.qty(a.lowStock[i].reorderLevel)})}',
                      trailing: QtyText(a.lowStock[i].onHand ?? 0, unit: a.lowStock[i].unitCode),
                      onTap: () => _openProduct(a.lowStock[i].id),
                    ),
                ],
              ),
      ),
      erpGap,
      VouchFlowPanel(
        title: 'inv.expiringIn'.trParams({'n': '${a.windowDays}'}),
        trailing: _Count(a.expiring.length),
        padded: false,
        child: a.expiring.isEmpty
            ? _quiet(context, 'inv.noAlerts'.tr)
            : Column(
                children: [
                  for (var i = 0; i < a.expiring.length; i++)
                    VouchFlowListRow(
                      divider: i > 0,
                      icon: PhosphorIconsRegular.hourglassMedium,
                      iconColor: a.expiring[i].expired ? t.dangerStrong : t.warningStrong,
                      title: a.expiring[i].productName ?? '',
                      subtitle: [
                        a.expiring[i].batchNumber,
                        a.expiring[i].warehouse?.name ?? '',
                        ErpFmt.qty(a.expiring[i].quantity),
                      ].where((s) => s.isNotEmpty).join(' · '),
                      trailing: VouchFlowStatusBadge(
                        label: a.expiring[i].expired ? 'inv.expired'.tr : dashDate(a.expiring[i].expiryDate),
                        tag: a.expiring[i].expired ? 'tag-accent-2' : 'tag-warn',
                      ),
                      onTap: () => _openProduct(a.expiring[i].productId),
                    ),
                ],
              ),
      ),
    ];
  }

  Widget _quiet(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.all(20),
    child: Text(text, textAlign: TextAlign.center, style: VfType.small.copyWith(color: context.vf.muted)),
  );
}

class _Count extends StatelessWidget {
  const _Count(this.n);
  final int n;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(color: t.primarySoft, borderRadius: BorderRadius.circular(VfSize.radiusPill)),
      child: Text('$n', style: VfType.meta.copyWith(color: t.primaryText, fontWeight: FontWeight.w600)),
    );
  }
}

/// One balance: the product, where and which batch, the quantity and value.
class _BalanceRow extends StatelessWidget {
  const _BalanceRow({
    required this.balance,
    required this.divider,
    required this.showWarehouse,
    required this.currency,
    required this.onTap,
  });

  final ErpStockBalance balance;
  final bool divider, showWarehouse;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final b = balance;
    final low = (b.reorderLevel ?? 0) > 0 && b.quantity <= b.reorderLevel!;
    final where = [
      b.productSku ?? '',
      if (showWarehouse) b.warehouse?.name ?? '',
      if (b.batchNumber.isNotEmpty) b.batchNumber,
      if (b.expiryDate != null) 'inv.expiresOn'.trParams({'date': dashDate(b.expiryDate)}),
    ].where((s) => s.isNotEmpty).join(' · ');
    return VouchFlowListRow(
      divider: divider,
      icon: PhosphorIconsRegular.package,
      iconColor: low ? t.warningStrong : null,
      title: b.productName ?? '',
      subtitle: where,
      onTap: onTap,
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          QtyText(b.quantity, unit: b.unitCode),
          const SizedBox(height: 2),
          Text(
            ErpFmt.compactMoney(b.value ?? 0, currency),
            style: VfType.meta.copyWith(color: t.muted, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}
