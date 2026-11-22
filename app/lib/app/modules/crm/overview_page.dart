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
import 'crm_app.dart';
import 'crm_widgets.dart';

/// The CRM home (the web's /erp/crm): today's follow-ups and the overdue
/// ones first, then the pipeline's value, the month's wins and the
/// pipeline by stage.
class CrmOverviewPage extends StatelessWidget {
  const CrmOverviewPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'crm',
    permission: 'crm.view',
    builder: (_) => const _Overview(),
  );
}

class _Overview extends StatefulWidget {
  const _Overview();

  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  final _repo = CrmRepository.to;
  final _erp = ErpService.to;
  CrmOverview? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _repo.overview();
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = opsError(e));
    }
  }

  Future<void> _openActivity(CrmActivity a) async {
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
    final d = _data;
    if (d == null) {
      return _error == null
          ? const VfLoadingView()
          : ErpPageBody(
              onRefresh: _load,
              children: [
                VouchFlowErrorState(
                  message: _error!,
                  onRetry: _load,
                  retryLabel: 'action.retry'.tr,
                ),
              ],
            );
    }
    final t = context.vf;
    final manage = _erp.can('crm.manage');
    final actions = crmCreateActions
        .where((a) => a.permission == null || _erp.can(a.permission!))
        .toList();
    final open = d.stages
        .where((s) => CrmStage.open.contains(s.stage))
        .toList();
    final peak = open.fold<double>(1, (m, s) => s.value > m ? s.value : m);

    Widget activities(List<CrmActivity> rows, String empty) => rows.isEmpty
        ? OpsPanelEmpty(empty)
        : Column(
            children: [
              for (var i = 0; i < rows.length; i++)
                CrmActivityRow(
                  activity: rows[i],
                  divider: i > 0,
                  onTap: () => _openActivity(rows[i]),
                  onDone: manage
                      ? () async {
                          if (await crmComplete(context, rows[i])) _load();
                        }
                      : null,
                ),
            ],
          );

    return ErpPageBody(
      onRefresh: _load,
      children: [
        ErpPageTitle('area.crm'.tr, subtitle: 'crm.sub'.tr),
        VouchFlowFigureGrid(
          children: [
            VouchFlowFigureCard(
              label: 'crm.dueToday'.tr,
              value: '${d.dueToday.length}',
              hint: d.overdue.isEmpty
                  ? 'crm.noOverdue'.tr
                  : 'crm.overdueN'.trParams({'n': '${d.overdue.length}'}),
              icon: PhosphorIconsRegular.calendarCheck,
              tone: d.overdue.isNotEmpty ? VfTone.warn : VfTone.info,
              onTap: () => erpGo('/erp/crm/activities'),
            ),
            VouchFlowFigureCard(
              label: 'crm.pipelineValue'.tr,
              value: crmMoney(d.openValue),
              hint: 'crm.weightedHint'.trParams({
                'v': crmMoney(d.weightedValue),
              }),
              icon: PhosphorIconsRegular.kanban,
              onTap: () => erpGo('/erp/crm/pipeline'),
            ),
            VouchFlowFigureCard(
              label: 'crm.wonThisMonth'.tr,
              value: crmMoney(d.wonValue),
              hint: crmDeals(d.wonCount),
              icon: PhosphorIconsRegular.trophy,
              tone: VfTone.ok,
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (actions.isNotEmpty) ...[
          VouchFlowPanel(
            title: 'inv.quickActions'.tr,
            padded: false,
            child: Column(
              children: [
                for (var i = 0; i < actions.length; i++)
                  VouchFlowListRow(
                    divider: i > 0,
                    icon: actions[i].icon,
                    title: actions[i].label.tr,
                    subtitle: actions[i].hint?.tr,
                    trailing: Icon(
                      PhosphorIconsBold.caretRight,
                      size: 14,
                      color: t.faint,
                    ),
                    onTap: () async {
                      await erpCreate(actions[i]);
                      _load();
                    },
                  ),
              ],
            ),
          ),
          erpGap,
        ],
        VouchFlowPanel(
          title: 'crm.dueToday'.tr,
          padded: false,
          actionLabel: 'erp.viewAll'.tr,
          onAction: () => erpGo('/erp/crm/activities'),
          child: activities(d.dueToday, 'crm.nothingDue'.tr),
        ),
        if (d.overdue.isNotEmpty) ...[
          erpGap,
          VouchFlowPanel(
            title: 'crm.overdue'.tr,
            padded: false,
            child: activities(d.overdue, 'crm.noOverdue'.tr),
          ),
        ],
        erpGap,
        VouchFlowPanel(
          title: 'crm.byStage'.tr,
          actionLabel: 'crm.nav.pipeline'.tr,
          onAction: () => erpGo('/erp/crm/pipeline'),
          child: Column(
            children: [
              for (final s in open) ...[
                _StageBar(stage: s, peak: peak),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'crm.lostThisMonth'.tr,
                      style: VfType.small.copyWith(color: t.muted),
                    ),
                  ),
                  Text(
                    '${d.lostCount}',
                    style: VfType.small.copyWith(
                      color: t.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'crm.leadsByStatus'.tr,
          actionLabel: 'crm.nav.leads'.tr,
          onAction: () => erpGo('/erp/crm/leads'),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in CrmLeadStatus.all)
                OpsBadge(
                  '${crmLeadStatusLabel(s)} ${d.leads[s] ?? 0}',
                  tone: crmLeadTone(s),
                  large: true,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StageBar extends StatelessWidget {
  const _StageBar({required this.stage, required this.peak});

  final CrmStageTotal stage;
  final double peak;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final tone = crmStageTone(stage.stage).colors(t).$1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${crmStageLabel(stage.stage)} · ${crmDeals(stage.count)}',
                style: VfType.small.copyWith(
                  color: t.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              crmMoney(stage.value),
              style: VfType.small.copyWith(
                color: t.text,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        OpsProgress(
          stage.value / peak,
          color: tone == t.text2 ? t.primary : tone,
        ),
      ],
    );
  }
}
