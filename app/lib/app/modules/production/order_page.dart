import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart';
import '../../data/models/ops_models.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/production_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart' show showToast;
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate, dashDateTime;
import '../erp/erp_widgets.dart';
import '../erp/ops_kit.dart';
import '../inventory/inventory_widgets.dart' show ErpFact, QtyText;
import 'production_widgets.dart';

/// One production order (the web's /erp/production/orders/[id]): output so
/// far, the materials with what is left to issue, the receipts and their
/// quality checks, the material issues, cost and timeline. The foot bar
/// offers, per permission and status, Release, Issue materials, Record
/// output, Complete, Close and Cancel. Opened with the order id.
class ProductionOrderPage extends StatefulWidget {
  const ProductionOrderPage({super.key, this.orderId});

  final int? orderId;

  @override
  State<ProductionOrderPage> createState() => _ProductionOrderPageState();
}

class _ProductionOrderPageState extends State<ProductionOrderPage> {
  late final int _id = widget.orderId ?? (Get.arguments as int);
  final _repo = ProductionRepository.to;
  final _erp = ErpService.to;
  ProductionOrder? _order;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final o = await _repo.order(_id);
      if (mounted) setState(() { _order = o; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = opsError(e));
    }
  }

  void _done(String? message, String fallback) {
    if (message == null) return;
    showToast(message.isEmpty ? fallback : message);
    _load();
  }

  List<VfSummaryRow> _summary(ProductionOrder o) => [
    VfSummaryRow('prd.product'.tr, o.productName),
    VfSummaryRow('prd.planned'.tr, '${ErpFmt.qty(o.planned)} ${o.unit}'),
    VfSummaryRow('prd.releasedQty'.tr, '${ErpFmt.qty(o.released)} ${o.unit}'),
  ];

  Future<void> _confirm(ProductionOrder o, String action) async {
    final currency = _erp.currency;
    final cancel = action == 'cancel';
    final message = await showVouchFlowDialog<String>(
      context,
      dialog: VouchFlowDialog(
        icon: switch (action) {
          'cancel' => PhosphorIconsRegular.xCircle,
          'close' => PhosphorIconsRegular.lockSimple,
          'release' => PhosphorIconsRegular.play,
          _ => PhosphorIconsRegular.flagCheckered,
        },
        tone: cancel ? VfTone.warn : VfTone.info,
        title: 'prd.$action.q'.trParams({'number': o.number}),
        subtitle: switch (action) {
          'release' => 'prd.release.sub'.tr,
          'complete' => 'prd.complete.sub'.tr,
          'close' => 'prd.close.sub'.trParams({'amount': '$currency ${ErpFmt.amount(o.costing?.wip ?? 0)}'}),
          _ => null,
        },
        summary: _summary(o),
        child: OpsConfirm(
          confirmLabel: 'prd.$action'.tr,
          danger: cancel,
          backLabel: cancel ? 'inv.keep'.tr : null,
          fieldLabel: cancel ? 'inv.reason'.tr : null,
          fieldHint: cancel ? 'inv.reasonHint'.tr : null,
          minLength: cancel ? 3 : 0,
          run: (reason) => cancel ? _repo.cancel(o.id, reason) : _repo.act(o.id, action),
        ),
      ),
    );
    _done(message, prdStatusLabel(o.status));
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    return VouchFlowPushedScaffold(
      title: o?.number ?? 'prd.order'.tr,
      body: o == null
          ? (_error == null
                ? const VfLoadingView()
                : ErpPageBody(children: [VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)]))
          : _body(context, o),
      bottomBar: o == null ? null : _actions(o),
    );
  }

  Widget? _actions(ProductionOrder o) {
    final s = o.status;
    final buttons = <Widget>[
      if (s == PrdStatus.planned && _erp.can('production.plan'))
        VouchFlowButton(
          label: 'prd.cancel'.tr,
          variant: VfButtonVariant.secondary,
          onPressed: () => _confirm(o, 'cancel'),
        ),
      if (s == PrdStatus.planned && _erp.can('production.plan'))
        VouchFlowButton(label: 'prd.release'.tr, icon: PhosphorIconsRegular.play, onPressed: () => _confirm(o, 'release')),
      if (o.onFloor && _erp.can('production.issue'))
        VouchFlowButton(
          label: 'prd.issue'.tr,
          icon: PhosphorIconsRegular.trayArrowUp,
          variant: VfButtonVariant.secondary,
          onPressed: () async => _done(await showIssueSheet(context, o), 'prd.issued'.tr),
        ),
      if (o.onFloor && !o.hasFinal && _erp.can('production.receive'))
        VouchFlowButton(
          label: 'prd.output'.tr,
          icon: PhosphorIconsRegular.package,
          onPressed: () async => _done(await showOutputSheet(context, o), 'prd.rcpt.pending_qc'.tr),
        ),
      if (s == PrdStatus.inProgress && _erp.can('production.plan'))
        VouchFlowButton(
          label: 'prd.complete'.tr,
          icon: PhosphorIconsRegular.flagCheckered,
          variant: VfButtonVariant.secondary,
          onPressed: () => _confirm(o, 'complete'),
        ),
      if (s == PrdStatus.completed && _erp.can('production.close'))
        VouchFlowButton(label: 'prd.close'.tr, icon: PhosphorIconsRegular.lockSimple, onPressed: () => _confirm(o, 'close')),
      if (s == PrdStatus.released && _erp.can('production.plan'))
        VouchFlowButton(
          label: 'prd.cancel'.tr,
          variant: VfButtonVariant.ghost,
          onPressed: () => _confirm(o, 'cancel'),
        ),
    ];
    if (buttons.isEmpty) return null;
    return OpsActionBar(children: buttons);
  }

  Widget _body(BuildContext context, ProductionOrder o) {
    final t = context.vf;
    final currency = _erp.currency;
    final c = o.costing;
    final pending = o.receipts.where((r) => r.isPending).toList();
    final canQc = _erp.can('production.qc');

    return ErpPageBody(
      onRefresh: _load,
      children: [
        OpsHead(
          icon: PhosphorIconsRegular.factory,
          tint: prdStatusTone(o.status).colors(t).$1,
          kicker: 'prd.order'.tr,
          title: o.number,
          subtitle: [
            '${ErpFmt.qty(o.planned)} ${o.unit} · ${o.productName}',
            if (o.bomVersion != null) '${'prd.version'.tr} ${o.bomVersion}',
            if (o.plannedStart != null) '${dashDate(o.plannedStart)} - ${dashDate(o.plannedEnd)}',
          ].join(' · '),
          badge: PrdStatusBadge(o.status, large: true),
        ),
        if (pending.isNotEmpty && canQc) ...[
          VouchFlowAlert(
            tone: VfTone.warn,
            icon: PhosphorIconsRegular.sealCheck,
            message: 'prd.pendingAlert'.trParams({'n': '${pending.length}'}),
            action: VouchFlowButton(
              label: 'prd.inspect'.tr,
              compact: true,
              onPressed: () async => _done(await showQcSheet(context, pending.first, productName: o.productName), 'prd.rcpt.released'.tr),
            ),
          ),
          erpGap,
        ],
        VouchFlowPanel(
          title: 'prd.outputPanel'.tr,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OpsProgress(o.progress, color: prdStatusTone(o.status).colors(t).$1),
              const SizedBox(height: 12),
              OpsFigureGrid(
                items: [
                  ('prd.planned'.tr, ErpFmt.qty(o.planned)),
                  ('prd.produced'.tr, ErpFmt.qty(o.produced)),
                  ('prd.releasedQty'.tr, ErpFmt.qty(o.released)),
                  ('prd.rejected'.tr, ErpFmt.qty(o.rejected)),
                  ('prd.wastage'.tr, ErpFmt.qty(o.wastage)),
                  ('prd.yield'.tr, opsPercent(c?.yieldPercent)),
                ],
              ),
            ],
          ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'prd.materials'.tr,
          subtitle: 'prd.materialsSub'.tr,
          padded: false,
          actionLabel: o.bom == null ? null : 'prd.viewBom'.tr,
          onAction: o.bom == null ? null : () => Get.toNamed(Routes.prdBom, arguments: o.bom!.id),
          child: o.requirements.isEmpty
              ? OpsPanelEmpty('prd.noMaterials'.tr)
              : Column(
                  children: [
                    for (var i = 0; i < o.requirements.length; i++) _RequirementRow(r: o.requirements[i], divider: i > 0),
                  ],
                ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'prd.receipts'.tr,
          subtitle: 'prd.receiptsSub'.tr,
          padded: false,
          child: o.receipts.isEmpty
              ? OpsPanelEmpty('prd.noReceipts'.tr)
              : Column(
                  children: [
                    for (var i = 0; i < o.receipts.length; i++)
                      PrdReceiptRow(
                        receipt: o.receipts[i],
                        divider: i > 0,
                        unit: o.unit,
                        onInspect: o.receipts[i].isPending && canQc
                            ? () async => _done(
                                await showQcSheet(context, o.receipts[i], productName: o.productName),
                                'prd.rcpt.released'.tr,
                              )
                            : null,
                      ),
                  ],
                ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'prd.issues'.tr,
          padded: false,
          child: o.issues.isEmpty
              ? OpsPanelEmpty('prd.noIssues'.tr)
              : Column(
                  children: [
                    for (var i = 0; i < o.issues.length; i++)
                      VouchFlowListRow(
                        divider: i > 0,
                        icon: PhosphorIconsRegular.trayArrowUp,
                        iconColor: t.warningStrong,
                        title: o.issues[i].number,
                        titleMaxLines: 1,
                        subtitle: [
                          if (o.issues[i].date != null) dashDate(o.issues[i].date),
                          ?o.issues[i].creator,
                          'prd.linesN'.trParams({'n': '${o.issues[i].lines.length}'}),
                        ].join(' · '),
                        trailing: Text(
                          ErpFmt.compactMoney(o.issues[i].value, currency),
                          style: VfType.small.copyWith(color: t.text, fontWeight: FontWeight.w600),
                        ),
                        onTap: _erp.can('inventory.view')
                            ? () => Get.toNamed(Routes.erpDocument, arguments: o.issues[i].id)
                            : null,
                      ),
                  ],
                ),
        ),
        if (c != null) ...[
          erpGap,
          VouchFlowPanel(
            title: 'prd.cost'.tr,
            subtitle: o.status == PrdStatus.closed ? 'prd.costClosed'.tr : 'prd.costOpen'.tr,
            child: Column(
              children: [
                if (c.standardUnit != null) ErpFact('prd.standardUnit'.tr, '$currency ${ErpFmt.amount(c.standardUnit)}'),
                ErpFact('prd.materialCost'.tr, '$currency ${ErpFmt.amount(c.material)}'),
                ErpFact('prd.conversionCost'.tr, '$currency ${ErpFmt.amount(c.conversion)}'),
                ErpFact('prd.actualTotal'.tr, '$currency ${ErpFmt.amount(c.actualTotal)}'),
                if (c.actualUnit != null) ErpFact('prd.actualUnit'.tr, '$currency ${ErpFmt.amount(c.actualUnit)}'),
                ErpFact('prd.receivedValue'.tr, '$currency ${ErpFmt.amount(c.received)}'),
                ErpFact('prd.wip'.tr, '$currency ${ErpFmt.amount(c.wip)}'),
                if (c.variance != null) ErpFact('prd.variance'.tr, '$currency ${ErpFmt.amount(c.variance)}'),
              ],
            ),
          ),
        ],
        erpGap,
        VouchFlowPanel(
          title: 'prd.timeline'.tr,
          child: Column(
            children: [
              ErpFact('prd.plannedBy'.tr, [o.creator ?? '-', if (o.createdAt != null) dashDateTime(o.createdAt)].join(' · ')),
              if (o.releasedAt != null) ErpFact('prd.releasedBy'.tr, [o.releaser ?? '-', dashDateTime(o.releasedAt)].join(' · ')),
              if (o.startedAt != null) ErpFact('prd.started'.tr, dashDateTime(o.startedAt)),
              if (o.completedAt != null) ErpFact('prd.completedBy'.tr, [o.completer ?? '-', dashDateTime(o.completedAt)].join(' · ')),
              if (o.closedAt != null) ErpFact('prd.closedBy'.tr, [o.closer ?? '-', dashDateTime(o.closedAt)].join(' · ')),
              if (o.cancelledAt != null)
                ErpFact('prd.cancelledBy'.tr, [o.canceller ?? '-', dashDateTime(o.cancelledAt), ?o.cancelReason].join(' · ')),
              if (o.materialsWarehouse != null) ErpFact('prd.materialsFrom'.tr, o.materialsWarehouse!),
              if (o.outputWarehouse != null) ErpFact('prd.outputTo'.tr, o.outputWarehouse!),
              if (o.workCentre != null) ErpFact('prd.workCentre'.tr, o.workCentre!),
              if (o.reference != null) ErpFact('inv.reference'.tr, o.reference!),
              if (o.notes != null) ErpFact('prd.notes'.tr, o.notes!),
            ],
          ),
        ),
      ],
    );
  }
}

