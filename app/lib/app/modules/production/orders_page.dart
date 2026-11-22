import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/models/ops_models.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/production_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../erp/erp_widgets.dart';
import '../erp/ops_kit.dart';
import 'production_app.dart';
import 'production_widgets.dart';

/// Every production order, open ones first by default, searchable by
/// number, reference or product (the web's /erp/production/orders).
class ProductionOrdersPage extends StatelessWidget {
  const ProductionOrdersPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'production',
    permission: 'production.view',
    builder: (_) => const _Orders(),
  );
}

class _Orders extends StatefulWidget {
  const _Orders();

  @override
  State<_Orders> createState() => _OrdersState();
}

class _OrdersState extends State<_Orders> {
  final _repo = ProductionRepository.to;
  String _status = 'open';
  String _q = '';
  Timer? _debounce;

  final _rows = <ProductionOrder>[];
  int _page = 1;
  bool _more = false, _loading = true, _loadingMore = false;
  String? _error;
  int _generation = 0;

  static const _statuses = ['open', ...PrdStatus.all, 'all'];

  @override
  void initState() {
    super.initState();
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
      final page = await _repo.orders(
        status: _status == 'all' ? null : _status,
        q: _q.trim().isEmpty ? null : _q.trim(),
        page: more ? _page + 1 : 1,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        if (!more) _rows.clear();
        _rows.addAll(page.data);
        _page = page.currentPage;
        _more = page.hasMore;
      });
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = opsError(e));
    } finally {
      if (mounted && generation == _generation) setState(() { _loading = false; _loadingMore = false; });
    }
  }

  void _search(String v) {
    _q = v;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), _load);
  }

  Future<void> _open(int id) async {
    await Get.toNamed(Routes.prdOrder, arguments: id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final mayPlan = ErpService.to.can('production.plan');
    return ErpPageBody(
      onRefresh: _load,
      children: [
        ErpPageTitle(
          'prd.nav.orders'.tr,
          trailing: mayPlan
              ? VouchFlowButton(
                  label: 'prd.plan'.tr,
                  icon: PhosphorIconsBold.plus,
                  compact: true,
                  onPressed: () async {
                    await erpCreate(productionCreateActions.first);
                    _load();
                  },
                )
              : null,
        ),
        VouchFlowSearchField(placeholder: 'prd.searchOrders'.tr, onChanged: _search),
        const SizedBox(height: 10),
        OpsChips<String>(
          values: _statuses,
          selected: _status,
          label: (s) => switch (s) {
            'open' => 'prd.open'.tr,
            'all' => 'inv.all'.tr,
            _ => prdStatusLabel(s),
          },
          onChanged: (s) {
            setState(() => _status = s);
            _load();
          },
        ),
        const SizedBox(height: 14),
        if (_loading)
          const VfLoadingView(inline: true)
        else if (_error != null && _rows.isEmpty)
          VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)
        else if (_rows.isEmpty)
          VouchFlowEmptyState(icon: PhosphorIconsRegular.factory, title: 'prd.noOrders'.tr)
        else
          VouchFlowPanel(
            padded: false,
            child: Column(
              children: [
                for (var i = 0; i < _rows.length; i++)
                  PrdOrderRow(order: _rows[i], divider: i > 0, onTap: () => _open(_rows[i].id)),
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
        const SizedBox(height: 8),
      ],
    );
  }
}
