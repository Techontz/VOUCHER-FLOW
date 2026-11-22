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

/// The pipeline on a phone (the web's /erp/crm/pipeline board, one column
/// at a time): pick a stage, see its deals, and move one with the arrows
/// beside it. Closed deals are the last 90 days'.
class CrmPipelinePage extends StatelessWidget {
  const CrmPipelinePage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(module: 'crm', permission: 'crm.view', builder: (_) => const _Pipeline());
}

class _Pipeline extends StatefulWidget {
  const _Pipeline();

  @override
  State<_Pipeline> createState() => _PipelineState();
}

class _PipelineState extends State<_Pipeline> {
  final _repo = CrmRepository.to;
  List<CrmStageTotal>? _board;
  String? _error;
  String _stage = CrmStage.prospecting;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await _repo.board();
      if (mounted) setState(() { _board = b; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = opsError(e));
    }
  }

  Future<void> _open(CrmOpportunity d) async {
    await Get.toNamed(Routes.crmOpportunity, arguments: d.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final board = _board;
    if (board == null) {
      return _error == null
          ? const VfLoadingView()
          : ErpPageBody(onRefresh: _load, children: [VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)]);
    }
    final t = context.vf;
    final manage = ErpService.to.can('crm.manage');
    final column = board.where((c) => c.stage == _stage).firstOrNull ?? CrmStageTotal(stage: _stage, count: 0, value: 0, weighted: 0);
    final open = board.where((c) => CrmStage.open.contains(c.stage));
    final openValue = open.fold<double>(0, (s, c) => s + c.value);
    final weighted = open.fold<double>(0, (s, c) => s + c.weighted);

    return ErpPageBody(
      onRefresh: _load,
      children: [
        ErpPageTitle(
          'crm.nav.pipeline'.tr,
          subtitle: 'crm.pipelineLine'.trParams({'open': crmMoney(openValue), 'weighted': crmMoney(weighted)}),
        ),
        OpsChips<String>(
          values: CrmStage.all,
          selected: _stage,
          label: crmStageLabel,
          counts: {for (final c in board) c.stage: c.count},
          onChanged: (s) => setState(() => _stage = s),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: crmStageTone(_stage).colors(t).$1, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${crmStageLabel(_stage)} · ${crmDeals(column.count)}',
                style: VfType.label.copyWith(color: t.text),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              CrmStage.open.contains(_stage)
                  ? '${crmMoney(column.value)} · ${crmMoney(column.weighted)}'
                  : crmMoney(column.value),
              style: VfType.meta.copyWith(color: t.muted, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ],
        ),
        if (!CrmStage.open.contains(_stage)) ...[
          const SizedBox(height: 4),
          Text('crm.recentClosed'.tr, style: VfType.meta.copyWith(color: t.muted)),
        ],
        const SizedBox(height: 10),
        if (column.items.isEmpty)
          VouchFlowEmptyState(icon: PhosphorIconsRegular.kanban, title: 'crm.emptyStage'.tr)
        else
          VouchFlowPanel(
            padded: false,
            child: Column(
              children: [
                for (var i = 0; i < column.items.length; i++)
                  CrmDealRow(
                    deal: column.items[i],
                    divider: i > 0,
                    showStage: false,
                    onTap: () => _open(column.items[i]),
                    onMove: manage
                        ? () async {
                            if (await crmMoveStage(context, column.items[i])) _load();
                          }
                        : null,
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}
