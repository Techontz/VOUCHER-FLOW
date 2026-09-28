import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/admin_models.dart';
import '../../data/services/admin_repository.dart';
import '../../widgets/common.dart' show Fmt;
import '../../widgets/vf/vf.dart';
import 'admin_widgets.dart';

/// Audit logs — the web's page: who did what, when and from which device,
/// searchable by text, action and date range. Append-only; nothing here
/// changes anything. A super admin sees every company (each entry names it).
class AuditPage extends StatefulWidget {
  const AuditPage({super.key, this.repository});

  final AdminRepository? repository;

  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  late final AdminRepository _repo = widget.repository ?? AdminRepository.to;
  static final _iso = DateFormat('yyyy-MM-dd');

  int _page = 1;
  String _q = '', _action = '';
  DateTime? _from, _to;
  Paginated<AuditEntry>? _result;
  List<String> _actions = const [];
  String? _error;
  Timer? _debounce;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _repo.auditActions().then((a) {
      if (mounted) setState(() => _actions = a);
    }, onError: (_) {});
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() => _error = null);
    try {
      final r = await _repo.audit(
        q: _q,
        action: _action,
        from: _from == null ? '' : _iso.format(_from!),
        to: _to == null ? '' : _iso.format(_to!),
        page: _page,
      );
      if (mounted && seq == _seq) setState(() => _result = r);
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _error = adminErrorText(e));
    }
  }

  void _search(String q) {
    _q = q;
    _page = 1;
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: q.isEmpty ? 0 : 260), _load);
  }

  Future<void> _pickDate(bool from) async {
    final now = DateTime.now();
    final current = from ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() {
      if (from) {
        _from = picked;
      } else {
        _to = picked;
      }
      _page = 1;
    });
    _load();
  }

  void _clearDate(bool from) {
    setState(() {
      if (from) {
        _from = null;
      } else {
        _to = null;
      }
      _page = 1;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final rows = _result?.data ?? const <AuditEntry>[];

    return AdminPageBody(
      route: '/audit',
      title: 'admin.auditLogs'.tr,
      subtitle: 'admin.auditSub'.tr,
      onRefresh: _load,
      children: [
        VouchFlowCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              VouchFlowSearchField(
                placeholder: 'admin.search'.tr,
                onChanged: _search,
              ),
              const SizedBox(height: 10),
              Semantics(
                label: 'admin.actions'.tr,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('action|${_actions.length}'),
                  initialValue: _action,
                  isExpanded: true,
                  icon: Icon(
                    PhosphorIconsRegular.caretDown,
                    size: 16,
                    color: t.muted,
                  ),
                  dropdownColor: t.surface,
                  borderRadius: BorderRadius.circular(VfSize.radiusL),
                  style: VfType.body.copyWith(color: t.text),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: t.inputBg,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text('admin.allActions'.tr),
                    ),
                    for (final a in _actions)
                      DropdownMenuItem(
                        value: a,
                        child: Text(
                          a,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _action = v ?? '';
                      _page = 1;
                    });
                    _load();
                  },
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _DateButton(
                      label: 'admin.from'.tr,
                      value: _from,
                      onTap: () => _pickDate(true),
                      onClear: () => _clearDate(true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DateButton(
                      label: 'admin.to'.tr,
                      value: _to,
                      onTap: () => _pickDate(false),
                      onClear: () => _clearDate(false),
                    ),
                  ),
                ],
              ),
              if (_result != null) ...[
                const SizedBox(height: 10),
                Text(
                  '${_result!.total}',
                  style: VfType.small.copyWith(
                    color: t.muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_error != null)
          VouchFlowErrorState(
            message: _error!,
            onRetry: _load,
            retryLabel: 'action.retry'.tr,
          )
        else if (_result == null)
          const VouchFlowLoadingState(rows: 6, rowHeight: 120)
        else if (rows.isEmpty)
          VouchFlowCard(
            child: VouchFlowEmptyState(
              icon: PhosphorIconsRegular.scroll,
              title: 'admin.noResults'.tr,
            ),
          )
        else ...[
          for (final row in rows) ...[
            _AuditCard(row: row),
            const SizedBox(height: 10),
          ],
          AdminPagination(
            page: _result!.page,
            lastPage: _result!.lastPage,
            total: _result!.total,
            onChange: (p) {
              setState(() => _page = p);
              _load();
            },
          ),
        ],
      ],
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap, onClear;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: t.inputBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VfSize.radiusL),
          side: BorderSide(color: t.inputBorder),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(VfSize.radiusL),
          onTap: onTap,
          child: Container(
            height: VfSize.inputH,
            padding: const EdgeInsets.only(left: 12, right: 4),
            child: Row(
              children: [
                Icon(
                  PhosphorIconsRegular.calendarBlank,
                  size: 17,
                  color: t.faint,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    value == null ? label : Fmt.date(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VfType.body.copyWith(
                      color: value == null ? t.placeholder : t.text,
                    ),
                  ),
                ),
                if (value != null)
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).deleteButtonTooltip,
                    icon: Icon(
                      PhosphorIconsRegular.x,
                      size: 15,
                      color: t.muted,
                    ),
                    onPressed: onClear,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AuditCard extends StatelessWidget {
  const _AuditCard({required this.row});
  final AuditEntry row;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return VouchFlowCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminPerson(
            initials: row.actorInitials,
            name: row.actorName,
            sub: row.company,
          ),
          const SizedBox(height: 10),
          Text(row.description, style: VfType.body.copyWith(color: t.text)),
          if ((row.changeSummary ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              row.changeSummary!,
              style: VfType.small.copyWith(color: t.muted, fontSize: 13),
            ),
          ],
          const SizedBox(height: 8),
          AdminLine(label: 'admin.date'.tr, value: Fmt.dateTime(row.createdAt)),
          if (row.device.isNotEmpty)
            AdminLine(label: 'admin.device'.tr, value: row.device),
        ],
      ),
    );
  }
}