class _RequirementRow extends StatelessWidget {
  const _RequirementRow({required this.r, required this.divider});

  final PrdRequirement r;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final done = r.remaining <= 0;
    return VouchFlowListRow(
      divider: divider,
      title: r.name,
      titleMaxLines: 2,
      subtitle: [
        '${'prd.issued'.tr} ${ErpFmt.qty(r.issued)} / ${ErpFmt.qty(r.required)}',
        '${'prd.inStore'.tr} ${ErpFmt.qty(r.available)}',
      ].join(' · '),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          QtyText(r.remaining, unit: r.unit),
          const SizedBox(height: 3),
          done
              ? OpsBadge('prd.fullyIssued'.tr, tone: VfTone.ok)
              : r.sufficient
              ? Text('prd.toIssue'.tr, style: VfType.meta.copyWith(color: t.muted))
              : OpsBadge('prd.short'.tr, tone: VfTone.bad),
        ],
      ),
    );
  }
}

/// A receipt: number, batch, quantities, and its quality check or the
/// Inspect button.
class PrdReceiptRow extends StatelessWidget {
  const PrdReceiptRow({super.key, required this.receipt, required this.divider, this.unit = '', this.onInspect, this.onTap, this.showOrder = false});

  final PrdReceipt receipt;
  final bool divider, showOrder;
  final String unit;
  final VoidCallback? onInspect, onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final r = receipt;
    final failed = r.parameters.where((p) => !p.passed).map((p) => p.name).toList();
    return VouchFlowListRow(
      divider: divider,
      icon: r.isPending ? PhosphorIconsRegular.hourglassMedium : PhosphorIconsRegular.sealCheck,
      iconColor: prdReceiptTone(r.status).colors(t).$1,
      title: showOrder ? (r.productName ?? r.number) : r.number,
      titleMaxLines: 1,
      onTap: onTap,
      subtitle: [
        if (showOrder) r.number,
        ?r.batch,
        if (r.date != null) dashDate(r.date),
        '${'prd.good'.tr} ${ErpFmt.qty(r.good)}${unit.isEmpty ? '' : ' $unit'}',
        if (r.isFinal) 'prd.final'.tr,
        if (r.inspector != null) failed.isEmpty ? '${r.inspector}: ${'prd.allPassed'.tr}' : '${r.inspector}: ${failed.join(', ')}',
      ].join(' · '),
      trailing: onInspect != null
          ? VouchFlowButton(label: 'prd.inspect'.tr, compact: true, onPressed: onInspect)
          : OpsBadge(prdReceiptLabel(r.status), tone: prdReceiptTone(r.status)),
    );
  }
}
