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

/// Audit logs: who did what, when and from which device — a row per entry,
/// its details in a sheet, searchable by text, action and date range. Append-only; nothing here
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

  Future<void> _pickAction() async {
    final v = await showAdminOptions<String>(
      context,
      title: 'admin.actions'.tr,
      selected: _action,
      options: [('', 'admin.allActions'.tr), for (final a in _actions) (a, a)],
    );
    if (v == null || v == _action) return;
    setState(() {
      _action = v;
      _page = 1;
    });
    _load();
  }

  void _openEntry(AuditEntry row) {
    final t = context.vf;
    showAdminItemSheet(
      context,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminPerson(
            initials: row.actorInitials,
            name: row.actorName,
            sub: row.company,
            size: 52,
          ),
          const SizedBox(height: 16),
          Text(row.description, style: VfType.body.copyWith(color: t.text)),
          if ((row.changeSummary ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              row.changeSummary!,
              style: VfType.small.copyWith(color: t.muted),
            ),
          ],
        ],
      ),
      details: [
        AdminLine(label: 'admin.date'.tr, value: Fmt.dateTime(row.createdAt)),
        if (row.device.isNotEmpty)
          AdminLine(label: 'admin.device'.tr, value: row.device),
      ],
    );
  }

  static String _when(DateTime? at) {
    if (at == null) return '';
    return DateTime.now().difference(at).inDays < 7
        ? Fmt.relative(at)
        : DateFormat('d MMM').format(at);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final rows = _result?.data ?? const <AuditEntry>[];

    return AdminPageBody(
      route: '/audit',
      title: 'admin.auditLogs'.tr,
      onRefresh: _load,
      children: [
        AdminSearchField(placeholder: 'admin.search'.tr, onChanged: _search),
        const SizedBox(height: 12),
        AdminChipRail(
          children: [
            AdminSelectChip(
              icon: PhosphorIconsRegular.lightning,
              label: _action.isEmpty ? 'admin.allActions'.tr : _action,
              active: _action.isNotEmpty,
              onTap: _pickAction,
              onClear: () {
                setState(() {
                  _action = '';
                  _page = 1;
                });
                _load();
              },
            ),
            AdminSelectChip(
              icon: PhosphorIconsRegular.calendarBlank,
              label: _from == null ? 'admin.from'.tr : Fmt.date(_from),
              active: _from != null,
              onTap: () => _pickDate(true),
              onClear: () => _clearDate(true),
            ),
            AdminSelectChip(
              icon: PhosphorIconsRegular.calendarBlank,
              label: _to == null ? 'admin.to'.tr : Fmt.date(_to),
              active: _to != null,
              onTap: () => _pickDate(false),
              onClear: () => _clearDate(false),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_error != null)
          VouchFlowErrorState(
            message: _error!,
            onRetry: _load,
            retryLabel: 'action.retry'.tr,
          )
        else if (_result == null)
          const VouchFlowLoadingState(rows: 6, rowHeight: 72)
        else if (rows.isEmpty)
          VouchFlowCard(
            radius: VfSize.radiusXl,
            child: VouchFlowEmptyState(
              icon: PhosphorIconsRegular.scroll,
              title: 'admin.noResults'.tr,
            ),
          )
        else ...[
          for (final row in rows)
            AdminListRow(
              semanticLabel: '${row.actorName}: ${row.description}',
              leading: VouchFlowAvatar(
                initials: row.actorInitials.isEmpty ? '?' : row.actorInitials,
                size: 44,
              ),
              title: row.actorName,
              meta: row.description,
              trailing: Text(
                _when(row.createdAt),
                style: VfType.meta.copyWith(
                  color: t.faint,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              onTap: () => _openEntry(row),
            ),
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
