import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart';
import '../../data/models/ops_models.dart';
import '../../data/services/production_repository.dart';
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;
import '../erp/ops_kit.dart';

/*
 * Pieces the Production screens share: how an order and a receipt status
 * read, an order as a list row, and the three floor sheets (issue
 * materials, record output, the quality check).
 */

String prdStatusLabel(String s) => 'prd.status.$s'.tr;

VfTone prdStatusTone(String s) => switch (s) {
  PrdStatus.released => VfTone.info,
  PrdStatus.inProgress => VfTone.warn,
  PrdStatus.completed => VfTone.ok,
  PrdStatus.cancelled => VfTone.bad,
  _ => VfTone.neutral,
};

String prdReceiptLabel(String s) => 'prd.rcpt.$s'.tr;

VfTone prdReceiptTone(String s) => switch (s) {
  PrdReceiptStatus.released => VfTone.ok,
  PrdReceiptStatus.rejected => VfTone.bad,
  _ => VfTone.warn,
};

class PrdStatusBadge extends StatelessWidget {
  const PrdStatusBadge(this.status, {super.key, this.large = false});

  final String status;
  final bool large;

  @override
  Widget build(BuildContext context) => OpsBadge(prdStatusLabel(status), tone: prdStatusTone(status), large: large);
}

final _numbers = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];

/// An order as a list row: product, number and dates, progress, status.
class PrdOrderRow extends StatelessWidget {
  const PrdOrderRow({super.key, required this.order, required this.onTap, this.divider = true});

  final ProductionOrder order;
  final VoidCallback onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final o = order;
    final showBar = o.onFloor || o.status == PrdStatus.completed;
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: divider ? Border(top: BorderSide(color: t.isDark ? t.glassBorder : t.border)) : null,
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: prdStatusTone(o.status).colors(t).$1.withValues(alpha: t.isDark ? .18 : .1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(PhosphorIconsRegular.factory, size: 19, color: prdStatusTone(o.status).colors(t).$1),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    o.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VfType.bodyStrong.copyWith(color: t.text, fontSize: 14.5, height: 1.3),
                  ),
                  Text(
                    [
                      o.number,
                      '${ErpFmt.qty(o.planned)} ${o.unit}'.trim(),
                      if (o.plannedStart != null) dashDate(o.plannedStart),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VfType.meta.copyWith(color: t.muted, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                  if (showBar) ...[
                    const SizedBox(height: 7),
                    OpsProgress(o.progress, color: prdStatusTone(o.status).colors(t).$1),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            PrdStatusBadge(o.status),
          ],
        ),
      ),
    );
  }
}

/// A sheet's title block: icon tile, title, the line under it.
class _SheetHead extends StatelessWidget {
  const _SheetHead({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: t.infoSoft, borderRadius: BorderRadius.circular(VfSize.radiusL)),
          child: Icon(icon, color: t.infoStrong, size: 22),
        ),
        const SizedBox(height: 14),
        Text(title, style: VfType.sectionTitle.copyWith(color: t.text)),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, style: VfType.body.copyWith(color: t.text2)),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}

/// A scrolling sheet body that lifts above the keyboard.
class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .9),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    ),
  );
}

/* ═════════════════════════════════════════════════════ issue materials ══ */

/// Issues materials to [order]: each component with what is left to issue
/// already filled in, a batch to take (automatic by default). Returns the
/// API's message once posted.
Future<String?> showIssueSheet(BuildContext context, ProductionOrder order) =>
    showVfSheet<String>(context, builder: (_) => _IssueSheet(order: order));

class _IssueSheet extends StatefulWidget {
  const _IssueSheet({required this.order});

  final ProductionOrder order;

  @override
  State<_IssueSheet> createState() => _IssueSheetState();
}

class _IssueSheetState extends State<_IssueSheet> {
  late final _rows = [
    for (final r in widget.order.requirements)
      (
        req: r,
        qty: TextEditingController(
          text: r.remaining > 0 ? ErpFmt.qty(r.allowsDecimals ? (r.remaining * 1000).ceil() / 1000 : r.remaining.ceil()).replaceAll(',', '') : '',
        ),
        batch: ValueNotifier<String?>(null),
      ),
  ];

