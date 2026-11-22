import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/models/ops_models.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/production_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart' show showToast;
import '../../widgets/vf/vf.dart';
import '../erp/erp_widgets.dart';
import '../erp/ops_kit.dart';
import 'order_page.dart' show PrdReceiptRow;
import 'production_widgets.dart';

/// The quality-control queue (the web's /erp/production/qc): output
/// waiting for its check, oldest first, and the checks already made. An
/// inspector opens a waiting receipt and releases or rejects it here.
class QcQueuePage extends StatelessWidget {
  const QcQueuePage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'production',
    permission: 'production.view',
    builder: (_) => const _Queue(),
  );
}

class _Queue extends StatefulWidget {
  const _Queue();

  @override
  State<_Queue> createState() => _QueueState();
}

class _QueueState extends State<_Queue> {
  final _repo = ProductionRepository.to;
  String _status = PrdReceiptStatus.pending;
  String _q = '';
  Timer? _debounce;

  final _rows = <PrdReceipt>[];
  int _page = 1;
  bool _more = false, _loading = true, _loadingMore = false;
  String? _error;
  int _generation = 0;

  static const _statuses = [PrdReceiptStatus.pending, PrdReceiptStatus.released, PrdReceiptStatus.rejected, 'all'];

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
      final page = await _repo.qc(status: _status, q: _q.trim().isEmpty ? null : _q.trim(), page: more ? _page + 1 : 1);
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

  Future<void> _inspect(PrdReceipt r) async {
    final message = await showQcSheet(context, r);
    if (message == null) return;
    showToast(message.isEmpty ? 'prd.rcpt.released'.tr : message);
    _load();
  }

  Future<void> _open(PrdReceipt r) async {
    if (r.orderId == null) return;
    await Get.toNamed(Routes.prdOrder, arguments: r.orderId);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final canQc = ErpService.to.can('production.qc');
    return ErpPageBody(
      onRefresh: _load,
      children: [
        ErpPageTitle('prd.nav.qc'.tr, subtitle: 'prd.qcQueueSub'.tr),
        VouchFlowSearchField(placeholder: 'prd.searchReceipts'.tr, onChanged: _search),
        const SizedBox(height: 10),
        OpsChips<String>(
          values: _statuses,
          selected: _status,
          label: (s) => s == 'all' ? 'inv.all'.tr : prdReceiptLabel(s),
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
          VouchFlowEmptyState(
            icon: PhosphorIconsRegular.sealCheck,
            title: _status == PrdReceiptStatus.pending ? 'prd.qcClear'.tr : 'prd.noReceipts'.tr,
          )
        else
          VouchFlowPanel(
            padded: false,
            child: Column(
              children: [
                for (var i = 0; i < _rows.length; i++)
                  PrdReceiptRow(
                    receipt: _rows[i],
                    divider: i > 0,
                    showOrder: true,
                    onTap: () => _open(_rows[i]),
                    onInspect: _rows[i].isPending && canQc ? () => _inspect(_rows[i]) : null,
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
        const SizedBox(height: 8),
      ],
    );
  }
}
