import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/models/erp_models.dart' show ErpPage;
import '../../data/services/api_service.dart';
import '../../widgets/vf/vf.dart';
import '../erp/erp_widgets.dart';
import 'fleet_widgets.dart';

/// Loads one page of a list for a search, a status filter and a page number.
typedef PageLoader<T> = Future<ErpPage<T>> Function(String? q, String? status, int page);

/// A list page of the Fleet and HR apps: a title, an optional search, status
/// pills, then the rows in a panel with "Show more" (the pattern of the
/// Inventory documents list, shared so every list behaves the same).
class PagedListBody<T> extends StatefulWidget {
  const PagedListBody({
    super.key,
    required this.title,
    required this.load,
    required this.row,
    required this.emptyText,
    this.subtitle,
    this.trailing,
    this.searchPlaceholder,
    this.statuses,
    this.statusLabel,
    this.initialStatus,
    this.emptyIcon = PhosphorIconsRegular.tray,
    this.header,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final String? searchPlaceholder;
  final List<String?>? statuses;
  final String Function(String?)? statusLabel;
  final String? initialStatus;
  final PageLoader<T> load;

  /// One row; [reload] refreshes the list after something changed.
  final Widget Function(BuildContext context, T item, int index, VoidCallback reload) row;
  final String emptyText;
  final IconData emptyIcon;

  /// Something between the filters and the list.
  final Widget? header;

  @override
  State<PagedListBody<T>> createState() => _PagedListBodyState<T>();
}

class _PagedListBodyState<T> extends State<PagedListBody<T>> {
  late String? _status = widget.initialStatus;
  String _q = '';
  Timer? _debounce;

  final _rows = <T>[];
  int _page = 1;
  bool _more = false, _loading = true, _loadingMore = false;
  String? _error;
  int _generation = 0;

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
      final page = await widget.load(_q.trim().isEmpty ? null : _q.trim(), _status, more ? _page + 1 : 1);
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
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _search(String v) {
    _q = v;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), _load);
  }

  @override
  Widget build(BuildContext context) {
    return ErpPageBody(
      onRefresh: _load,
      children: [
        ErpPageTitle(widget.title, subtitle: widget.subtitle, trailing: widget.trailing),
        if (widget.searchPlaceholder != null) ...[
          VouchFlowSearchField(placeholder: widget.searchPlaceholder!, onChanged: _search),
          const SizedBox(height: 10),
        ],
        if (widget.statuses != null) ...[
          StatusFilter(
            values: widget.statuses!,
            selected: _status,
            label: widget.statusLabel ?? (s) => s ?? '',
            onChanged: (v) {
              setState(() => _status = v);
              _load();
            },
          ),
          const SizedBox(height: 14),
        ],
        ?widget.header,
        if (_loading)
          const VfLoadingView(inline: true)
        else if (_error != null && _rows.isEmpty)
          VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)
        else if (_rows.isEmpty)
          VouchFlowEmptyState(icon: widget.emptyIcon, title: widget.emptyText)
        else
          VouchFlowPanel(
            padded: false,
            child: Column(
              children: [
                for (var i = 0; i < _rows.length; i++) widget.row(context, _rows[i], i, _load),
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
