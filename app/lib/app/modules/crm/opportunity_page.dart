import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/ops_models.dart';
import '../../data/services/crm_repository.dart';
import '../../data/services/erp_service.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate, dashDateTime;
import '../erp/erp_widgets.dart';
import '../erp/ops_kit.dart';
import '../inventory/inventory_widgets.dart' show ErpFact;
import 'crm_widgets.dart';
import 'lead_page.dart' show CrmContactButtons;

/// One deal (the web's /erp/crm/opportunities/[id]): value, stage and
/// probability, the customer, its activities and history. Move it to
/// another stage or log an activity from the foot bar. Opened with its id.
class CrmOpportunityPage extends StatefulWidget {
  const CrmOpportunityPage({super.key, this.opportunityId});

  final int? opportunityId;

  @override
  State<CrmOpportunityPage> createState() => _CrmOpportunityPageState();
}

class _CrmOpportunityPageState extends State<CrmOpportunityPage> {
  late final int _id = widget.opportunityId ?? (Get.arguments as int);
  CrmOpportunity? _deal;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await CrmRepository.to.opportunity(_id);
      if (mounted) setState(() { _deal = d; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = opsError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _deal;
    final manage = ErpService.to.can('crm.manage');
    return VouchFlowPushedScaffold(
      title: d?.number ?? 'crm.opportunity'.tr,
      body: d == null
          ? (_error == null
                ? const VfLoadingView()
                : ErpPageBody(children: [VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)]))
          : _body(context, d, manage),
      bottomBar: d == null || !manage
          ? null
          : OpsActionBar(
              children: [
                VouchFlowButton(
                  label: 'crm.moveTo'.tr,
                  icon: PhosphorIconsRegular.arrowsDownUp,
                  variant: VfButtonVariant.secondary,
                  onPressed: () async {
                    if (await crmMoveStage(context, d)) _load();
                  },
                ),
                VouchFlowButton(
                  label: 'crm.log'.tr,
                  icon: PhosphorIconsRegular.phoneCall,
                  onPressed: () async {
                    await Get.toNamed(Routes.crmActivityNew, arguments: {'opportunity': d.id, 'customer': d.customerId, 'name': d.title});
                    _load();
                  },
                ),
              ],
            ),
    );
  }

  Widget _body(BuildContext context, CrmOpportunity d, bool manage) {
    final t = context.vf;
    return ErpPageBody(
      onRefresh: _load,
      children: [
        OpsHead(
          icon: PhosphorIconsRegular.handshake,
          tint: crmStageTone(d.stage).colors(t).$1,
          kicker: d.number,
          title: d.title,
          subtitle: [crmMoney(d.value, compact: false), '${d.probability}%', ?d.customer].join(' · '),
          badge: OpsBadge(crmStageLabel(d.stage), tone: crmStageTone(d.stage), large: true),
        ),
        CrmContactButtons(phone: d.customerPhone, email: d.customerEmail),
        VouchFlowPanel(
          title: 'crm.details'.tr,
          child: Column(
            children: [
              ErpFact('crm.value'.tr, crmMoney(d.value, compact: false)),
              ErpFact('crm.weighted'.tr, crmMoney(d.value * d.probability / 100, compact: false)),
              if (d.expectedClose != null) ErpFact('crm.closeDate'.tr, dashDate(d.expectedClose)),
              if (d.customer != null) ErpFact('crm.customer'.tr, d.customer!),
              if (d.leadName != null)
                ErpFact('crm.fromLead'.tr, d.leadName!, onTap: d.leadId == null ? null : () => Get.toNamed(Routes.crmLead, arguments: d.leadId)),
              if (d.owner != null) ErpFact('crm.owner'.tr, d.owner!),
              if (d.closeReason != null) ErpFact('crm.reason'.tr, crmReasonLabel(d.closeReason!)),
              if (d.closeNote != null) ErpFact('crm.note'.tr, d.closeNote!),
              if (d.createdAt != null) ErpFact('crm.created'.tr, dashDateTime(d.createdAt)),
              if (d.notes != null) ErpFact('crm.notes'.tr, d.notes!),
            ],
          ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'crm.activities'.tr,
          padded: false,
          child: d.activities.isEmpty
              ? OpsPanelEmpty('crm.noActivities'.tr)
              : Column(
                  children: [
                    for (var i = 0; i < d.activities.length; i++)
                      CrmActivityRow(
                        activity: d.activities[i],
                        divider: i > 0,
                        showLink: false,
                        onDone: manage
                            ? () async {
                                if (await crmComplete(context, d.activities[i])) _load();
                              }
                            : null,
                      ),
                  ],
                ),
        ),
        if (d.history.isNotEmpty) ...[
          erpGap,
          VouchFlowPanel(
            title: 'crm.history'.tr,
            padded: false,
            child: Column(
              children: [
                for (var i = 0; i < d.history.length; i++)
                  VouchFlowListRow(
                    divider: i > 0,
                    icon: PhosphorIconsRegular.clockCounterClockwise,
                    iconColor: t.muted,
                    title: d.history[i].what,
                    titleMaxLines: 2,
                    subtitle: [d.history[i].who, if (d.history[i].at != null) dashDateTime(d.history[i].at)].join(' · '),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
