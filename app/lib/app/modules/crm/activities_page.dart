import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/models/ops_models.dart';
import '../../data/services/crm_repository.dart';
import '../../data/services/erp_service.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../erp/erp_widgets.dart';
import '../erp/ops_kit.dart';
import 'crm_widgets.dart';

/// Follow-ups (the web's /erp/crm/activities): open ones by due time by
/// default, with today, overdue and done a tap away; a round check marks
/// one done with its outcome.
class CrmActivitiesPage extends StatelessWidget {
  const CrmActivitiesPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(module: 'crm', permission: 'crm.view', builder: (_) => const _Activities());
}

class _Activities extends StatefulWidget {
  const _Activities();

  @override
  State<_Activities> createState() => _ActivitiesState();
}

class _ActivitiesState extends State<_Activities> {
  final _repo = CrmRepository.to;
  String _status = 'open';
  String? _type;

  final _rows = <CrmActivity>[];
  int _page = 1;
  bool _more = false, _loading = true, _loadingMore = false;
  String? _error;
  int _generation = 0;

  static const _statuses = ['open', 'today', 'overdue', 'done'];

  @override
  void initState() {
    super.initState();
    _load();
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
      final page = await _repo.activities(status: _status, type: _type, page: more ? _page + 1 : 1);
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

  Future<void> _open(CrmActivity a) async {
    if (a.opportunityId != null) {
      await Get.toNamed(Routes.crmOpportunity, arguments: a.opportunityId);
    } else if (a.leadId != null) {
      await Get.toNamed(Routes.crmLead, arguments: a.leadId);
    } else {
      return;
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final manage = ErpService.to.can('crm.manage');
    return ErpPageBody(
      onRefresh: _load,
      children: [
        ErpPageTitle(
          'crm.nav.activities'.tr,
          subtitle: 'crm.activitiesSub'.tr,
          trailing: manage
              ? VouchFlowButton(
                  label: 'crm.log'.tr,
                  icon: PhosphorIconsBold.plus,
                  compact: true,
                  onPressed: () async {
                    await Get.toNamed(Routes.crmActivityNew);
                    _load();
                  },
                )
              : null,
        ),
        OpsChips<String>(
          values: _statuses,
          selected: _status,
          label: (s) => 'crm.filter.$s'.tr,
          onChanged: (s) {
            setState(() => _status = s);
            _load();
          },
        ),
        const SizedBox(height: 8),
        OpsChips<String?>(
          values: const [null, ...CrmActivityType.all],
          selected: _type,
          label: (s) => s == null ? 'crm.allTypes'.tr : crmActivityLabel(s),
          onChanged: (s) {
            setState(() => _type = s);
            _load();
          },
        ),
        const SizedBox(height: 14),
        if (_loading)
          const VfLoadingView(inline: true)
        else if (_error != null && _rows.isEmpty)
          VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)
        else if (_rows.isEmpty)
          VouchFlowEmptyState(icon: PhosphorIconsRegular.calendarCheck, title: 'crm.noActivities'.tr)
        else
          VouchFlowPanel(
            padded: false,
            child: Column(
              children: [
                for (var i = 0; i < _rows.length; i++)
                  CrmActivityRow(
                    activity: _rows[i],
                    divider: i > 0,
                    onTap: () => _open(_rows[i]),
                    onDone: manage
                        ? () async {
                            if (await crmComplete(context, _rows[i])) _load();
                          }
                        : null,
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
