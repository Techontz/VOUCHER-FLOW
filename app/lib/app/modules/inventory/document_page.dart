import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/inventory_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart' show showToast;
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate, dashDateTime;
import '../erp/erp_widgets.dart';
import 'inventory_widgets.dart';
import 'product_page.dart' show MovementRow;

/// One stock document: its lines, who prepared and posted it, the
/// movements it made, and, gated by permission, Post, Cancel draft and
/// Reverse, each behind a confirmation sheet (the web's
/// /erp/documents/[id]). Opened with the document id as the argument.
class DocumentPage extends StatefulWidget {
  const DocumentPage({super.key, this.documentId});

  final int? documentId;

  @override
  State<DocumentPage> createState() => _DocumentPageState();
}

class _DocumentPageState extends State<DocumentPage> {
  late int _id = widget.documentId ?? (Get.arguments as int);
  ErpStockDocument? _doc;
  String? _error;

  final _erp = ErpService.to;
  final _repo = InventoryRepository.to;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _repo.document(_id);
      if (mounted) setState(() { _doc = d; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'state.offline'.tr);
    }
  }

  List<VfSummaryRow> _summary(ErpStockDocument d) => [
    VfSummaryRow('inv.type'.tr, docTypeLabel(d.type)),
    VfSummaryRow('inv.warehouse'.tr, d.place),
    VfSummaryRow('inv.lines'.tr, '${d.lines.length}'),
  ];

  Future<void> _post(ErpStockDocument d) async {
    final message = await showVouchFlowDialog<String>(
      context,
      dialog: VouchFlowDialog(
        icon: PhosphorIconsRegular.checkCircle,
        tone: VfTone.info,
        title: 'inv.postQ'.trParams({'number': d.number}),
        subtitle: 'inv.postSub'.tr,
        summary: _summary(d),
        child: _ConfirmActions(
          confirmLabel: 'inv.post'.tr,
          run: (_) => _repo.post(d.id),
        ),
      ),
    );
    if (message == null) return;
    showToast(message.isEmpty ? 'inv.status.posted'.tr : message);
    _load();
  }

  Future<void> _cancel(ErpStockDocument d) async {
    final done = await showVouchFlowDialog<String>(
      context,
      dialog: VouchFlowDialog(
        icon: PhosphorIconsRegular.xCircle,
        tone: VfTone.warn,
        title: 'inv.cancelDraftQ'.trParams({'number': d.number}),
        subtitle: 'inv.cancelDraftSub'.tr,
        summary: _summary(d),
        child: _ConfirmActions(
          confirmLabel: 'inv.cancelDraft'.tr,
          backLabel: 'inv.keep'.tr,
          danger: true,
          run: (_) async {
            await _repo.cancel(d.id);
            return 'inv.status.cancelled'.tr;
          },
        ),
      ),
    );
    if (done == null) return;
    showToast(done);
    _load();
  }

  Future<void> _reverse(ErpStockDocument d) async {
    final reversal = await showVouchFlowDialog<String>(
      context,
      dialog: VouchFlowDialog(
        icon: PhosphorIconsRegular.arrowUUpLeft,
        tone: VfTone.warn,
        title: 'inv.reverseQ'.trParams({'number': d.number}),
        subtitle: 'inv.reverseSub'.tr,
        summary: _summary(d),
        child: _ConfirmActions(
          confirmLabel: 'inv.reverse'.tr,
          danger: true,
          reason: true,
          run: (reason) async {
            final r = await _repo.reverse(d.id, reason);
            return '${r.id}';
          },
        ),
      ),
    );
    if (reversal == null) return;
    // The reversing document is the one to look at now, as on the web.
    showToast('inv.status.reversed'.tr, body: d.number);
    setState(() {
      _id = int.parse(reversal);
      _doc = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _doc;
    return VouchFlowPushedScaffold(
      title: d?.number ?? 'inv.documents'.tr,
      body: d == null
          ? (_error == null
                ? const VfLoadingView()
                : ErpPageBody(children: [VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)]))
          : _body(context, d),
      bottomBar: d == null ? null : _actions(context, d),
    );
  }

  Widget? _actions(BuildContext context, ErpStockDocument d) {
    final mayPrepare = _erp.can(ErpDocType.preparePermission[d.type] ?? '');
    final buttons = <Widget>[
      if (d.isDraft && mayPrepare)
        VouchFlowButton(
          label: 'inv.cancelDraft'.tr,
          variant: VfButtonVariant.secondary,
          onPressed: () => _cancel(d),
        ),
      if (d.isDraft && _erp.can('inventory.post'))
        VouchFlowButton(
          label: 'inv.post'.tr,
          icon: PhosphorIconsRegular.checkCircle,
          onPressed: () => _post(d),
        ),
      if (d.isPosted && d.reversalOfId == null && _erp.can('inventory.reverse'))
        VouchFlowButton(
          label: 'inv.reverse'.tr,
          icon: PhosphorIconsRegular.arrowUUpLeft,
          variant: VfButtonVariant.secondary,
          onPressed: () => _reverse(d),
        ),
    ];
    if (buttons.isEmpty) return null;
    final t = context.vf;
    return VfGlass(
      borderRadius: BorderRadius.zero,
      fill: t.barFill,
      highlight: false,
      shadow: false,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(VfSize.pagePad, 12, VfSize.pagePad, 12),
          child: VouchFlowActions(children: buttons),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, ErpStockDocument d) {
    final t = context.vf;
    final currency = _erp.currency;
    final costed = ErpDocType.costed(d.type);
    final count = d.type == ErpDocType.count;
    final value = d.movements
        .where((m) => m.type != 'transfer_in')
        .fold<double>(0, (s, m) => s + m.value);

    return ErpPageBody(
      onRefresh: _load,
      children: [
        // Head: what it is, its number and status, where and when.
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: docTypeTint(t, d.type).withValues(alpha: t.isDark ? .18 : .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(docTypeIcon(d.type), size: 25, color: docTypeTint(t, d.type)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      docTypeLabel(d.type),
                      style: VfType.small.copyWith(color: t.muted, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      d.number,
                      style: VfType.pageTitle.copyWith(
                        color: t.text,
                        fontSize: 19,
                        letterSpacing: -.3,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        d.place,
                        ?d.supplier?.name,
                        if (d.documentDate != null) dashDate(d.documentDate),
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: VfType.small.copyWith(color: t.text2),
                    ),
                    const SizedBox(height: 10),
                    DocStatusBadge(d.status, large: true),
                  ],
                ),
              ),
            ],
          ),
        ),
        VouchFlowPanel(
          title: 'inv.lines'.tr,
          trailing: Text(
            '${d.lines.length}',
            style: VfType.small.copyWith(color: t.muted, fontWeight: FontWeight.w600),
          ),
          padded: false,
          child: Column(
            children: [
              for (var i = 0; i < d.lines.length; i++)
                _LineRow(
                  line: d.lines[i],
                  divider: i > 0,
                  costed: costed,
                  count: count,
                  showVariance: count && !d.isDraft,
                  currency: currency,
                  signed: d.type == ErpDocType.adjustment,
                ),
            ],
          ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'inv.details'.tr,
          child: Column(
            children: [
              ErpFact(
                'inv.prepared'.tr,
                [d.creator?.name ?? '-', if (d.createdAt != null) dashDateTime(d.createdAt)].join(' · '),
              ),
              if (d.postedAt != null)
                ErpFact('inv.postedBy'.tr, [d.poster?.name ?? '-', dashDateTime(d.postedAt)].join(' · ')),
              if (d.reversalOf != null)
                ErpFact(
                  'inv.reversalOf'.tr,
                  d.reversalOf!.name,
                  onTap: () => Get.toNamed(Routes.erpDocument, arguments: d.reversalOf!.id, preventDuplicates: false),
                ),
              if (d.reference != null) ErpFact('inv.reference'.tr, d.reference!),
              if (d.reason != null) ErpFact('inv.reason'.tr, d.reason!),
              if (d.movements.isNotEmpty && d.type != ErpDocType.transfer)
                ErpFact('inv.value'.tr, '$currency ${ErpFmt.amount(value.abs())}'),
            ],
          ),
        ),
        if (d.movements.isNotEmpty) ...[
          erpGap,
          VouchFlowPanel(
            title: 'inv.movementsPosted'.tr,
            padded: false,
            child: Column(
              children: [
                for (var i = 0; i < d.movements.length; i++)
                  MovementRow(
                    movement: d.movements[i],
                    divider: i > 0,
                    showProduct: true,
                    unit: d.lines.where((l) => l.productId == d.movements[i].productId).firstOrNull?.unitCode,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.line,
    required this.divider,
    required this.costed,
    required this.count,
    required this.showVariance,
    required this.currency,
    required this.signed,
  });

  final ErpDocumentLine line;
  final bool divider, costed, count, showVariance, signed;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final l = line;
    final sub = [
      l.productSku ?? '',
      if (l.batchNumber != null && l.batchNumber!.isNotEmpty) '${'inv.batch'.tr} ${l.batchNumber}',
      if (l.expiryDate != null) 'inv.expiresOn'.trParams({'date': dashDate(l.expiryDate)}),
      if (costed && l.unitCost != null) '@ ${ErpFmt.amount(l.unitCost)}',
    ].where((s) => s.isNotEmpty).join(' · ');
    final variance = showVariance && l.systemQuantity != null ? l.quantity - l.systemQuantity! : null;

    return VouchFlowListRow(
      divider: divider,
      title: l.productName ?? '',
      titleMaxLines: 2,
      subtitle: sub,
      onTap: () => Get.toNamed(Routes.erpProduct, arguments: l.productId),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          QtyText(l.quantity, unit: l.unitCode, signed: signed),
          if (count && l.systemQuantity != null) ...[
            const SizedBox(height: 2),
            Text(
              '${'inv.system'.tr} ${ErpFmt.qty(l.systemQuantity)}',
              style: VfType.meta.copyWith(color: t.muted, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ],
          if (variance != null) ...[
            const SizedBox(height: 2),
            QtyText(variance, signed: true, style: VfType.meta.copyWith(fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}

/// The two buttons at the foot of a confirmation sheet, with an optional
/// reason field; the confirming one runs [run] and closes the sheet with
/// its result, or shows the API's refusal in place.
class _ConfirmActions extends StatefulWidget {
  const _ConfirmActions({
    required this.confirmLabel,
    required this.run,
    this.backLabel,
    this.danger = false,
    this.reason = false,
  });

  final String confirmLabel;
  final String? backLabel;
  final bool danger, reason;
  final Future<String> Function(String reason) run;

  @override
  State<_ConfirmActions> createState() => _ConfirmActionsState();
}

class _ConfirmActionsState extends State<_ConfirmActions> {
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() { _busy = true; _error = null; });
    try {
      final result = await widget.run(_reason.text.trim());
      if (mounted) Navigator.of(context).pop(result);
    } on ApiException catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.field('reason') ?? e.message; });
    } catch (_) {
      if (mounted) setState(() { _busy = false; _error = 'state.offline'.tr; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final ready = !widget.reason || _reason.text.trim().length >= 3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.reason) ...[
          VouchFlowTextField(
            label: 'inv.reason'.tr,
            required: true,
            controller: _reason,
            placeholder: 'inv.reasonHint'.tr,
            autofocus: true,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 4),
        ],
        if (_error != null) ...[
          Row(
            children: [
              Icon(PhosphorIconsRegular.warningCircle, size: 16, color: t.dangerStrong),
              const SizedBox(width: 6),
              Expanded(child: Text(_error!, style: VfType.small.copyWith(color: t.dangerStrong))),
            ],
          ),
          const SizedBox(height: 4),
        ],
        const SizedBox(height: 14),
        VouchFlowActions(
          children: [
            VouchFlowButton(
              label: widget.backLabel ?? 'action.back'.tr,
              variant: VfButtonVariant.secondary,
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
            ),
            VouchFlowButton(
              label: widget.confirmLabel,
              variant: widget.danger ? VfButtonVariant.dangerSolid : VfButtonVariant.primary,
              loading: _busy,
              onPressed: ready ? _go : null,
            ),
          ],
        ),
      ],
    );
  }
}
