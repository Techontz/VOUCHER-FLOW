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
import '../erp/erp_widgets.dart';
import '../shell/app_registry.dart';
import 'inventory_app.dart';
import 'inventory_widgets.dart';

/// Every stock document, newest first, filtered by status and type and
/// searchable by number or reference (the web's /erp/documents).
class DocumentsPage extends StatelessWidget {
  const DocumentsPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'inventory',
    permission: 'inventory.view',
    builder: (_) => const _Documents(),
  );
}

class _Documents extends StatefulWidget {
  const _Documents();

  @override
  State<_Documents> createState() => _DocumentsState();
}

class _DocumentsState extends State<_Documents> {
  final _repo = InventoryRepository.to;
  String? _status;
  String? _type;
  String _q = '';
  Timer? _debounce;

  final _rows = <ErpStockDocument>[];
  int _page = 1;
  bool _more = false, _loading = true, _loadingMore = false;
  String? _error;
  int _generation = 0;

  static const _statuses = [null, ErpDocStatus.draft, ErpDocStatus.posted, ErpDocStatus.reversed];

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
      final page = await _repo.documents(
        type: _type,
        status: _status,
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
    } on ApiException catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _error = 'state.offline'.tr);
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
    await Get.toNamed(Routes.erpDocument, arguments: id);
    _load();
  }

  Future<void> _new() async {
    final erp = ErpService.to;
    final actions = inventoryCreateActions.where((a) => a.permission == null || erp.can(a.permission!)).toList();
    final chosen = await showVouchFlowBottomSheet<VfCreateAction>(
      context,
      title: 'inv.newDocument'.tr,
      child: Column(
        children: [
          for (var i = 0; i < actions.length; i++)
            Builder(
              builder: (ctx) => VouchFlowListRow(
                divider: i > 0,
                icon: actions[i].icon,
                title: actions[i].label.tr,
                subtitle: actions[i].hint?.tr,
                onTap: () => Navigator.of(ctx).pop(actions[i]),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
    if (chosen == null) return;
    await erpCreate(chosen);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final erp = ErpService.to;
    final canPrepare = inventoryCreateActions.any((a) => a.permission == null || erp.can(a.permission!));
    return ErpPageBody(
      onRefresh: _load,
      children: [
        ErpPageTitle(
          'inv.documents'.tr,
          trailing: canPrepare
              ? VouchFlowButton(
                  label: 'inv.newDocument'.tr,
                  icon: PhosphorIconsBold.plus,
                  compact: true,
                  onPressed: _new,
                )
              : null,
        ),
        VouchFlowSearchField(placeholder: 'inv.searchDocuments'.tr, onChanged: _search),
        const SizedBox(height: 10),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final s in _statuses) ...[
                VouchFlowFilterChip(
                  label: s == null ? 'inv.all'.tr : docStatusLabel(s),
                  selected: _status == s,
                  onTap: () {
                    setState(() => _status = s);
                    _load();
                  },
                ),
                const SizedBox(width: 8),
              ],
              _TypeMenu(
                value: _type,
                onChanged: (v) {
                  setState(() => _type = v);
                  _load();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_loading)
          const VfLoadingView(inline: true)
        else if (_error != null && _rows.isEmpty)
          VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)
        else if (_rows.isEmpty)
          VouchFlowEmptyState(icon: PhosphorIconsRegular.tray, title: 'inv.noDocuments'.tr)
        else
          VouchFlowPanel(
            padded: false,
            child: Column(
              children: [
                for (var i = 0; i < _rows.length; i++)
                  DocumentRow(doc: _rows[i], divider: i > 0, onTap: () => _open(_rows[i].id)),
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

/// "All types ▾": the document type filter, as a pill beside the statuses.
class _TypeMenu extends StatelessWidget {
  const _TypeMenu({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final selected = value != null;
    return PopupMenuButton<String>(
      tooltip: 'inv.type'.tr,
      position: PopupMenuPosition.under,
      onSelected: (v) => onChanged(v.isEmpty ? null : v),
      itemBuilder: (_) => [
        PopupMenuItem(value: '', child: Text('inv.allTypes'.tr)),
        for (final type in ErpDocType.all)
          PopupMenuItem(
            value: type,
            child: Row(
              children: [
                Icon(docTypeIcon(type), size: 18, color: docTypeTint(t, type)),
                const SizedBox(width: 10),
                Text(docTypeLabel(type)),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: ShapeDecoration(
          color: selected ? t.primarySoftStrong : t.glassFillStrong,
          shape: StadiumBorder(side: BorderSide(color: selected ? t.primaryBorder : (t.isDark ? t.glassBorder : t.border))),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selected ? docTypeLabel(value!) : 'inv.allTypes'.tr,
              style: VfType.label.copyWith(fontSize: 14.5, color: selected ? t.primaryText : t.text2),
            ),
            const SizedBox(width: 6),
            Icon(PhosphorIconsBold.caretDown, size: 12, color: selected ? t.primaryText : t.muted),
          ],
        ),
      ),
    );
  }
}
