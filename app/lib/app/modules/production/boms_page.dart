import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart';
import '../../data/models/ops_models.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/production_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../erp/erp_widgets.dart';
import '../erp/ops_kit.dart';
import '../inventory/inventory_widgets.dart' show ErpFact, QtyText;

/// The bills of materials, read only on the phone (the web's
/// /erp/production/boms): each version with its output, components and
/// standard cost. Editing a recipe stays on the web.
class BomsPage extends StatelessWidget {
  const BomsPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'production',
    permission: 'production.view',
    builder: (_) => const _Boms(),
  );
}

class _Boms extends StatefulWidget {
  const _Boms();

  @override
  State<_Boms> createState() => _BomsState();
}

class _BomsState extends State<_Boms> {
  final _repo = ProductionRepository.to;
  String _q = '';
  Timer? _debounce;
  List<PrdBom>? _rows;
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

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final page = await _repo.boms(q: _q.trim().isEmpty ? null : _q.trim());
      if (mounted && generation == _generation) setState(() { _rows = page.data; _error = null; });
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = opsError(e));
    }
  }

  void _search(String v) {
    _q = v;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), _load);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final rows = _rows;
    final currency = ErpService.to.currency;
    return ErpPageBody(
      onRefresh: _load,
      children: [
        ErpPageTitle('prd.nav.boms'.tr, subtitle: 'prd.bomsSub'.tr),
        VouchFlowSearchField(placeholder: 'prd.searchBoms'.tr, onChanged: _search),
        const SizedBox(height: 14),
        if (rows == null && _error == null)
          const VfLoadingView(inline: true)
        else if (rows == null)
          VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)
        else if (rows.isEmpty)
          VouchFlowEmptyState(icon: PhosphorIconsRegular.listChecks, title: 'prd.noBoms'.tr)
        else
          VouchFlowPanel(
            padded: false,
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++)
                  VouchFlowListRow(
                    divider: i > 0,
                    icon: PhosphorIconsRegular.listChecks,
                    iconColor: rows[i].isActive ? t.successStrong : t.muted,
                    title: rows[i].productName,
                    subtitle: [
                      '${'prd.version'.tr} ${rows[i].version}',
                      'prd.perBatch'.trParams({'qty': ErpFmt.qty(rows[i].output), 'unit': rows[i].unit}),
                      if (rows[i].standardCost != null) '$currency ${ErpFmt.amount(rows[i].standardCost!.round())}',
                    ].join(' · '),
                    trailing: OpsBadge(
                      rows[i].isActive ? 'prd.active'.tr : 'prd.inactive'.tr,
                      tone: rows[i].isActive ? VfTone.ok : VfTone.neutral,
                    ),
                    onTap: () => Get.toNamed(Routes.prdBom, arguments: rows[i].id),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// One bill of materials (the web's /erp/production/boms/[id]): output per
/// batch, components with their allowance and cost per unit, conversion and
/// standard cost, and the other versions. Opened with the BOM's id.
class BomPage extends StatefulWidget {
  const BomPage({super.key, this.bomId});

  final int? bomId;

  @override
  State<BomPage> createState() => _BomPageState();
}

class _BomPageState extends State<BomPage> {
  late int _id = widget.bomId ?? (Get.arguments as int);
  PrdBom? _bom;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await ProductionRepository.to.bom(_id);
      if (mounted) setState(() { _bom = b; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = opsError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _bom;
    return VouchFlowPushedScaffold(
      title: b == null ? 'prd.bom'.tr : '${'prd.version'.tr} ${b.version}',
      body: b == null
          ? (_error == null
                ? const VfLoadingView()
                : ErpPageBody(children: [VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)]))
          : _body(context, b),
    );
  }

  Widget _body(BuildContext context, PrdBom b) {
    final t = context.vf;
    final currency = ErpService.to.currency;
    return ErpPageBody(
      onRefresh: _load,
      children: [
        OpsHead(
          icon: PhosphorIconsRegular.listChecks,
          tint: b.isActive ? t.successStrong : t.muted,
          kicker: 'prd.bom'.tr,
          title: b.productName,
          subtitle: [
            '${'prd.version'.tr} ${b.version}',
            'prd.perBatch'.trParams({'qty': ErpFmt.qty(b.output), 'unit': b.unit}),
            ?b.workCentre,
          ].join(' · '),
          badge: OpsBadge(b.isActive ? 'prd.active'.tr : 'prd.inactive'.tr, tone: b.isActive ? VfTone.ok : VfTone.neutral, large: true),
        ),
        VouchFlowPanel(
          title: 'prd.components'.tr,
          trailing: Text('${b.lines.length}', style: VfType.small.copyWith(color: t.muted, fontWeight: FontWeight.w600)),
          padded: false,
          child: Column(
            children: [
              for (var i = 0; i < b.lines.length; i++)
                VouchFlowListRow(
                  divider: i > 0,
                  title: b.lines[i].name,
                  titleMaxLines: 2,
                  subtitle: [
                    b.lines[i].sku,
                    if (b.lines[i].scrap > 0) '${'prd.allowance'.tr} ${ErpFmt.qty(b.lines[i].scrap)}%',
                    if (b.lines[i].costPerUnit != null) '$currency ${ErpFmt.amount(double.parse(b.lines[i].costPerUnit!.toStringAsFixed(2)))} ${'prd.perUnitShort'.tr}',
                  ].join(' · '),
                  trailing: QtyText(b.lines[i].quantity, unit: b.lines[i].unit),
                ),
            ],
          ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'prd.standardCost'.tr,
          subtitle: 'prd.standardCostSub'.tr,
          child: Column(
            children: [
              if (b.materialsPerUnit != null) ErpFact('prd.materialsPerUnit'.tr, '$currency ${ErpFmt.amount(double.parse(b.materialsPerUnit!.toStringAsFixed(2)))}'),
              if (b.conversionPerUnit != null) ErpFact('prd.conversionPerUnit'.tr, '$currency ${ErpFmt.amount(double.parse(b.conversionPerUnit!.toStringAsFixed(2)))}'),
              if (b.standardCost != null) ErpFact('prd.standardUnit'.tr, '$currency ${ErpFmt.amount(double.parse(b.standardCost!.toStringAsFixed(2)))}'),
              ErpFact('prd.labourPerBatch'.tr, '$currency ${ErpFmt.amount(b.labour)}'),
              ErpFact('prd.overheadPerBatch'.tr, '$currency ${ErpFmt.amount(b.overhead)}'),
              ErpFact('prd.usedBy'.tr, 'prd.ordersN'.trParams({'n': '${b.ordersCount}'})),
              if (b.notes != null) ErpFact('prd.notes'.tr, b.notes!),
            ],
          ),
        ),
        if (b.versions.length > 1) ...[
          erpGap,
          VouchFlowPanel(
            title: 'prd.versions'.tr,
            padded: false,
            child: Column(
              children: [
                for (var i = 0; i < b.versions.length; i++)
                  VouchFlowListRow(
                    divider: i > 0,
                    icon: PhosphorIconsRegular.gitBranch,
                    iconColor: b.versions[i].id == b.id ? t.primary : t.muted,
                    title: '${'prd.version'.tr} ${b.versions[i].version}',
                    trailing: b.versions[i].active ? OpsBadge('prd.active'.tr, tone: VfTone.ok) : null,
                    onTap: b.versions[i].id == b.id
                        ? null
                        : () {
                            setState(() { _id = b.versions[i].id; _bom = null; });
                            _load();
                          },
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