  @override
  void dispose() {
    for (final r in _rows) {
      r.qty.dispose();
      r.batch.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> get _lines => [
    for (final r in _rows)
      if ((double.tryParse(r.qty.text) ?? 0) > 0)
        {'product_id': r.req.productId, 'quantity': double.parse(r.qty.text), 'batch_number': r.batch.value},
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final o = widget.order;
    return _SheetBody(
      children: [
        _SheetHead(
          icon: PhosphorIconsRegular.trayArrowUp,
          title: 'prd.issueMaterials'.tr,
          subtitle: 'prd.issueSub'.trParams({'warehouse': o.materialsWarehouse ?? '-'}),
        ),
        for (final r in _rows) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: vfCardDecoration(t),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(r.req.name, style: VfType.bodyStrong.copyWith(color: t.text, fontSize: 14.5, height: 1.3)),
                Text(
                  '${'prd.toIssue'.tr} ${ErpFmt.qty(r.req.remaining)} · ${'prd.inStore'.tr} ${ErpFmt.qty(r.req.available)} ${r.req.unit}',
                  style: VfType.meta.copyWith(color: t.muted, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                const SizedBox(height: 10),
                VouchFlowTextField(
                  label: '${'inv.quantity'.tr} (${r.req.unit})',
                  controller: r.qty,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: _numbers,
                  onChanged: (_) => setState(() {}),
                ),
                if (r.req.trackBatches && r.req.batches.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ValueListenableBuilder<String?>(
                    valueListenable: r.batch,
                    builder: (_, value, _) => VouchFlowDropdown<String>(
                      label: 'prd.batch'.tr,
                      items: ['', for (final b in r.req.batches) b.batch],
                      value: value ?? '',
                      itemLabel: (b) {
                        if (b.isEmpty) return 'prd.batchAuto'.tr;
                        final x = r.req.batches.firstWhere((e) => e.batch == b);
                        return '$b · ${ErpFmt.qty(x.quantity)}';
                      },
                      onChanged: (v) => r.batch.value = (v == null || v.isEmpty) ? null : v,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        Text('prd.issueHint'.tr, style: VfType.meta.copyWith(color: t.muted)),
        OpsConfirm(
          confirmLabel: 'prd.issueAndPost'.tr,
          icon: PhosphorIconsRegular.checkCircle,
          ready: _lines.isNotEmpty,
          run: (_) => ProductionRepository.to.issue(o.id, _lines),
        ),
      ],
    );
  }
}

/* ═══════════════════════════════════════════════════════ record output ══ */

/// Records output on [order]: good, rejected and wastage, the batch and
/// expiry it needs, and whether it is the last. Returns the API's message.
Future<String?> showOutputSheet(BuildContext context, ProductionOrder order) =>
    showVfSheet<String>(context, builder: (_) => _OutputSheet(order: order));

class _OutputSheet extends StatefulWidget {
  const _OutputSheet({required this.order});

  final ProductionOrder order;

  @override
  State<_OutputSheet> createState() => _OutputSheetState();
}

class _OutputSheetState extends State<_OutputSheet> {
  final _good = TextEditingController();
  final _rejected = TextEditingController(text: '0');
  final _wastage = TextEditingController(text: '0');
  late final _batch = TextEditingController(text: _suggestBatch());
  final _notes = TextEditingController();
  late DateTime? _expiry = widget.order.trackExpiry ? DateTime.now().add(const Duration(days: 365)) : null;
  bool _final = false;

  /// The web's suggestion: the SKU's short name, today, then A, B, C per receipt.
  String _suggestBatch() {
    final o = widget.order;
    if (!o.trackBatches) return '';
    final prefix = (o.productSku ?? 'FG').replaceFirst(RegExp(r'^FG-'), '').split('-').first;
    final d = DateTime.now();
    final stamp = '${'${d.year % 100}'.padLeft(2, '0')}${'${d.month}'.padLeft(2, '0')}${'${d.day}'.padLeft(2, '0')}';
    return '$prefix-$stamp-${String.fromCharCode(65 + o.receipts.length)}';
  }

  @override
  void dispose() {
    for (final c in [_good, _rejected, _wastage, _batch, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  double _n(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;
  double get _produced => _n(_good) + _n(_rejected) + _n(_wastage);

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry ?? now.add(const Duration(days: 365)),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _expiry = picked);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final o = widget.order;
    Widget qty(String label, TextEditingController c, {bool required = false}) => Expanded(
      child: VouchFlowTextField(
        label: label,
        required: required,
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: _numbers,
        onChanged: (_) => setState(() {}),
      ),
    );
    return _SheetBody(
      children: [
        _SheetHead(icon: PhosphorIconsRegular.package, title: 'prd.recordOutput'.tr, subtitle: 'prd.recordOutputSub'.tr),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            qty('prd.good'.tr, _good, required: true),
            const SizedBox(width: 10),
            qty('prd.rejected'.tr, _rejected),
            const SizedBox(width: 10),
            qty('prd.wastage'.tr, _wastage),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${'prd.produced'.tr}  ', style: VfType.small.copyWith(color: t.muted)),
                TextSpan(
                  text: '${ErpFmt.qty(_produced)} ${o.unit}',
                  style: VfType.small.copyWith(color: t.text, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        if (o.trackBatches) ...[
          VouchFlowTextField(
            label: 'prd.batch'.tr,
            required: true,
            controller: _batch,
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 12),
        ],
        if (o.trackExpiry) ...[
          VouchFlowTextField(
            key: ValueKey(_expiry),
            label: 'inv.expiry'.tr,
            required: true,
            readOnly: true,
            initialValue: _expiry == null ? '' : dashDate(_expiry),
            suffix: Icon(PhosphorIconsRegular.calendarBlank, size: 18, color: t.muted),
            onTap: _pickExpiry,
          ),
          const SizedBox(height: 12),
        ],
        Container(
          decoration: vfCardDecoration(t),
          child: SwitchListTile.adaptive(
            value: _final,
            onChanged: (v) => setState(() => _final = v),
            title: Text('prd.finalReceipt'.tr, style: VfType.label.copyWith(color: t.text)),
            subtitle: Text('prd.finalReceiptHint'.tr, style: VfType.meta.copyWith(color: t.muted)),
          ),
        ),
        const SizedBox(height: 12),
        VouchFlowTextField(label: 'prd.notes'.tr, hint: 'inv.optional'.tr, controller: _notes, maxLines: 3, minLines: 1),
        OpsConfirm(
          confirmLabel: 'prd.saveOutput'.tr,
          icon: PhosphorIconsRegular.floppyDisk,
          ready: _produced > 0,
          run: (_) => ProductionRepository.to.receive(o.id, {
            'receipt_date': opsDay(DateTime.now()),
            'produced_quantity': _produced,
            'good_quantity': _n(_good),
            'rejected_quantity': _n(_rejected),
            'wastage_quantity': _n(_wastage),
            'batch_number': _batch.text.trim().isEmpty ? null : _batch.text.trim(),
            'expiry_date': _expiry == null ? null : opsDay(_expiry!),
            'is_final': _final,
            'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          }),
        ),
      ],
    );
  }
}

/* ═══════════════════════════════════════════════════════ quality check ══ */

/// The usual checks for bottled water, as the web's quality dialog starts.
List<QcParameter> defaultQcParameters() => [
  QcParameter(name: 'pH', target: '6.5 to 8.5'),
  QcParameter(name: 'Total dissolved solids', target: 'up to 500 mg/L'),
  QcParameter(name: 'Fill level'),
  QcParameter(name: 'Cap torque', target: '12 to 18 in-lb'),
  QcParameter(name: 'Label and coding', target: 'Batch and expiry legible'),
];

/// The quality check on [receipt]: each parameter's measured value and
/// pass or fail, then release into stock or reject. A failed parameter
/// leaves only Reject, as the API insists. Returns the API's message.
Future<String?> showQcSheet(BuildContext context, PrdReceipt receipt, {String? productName}) =>
    showVfSheet<String>(context, builder: (_) => _QcSheet(receipt: receipt, productName: productName));

class _QcSheet extends StatefulWidget {
  const _QcSheet({required this.receipt, this.productName});

  final PrdReceipt receipt;
  final String? productName;

  @override
  State<_QcSheet> createState() => _QcSheetState();
}

class _QcSheetState extends State<_QcSheet> {
  final _params = defaultQcParameters();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = TextEditingController();
    final added = await showVouchFlowBottomSheet<String>(
      context,
      title: 'prd.addParameter'.tr,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: VouchFlowTextField(label: 'prd.parameter'.tr, controller: name, autofocus: true),
      ),
      actions: [
        Builder(
          builder: (ctx) => VouchFlowButton(
            label: 'prd.addParameter'.tr,
            onPressed: () => Navigator.of(ctx).pop(name.text.trim()),
          ),
        ),
      ],
    );
    name.dispose();
    if (added != null && added.isNotEmpty) setState(() => _params.add(QcParameter(name: added)));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final r = widget.receipt;
    final failed = _params.any((p) => !p.passed);
    final repo = ProductionRepository.to;
    return _SheetBody(
      children: [
        _SheetHead(
          icon: PhosphorIconsRegular.sealCheck,
          title: 'prd.qcTitle'.tr,
          subtitle: [r.number, ?(widget.productName ?? r.productName), ?r.batch].join(' · '),
        ),
        Text('prd.qcSub'.tr, style: VfType.small.copyWith(color: t.text2)),
        const SizedBox(height: 14),
        Container(
          decoration: vfCardDecoration(t),
          child: Column(
            children: [
              for (var i = 0; i < _params.length; i++)
                _ParamRow(
                  key: ObjectKey(_params[i]),
                  param: _params[i],
                  divider: i > 0,
                  onChanged: () => setState(() {}),
                  onRemove: _params.length > 1 ? () => setState(() => _params.removeAt(i)) : null,
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        VouchFlowButton(
          label: 'prd.addParameter'.tr,
          icon: PhosphorIconsBold.plus,
          variant: VfButtonVariant.ghost,
          compact: true,
          onPressed: _add,
        ),
        if (failed) ...[
          const SizedBox(height: 8),
          VouchFlowAlert(message: 'prd.failedBlocks'.tr, tone: VfTone.warn, icon: PhosphorIconsRegular.warning),
        ],
        const SizedBox(height: 12),
        VouchFlowTextField(label: 'prd.notes'.tr, hint: 'inv.optional'.tr, controller: _notes, maxLines: 3, minLines: 1),
        const SizedBox(height: 6),
        _QcDecision(
          canRelease: !failed && r.good > 0,
          run: (decision) => repo.inspect(r.id, decision: decision, parameters: _params, notes: _notes.text),
        ),
      ],
    );
  }
}

class _ParamRow extends StatelessWidget {
  const _ParamRow({super.key, required this.param, required this.divider, required this.onChanged, this.onRemove});

  final QcParameter param;
  final bool divider;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final p = param;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
      decoration: BoxDecoration(
        border: divider ? Border(top: BorderSide(color: t.isDark ? t.glassBorder : t.border)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: VfType.bodyStrong.copyWith(color: t.text, fontSize: 14.5, height: 1.3)),
                    if (p.target.isNotEmpty)
                      Text('${'prd.target'.tr}: ${p.target}', style: VfType.meta.copyWith(color: t.muted)),
                  ],
                ),
              ),
              if (onRemove != null)
                IconButton(
                  tooltip: 'inv.remove'.tr,
                  onPressed: onRemove,
                  icon: Icon(PhosphorIconsRegular.x, size: 17, color: t.muted),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: VouchFlowTextField(
                    label: 'prd.measured'.tr,
                    initialValue: p.value,
                    onChanged: (v) => p.value = v,
                  ),
                ),
                const SizedBox(width: 10),
                _PassFail(
                  passed: p.passed,
                  onChanged: (v) {
                    p.passed = v;
                    onChanged();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pass / Fail as a two-segment toggle, big enough for a gloved thumb.
class _PassFail extends StatelessWidget {
  const _PassFail({required this.passed, required this.onChanged});

  final bool passed;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    Widget seg(bool value, String label, Color fg, Color bg) {
      final on = passed == value;
      return Semantics(
        button: true,
        selected: on,
        child: InkWell(
          borderRadius: BorderRadius.circular(VfSize.radiusM),
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: on ? bg : Colors.transparent,
              borderRadius: BorderRadius.circular(VfSize.radiusM),
            ),
            child: Text(label, style: VfType.label.copyWith(fontSize: 13.5, color: on ? fg : t.muted)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.isDark ? t.glassFillStrong : t.background,
        borderRadius: BorderRadius.circular(VfSize.radiusM + 3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg(true, 'prd.pass'.tr, t.successStrong, t.successSoft),
          seg(false, 'prd.fail'.tr, t.dangerStrong, t.dangerSoft),
        ],
      ),
    );
  }
}

/// Reject and Release, the second only while every parameter passed.
class _QcDecision extends StatefulWidget {
  const _QcDecision({required this.canRelease, required this.run});

  final bool canRelease;
  final Future<String> Function(String decision) run;

  @override
  State<_QcDecision> createState() => _QcDecisionState();
}

class _QcDecisionState extends State<_QcDecision> {
  String? _busy;
  String? _error;

  Future<void> _go(String decision) async {
    FocusScope.of(context).unfocus();
    setState(() { _busy = decision; _error = null; });
    try {
      final message = await widget.run(decision);
      if (mounted) Navigator.of(context).pop(message);
    } catch (e) {
      if (mounted) setState(() { _busy = null; _error = opsError(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: VfType.small.copyWith(color: t.dangerStrong)),
        ],
        const SizedBox(height: 14),
        VouchFlowActions(
          children: [
            VouchFlowButton(
              label: 'prd.reject'.tr,
              icon: PhosphorIconsRegular.xCircle,
              variant: VfButtonVariant.danger,
              loading: _busy == 'reject',
              onPressed: _busy != null ? null : () => _go('reject'),
            ),
            VouchFlowButton(
              label: 'prd.release'.tr,
              icon: PhosphorIconsRegular.sealCheck,
              loading: _busy == 'release',
              onPressed: _busy != null || !widget.canRelease ? null : () => _go('release'),
            ),
          ],
        ),
      ],
    );
  }
}
