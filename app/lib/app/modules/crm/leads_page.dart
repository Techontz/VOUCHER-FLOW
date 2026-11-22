import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/ops_models.dart';
import '../../data/services/crm_repository.dart';
import '../../data/services/erp_service.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../erp/erp_widgets.dart';
import '../erp/ops_kit.dart';
import 'crm_widgets.dart';

/// The leads (the web's /erp/crm/leads): searchable by name, business,
/// number, phone or email, filtered by status, newest first.
class CrmLeadsPage extends StatelessWidget {
  const CrmLeadsPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(module: 'crm', permission: 'crm.view', builder: (_) => const _Leads());
}

class _Leads extends StatefulWidget {
  const _Leads();

  @override
  State<_Leads> createState() => _LeadsState();
}

class _LeadsState extends State<_Leads> {
  final _repo = CrmRepository.to;
  String? _status;
  String _q = '';
  Timer? _debounce;

  final _rows = <CrmLead>[];
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
      final page = await _repo.leads(status: _status, q: _q.trim().isEmpty ? null : _q.trim(), page: more ? _page + 1 : 1);
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
    await Get.toNamed(Routes.crmLead, arguments: id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return ErpPageBody(
      onRefresh: _load,
      children: [
        ErpPageTitle(
          'crm.nav.leads'.tr,
          trailing: ErpService.to.can('crm.manage')
              ? VouchFlowButton(
                  label: 'crm.newLead'.tr,
                  icon: PhosphorIconsBold.plus,
                  compact: true,
                  onPressed: () async {
                    final id = await Get.toNamed(Routes.crmLeadNew);
                    if (id is int) {
                      _open(id);
                    } else {
                      _load();
                    }
                  },
                )
              : null,
        ),
        VouchFlowSearchField(placeholder: 'crm.searchLeads'.tr, onChanged: _search),
        const SizedBox(height: 10),
        OpsChips<String?>(
          values: const [null, ...CrmLeadStatus.all],
          selected: _status,
          label: (s) => s == null ? 'inv.all'.tr : crmLeadStatusLabel(s),
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
          VouchFlowEmptyState(icon: PhosphorIconsRegular.userFocus, title: 'crm.noLeads'.tr)
        else
          VouchFlowPanel(
            padded: false,
            child: Column(
              children: [
                for (var i = 0; i < _rows.length; i++)
                  VouchFlowListRow(
                    divider: i > 0,
                    icon: PhosphorIconsRegular.userFocus,
                    iconColor: crmLeadTone(_rows[i].status).colors(t).$1,
                    title: _rows[i].contactName,
                    subtitle: [
                      ?_rows[i].companyName,
                      ?_rows[i].region,
                      if (_rows[i].estimatedValue > 0) crmMoney(_rows[i].estimatedValue),
                    ].join(' · '),
                    trailing: OpsBadge(crmLeadStatusLabel(_rows[i].status), tone: crmLeadTone(_rows[i].status)),
                    onTap: () => _open(_rows[i].id),
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
