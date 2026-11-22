import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart';
import '../../data/models/sales_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/sales_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart' show showToast;
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;
import '../erp/erp_widgets.dart';
import '../sales/sales_widgets.dart';

/// One loading order (the web's /erp/dispatch/loading/[id]): one truck,
/// one warehouse, one order, and every step from the bay to the customer's
/// signature, each done by the person whose job it is: enter what was
/// loaded and confirm it (stock leaves), the driver and the gate confirm,
/// the delivery note and the gate pass (out for delivery), proof of
/// delivery with who received it, and the decision on a short delivery
/// (back to stock or written off). Opened with the loading order id.
class LoadingOrderPage extends StatefulWidget {
  const LoadingOrderPage({super.key, this.loadingId});

  final int? loadingId;

  @override
  State<LoadingOrderPage> createState() => _LoadingOrderPageState();
}

class _LoadingOrderPageState extends State<LoadingOrderPage> {
  late final int _id = widget.loadingId ?? (Get.arguments as int);
  final _repo = SalesRepository.to;
  final _erp = ErpService.to;
  LoadingOrder? _lo;
  String? _error;

  /// What the warehouse is typing as loaded, per line.
  final _loaded = <int, TextEditingController>{};
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _loaded.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _plain(double? v) => v == null ? '' : ErpFmt.qty(v).replaceAll(',', '');

  Future<void> _load() async {
    try {
      final lo = await _repo.loadingOrder(_id);
      if (!mounted) return;
      setState(() {
        _lo = lo;
        _error = null;
        for (final l in lo.lines) {
          (_loaded[l.id] ??= TextEditingController()).text = _plain(l.loaded);
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'state.offline'.tr);
    }
  }

  bool _dirty(LoadingOrder lo) => lo.lines.any((l) => (_loaded[l.id]?.text.trim() ?? '') != _plain(l.loaded));

  void _done(String? message) {
    if (message == null) return;
    showToast(message.isEmpty ? 'sal.done'.tr : message);
    _load();
  }

  Future<void> _saveLoaded(LoadingOrder lo) async {
    FocusScope.of(context).unfocus();
    setState(() { _saving = true; _saveError = null; });
    try {
      final m = await _repo.saveLoaded(lo.id, {
        for (final l in lo.lines)
          l.id: (_loaded[l.id]?.text.trim() ?? '').isEmpty ? null : salesNum(_loaded[l.id]!.text),
      });
      showToast(m.isEmpty ? 'dsp.loadedSaved'.tr : m);
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _saveError = e.message);
    } catch (_) {
      if (mounted) setState(() => _saveError = 'state.offline'.tr);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<VfSummaryRow> _summary(LoadingOrder lo) => [
    VfSummaryRow('sal.customer'.tr, lo.customer?.name ?? '-'),
    if (lo.vehicleNumber != null) VfSummaryRow('dsp.vehicle'.tr, lo.vehicleNumber!),
    if (lo.driverName != null) VfSummaryRow('dsp.driver'.tr, lo.driverName!),
  ];

  Future<void> _confirmLoading(LoadingOrder lo) async => _done(
    await confirmSalesAction(
      context,
      icon: PhosphorIconsRegular.package,
      title: 'dsp.confirmLoadingQ'.trParams({'number': lo.number}),
      subtitle: 'dsp.confirmLoadingSub'.tr,
      summary: [
        for (final l in lo.lines) VfSummaryRow(l.productName, '${ErpFmt.qty(l.loaded)}${l.unitCode == null ? '' : ' ${l.unitCode}'}'),
      ],
      confirmLabel: 'dsp.confirmLoading'.tr,
      run: (_) => _repo.confirmLoading(lo.id),
    ),
  );

  Future<void> _driver(LoadingOrder lo) async => _done(
    await confirmSalesAction(
      context,
      icon: PhosphorIconsRegular.steeringWheel,
      title: 'dsp.driverConfirms'.tr,
      subtitle: 'dsp.driverConfirmsSub'.trParams({'name': lo.driverName ?? '-'}),
      summary: _summary(lo),
      confirmLabel: 'dsp.confirm'.tr,
      reason: SalesReason(label: 'dsp.driverName'.tr, required: lo.driverName == null, min: 2, initial: lo.driverName),
      run: (name) => _repo.confirmDriver(lo.id, name),
    ),
  );

  Future<void> _security(LoadingOrder lo) async => _done(
    await confirmSalesAction(
      context,
      icon: PhosphorIconsRegular.shieldCheck,
      title: 'dsp.securityConfirms'.tr,
      subtitle: 'dsp.securityConfirmsSub'.tr,
      summary: _summary(lo),
      confirmLabel: 'dsp.confirm'.tr,
      reason: SalesReason(label: 'dsp.securityName'.tr, required: false),
      run: (name) => _repo.confirmSecurity(lo.id, name),
    ),
  );

  Future<void> _deliveryNote(LoadingOrder lo) async => _done(
    await confirmSalesAction(
      context,
      icon: PhosphorIconsRegular.fileText,
      title: 'dsp.issueDeliveryNote'.tr,
      subtitle: 'dsp.issueDeliveryNoteSub'.tr,
      summary: _summary(lo),
      confirmLabel: 'dsp.issue'.tr,
      run: (_) => _repo.issueDeliveryNote(lo.id),
    ),
  );

  Future<void> _gatePass(LoadingOrder lo) async => _done(
    await confirmSalesAction(
      context,
      icon: PhosphorIconsRegular.doorOpen,
      title: 'dsp.outForDeliveryQ'.tr,
      subtitle: 'dsp.issueGatePassSub'.tr,
      summary: [..._summary(lo), if (lo.deliveryNoteNumber != null) VfSummaryRow('sal.deliveryNote'.tr, lo.deliveryNoteNumber!)],
      confirmLabel: 'dsp.issueGatePass'.tr,
      run: (_) => _repo.issueGatePass(lo.id),
    ),
  );

  Future<void> _deliver(LoadingOrder lo) async {
    final received = {for (final l in lo.lines) l.id: TextEditingController(text: _plain(l.loaded ?? 0))};
    final name = TextEditingController();
    final remark = TextEditingController();
    var date = DateTime.now();
    final numbers = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    final message = await confirmSalesAction(
      context,
      icon: PhosphorIconsRegular.handArrowDown,
      tone: VfTone.ok,
      title: 'dsp.proofOfDelivery'.tr,
      subtitle: 'dsp.podSub'.tr,
      confirmLabel: 'dsp.recordDelivery'.tr,
      ready: () => name.text.trim().length >= 2,
      extra: (context, setState) {
        final t = context.vf;
        final short = lo.lines.any((l) => salesNum(received[l.id]!.text) < (l.loaded ?? 0) - 0.00001);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            VouchFlowTextField(
              label: 'dsp.receivedBy'.tr,
              required: true,
              placeholder: 'dsp.receivedByHint'.tr,
              controller: name,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            VouchFlowTextField(
              key: ValueKey(date),
              label: 'dsp.receivedOn'.tr,
              required: true,
              readOnly: true,
              initialValue: dashDate(date),
              suffix: Icon(PhosphorIconsRegular.calendarBlank, size: 18, color: t.muted),
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(now.year - 1), lastDate: now);
                if (picked != null) setState(() => date = picked);
              },
            ),
            const SizedBox(height: 12),
            for (final l in lo.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: VouchFlowTextField(
                  label: l.productName,
                  hint: 'dsp.loadedN'.trParams({'n': ErpFmt.qty(l.loaded)}),
                  controller: received[l.id],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: numbers,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            VouchFlowTextField(
              label: 'dsp.remark'.tr,
              hint: 'sal.optional'.tr,
              placeholder: 'dsp.remarkHint'.tr,
              controller: remark,
              maxLength: 500,
              maxLines: 3,
              minLines: 2,
            ),
            if (short) ...[
              const SizedBox(height: 8),
              VouchFlowAlert(message: 'dsp.shortWarning'.tr, tone: VfTone.warn, icon: PhosphorIconsRegular.warning),
            ],
          ],
        );
      },
      run: (_) => _repo.deliver(
        lo.id,
        receivedBy: name.text,
        date: date,
        remark: remark.text,
        quantities: {for (final l in lo.lines) l.id: salesNum(received[l.id]!.text)},
      ),
    );
    // After the sheet has finished sliding away.
    Future.delayed(const Duration(seconds: 1), () {
      for (final c in [...received.values, name, remark]) {
        c.dispose();
      }
    });
    _done(message);
  }

  Future<void> _resolve(LoadingOrder lo) async {
    var decision = 'return';
    _done(
      await confirmSalesAction(
        context,
        icon: PhosphorIconsRegular.scales,
        tone: VfTone.warn,
        title: 'dsp.resolveShort'.tr,
        subtitle: 'dsp.resolveShortSub'.tr,
        confirmLabel: 'dsp.decide'.tr,
        reason: SalesReason(label: 'dsp.whatHappened'.tr),
        extra: (context, setState) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: VouchFlowDropdown<String>(
            label: 'dsp.decision'.tr,
            items: const ['return', 'write_off'],
            value: decision,
            itemLabel: (d) => 'dsp.decision.$d'.tr,
            onChanged: (v) => setState(() => decision = v ?? decision),
          ),
        ),
        run: (note) => _repo.resolve(lo.id, decision, note),
      ),
    );
  }

  Future<void> _cancel(LoadingOrder lo) async => _done(
    await confirmSalesAction(
      context,
      icon: PhosphorIconsRegular.xCircle,
      tone: VfTone.warn,
      title: 'dsp.cancelQ'.trParams({'number': lo.number}),
      subtitle: 'dsp.cancelSub'.tr,
      summary: _summary(lo),
      confirmLabel: 'sal.cancelDoc'.tr,
      backLabel: 'sal.keep'.tr,
      danger: true,
      run: (_) => _repo.cancelLoading(lo.id),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final lo = _lo;
    return VouchFlowPushedScaffold(
      title: lo?.number ?? 'sal.loadingOrder'.tr,
      body: lo == null
          ? (_error == null
                ? const VfLoadingView()
                : ErpPageBody(children: [VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)]))
          : _body(context, lo),
      bottomBar: lo == null ? null : _actions(lo),
    );
  }

  /// The one or two things that can happen next, for this person.
  Widget? _actions(LoadingOrder lo) {
    final load = _erp.can('dispatch.load');
    final gate = _erp.can('dispatch.gatepass');
    final quiet = <Widget>[];
    final main = <Widget>[];
    if (lo.isOpen && load) {
      quiet.add(SalesQuietAction(label: 'sal.cancelDoc'.tr, icon: PhosphorIconsRegular.xCircle, onPressed: () => _cancel(lo)));
      main.add(
        VouchFlowButton(
          label: 'dsp.confirmLoading'.tr,
          icon: PhosphorIconsRegular.checkCircle,
          onPressed: lo.allEntered && !_dirty(lo) ? () => _confirmLoading(lo) : null,
        ),
      );
    }
    if (lo.isLoaded) {
      if (lo.driverConfirmedAt == null && load) {
        main.add(VouchFlowButton(label: 'dsp.driverConfirms'.tr, variant: VfButtonVariant.secondary, onPressed: () => _driver(lo)));
      }
      if (lo.securityConfirmedAt == null && gate) {
        main.add(VouchFlowButton(label: 'dsp.securityConfirms'.tr, variant: VfButtonVariant.secondary, onPressed: () => _security(lo)));
      }
      if (lo.driverConfirmedAt != null && lo.securityConfirmedAt != null && lo.deliveryNoteNumber == null && load) {
        main.add(VouchFlowButton(label: 'dsp.issueDeliveryNote'.tr, icon: PhosphorIconsRegular.fileText, onPressed: () => _deliveryNote(lo)));
      }
      if (lo.deliveryNoteNumber != null && gate) {
        main.add(VouchFlowButton(label: 'dsp.outForDelivery'.tr, icon: PhosphorIconsRegular.doorOpen, onPressed: () => _gatePass(lo)));
      }
    }
    if (lo.onTheRoad && _erp.can('dispatch.deliver')) {
      main.add(VouchFlowButton(label: 'dsp.recordDelivery'.tr, icon: PhosphorIconsRegular.handArrowDown, onPressed: () => _deliver(lo)));
    }
    if (lo.discrepancyOpen && _erp.can('dispatch.resolve')) {
      main.add(VouchFlowButton(label: 'dsp.resolveShort'.tr, icon: PhosphorIconsRegular.scales, onPressed: () => _resolve(lo)));
    }
    final all = [...quiet, ...main];
    return all.isEmpty ? null : SalesActionBar(children: all);
  }

  /// What the page says happens next, in a sentence.
  String? _nextStep(LoadingOrder lo) {
    if (lo.isOpen) return lo.allEntered ? 'dsp.next.confirm'.tr : 'dsp.next.enterLoaded'.tr;
    if (lo.isLoaded) {
      if (lo.driverConfirmedAt == null || lo.securityConfirmedAt == null) return 'dsp.next.confirmations'.tr;
      if (lo.deliveryNoteNumber == null) return 'dsp.next.deliveryNote'.tr;
      return 'dsp.next.gatePass'.tr;
    }
    if (lo.onTheRoad) return 'dsp.next.deliver'.tr;
    return null;
  }

  Widget _body(BuildContext context, LoadingOrder lo) {
    final t = context.vf;
    final canLoad = lo.isOpen && _erp.can('dispatch.load');
    final next = _nextStep(lo);
    final numbers = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    final dirty = _dirty(lo);

    return ErpPageBody(
      onRefresh: _load,
      children: [
        SalesDocHead(
          icon: lo.onTheRoad ? PhosphorIconsRegular.truck : PhosphorIconsRegular.package,
          tint: lo.discrepancyOpen ? t.dangerStrong : (lo.onTheRoad ? t.infoStrong : t.primary),
          kind: 'sal.loadingOrder'.tr,
          number: lo.number,
          status: lo.status,
          subtitle: [?lo.customer?.name, ?lo.warehouse?.name, if (lo.plannedDate != null) dashDate(lo.plannedDate)].join(' · '),
          extra: lo.discrepancyStatus == null
              ? null
              : VouchFlowStatusBadge(
                  label: 'dsp.short.${lo.discrepancyStatus}'.tr,
                  tag: lo.discrepancyOpen ? 'tag-accent-2' : 'tag-neutral',
                  large: true,
                ),
        ),
        if (lo.discrepancyOpen) ...[
          VouchFlowAlert(
            tone: VfTone.bad,
            icon: PhosphorIconsRegular.warningDiamond,
            title: 'dsp.shortOpen'.tr,
            message: 'dsp.shortOpenBody'.tr,
          ),
          erpGap,
        ] else if (next != null) ...[
          VouchFlowAlert(tone: VfTone.info, icon: PhosphorIconsRegular.signpost, title: 'dsp.nextStep'.tr, message: next),
          erpGap,
        ],
        VouchFlowPanel(
          title: 'sal.lines'.tr,
          subtitle: canLoad ? 'dsp.loadedHint'.tr : null,
          padded: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < lo.lines.length; i++)
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: i == 0
                      ? null
                      : BoxDecoration(border: Border(top: BorderSide(color: t.isDark ? t.glassBorder : t.border))),
                  child: _LineBlock(
                    line: lo.lines[i],
                    available: lo.isOpen ? (lo.availability[lo.lines[i].productId]?[lo.warehouseId])?.onHand : null,
                    editor: canLoad
                        ? VouchFlowTextField(
                            label: 'sal.qtyLoaded'.tr,
                            controller: _loaded[lo.lines[i].id],
                            placeholder: ErpFmt.qty(lo.lines[i].approved),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: numbers,
                            onChanged: (_) => setState(() {}),
                          )
                        : null,
                  ),
                ),
              if (canLoad)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_saveError != null) ...[
                        Text(_saveError!, style: VfType.small.copyWith(color: t.dangerStrong)),
                        const SizedBox(height: 8),
                      ],
                      VouchFlowButton(
                        label: 'dsp.saveLoaded'.tr,
                        icon: PhosphorIconsRegular.floppyDisk,
                        variant: VfButtonVariant.secondary,
                        expand: true,
                        loading: _saving,
                        onPressed: dirty && !_saving ? () => _saveLoaded(lo) : null,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (lo.isDelivered) ...[
          erpGap,
          VouchFlowPanel(
            title: 'dsp.proofOfDelivery'.tr,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SalesFact('dsp.receivedBy'.tr, lo.receivedByName),
                SalesFact('dsp.receivedOn'.tr, lo.receivedDate == null ? null : dashDate(lo.receivedDate)),
                SalesFact('dsp.remark'.tr, lo.deliveryRemark),
                SalesFact(
                  'dsp.shortage'.tr,
                  lo.shortDelivered ? 'dsp.short.${lo.discrepancyStatus ?? 'open'}'.tr : 'dsp.noShortage'.tr,
                ),
                SalesFact('dsp.decisionNote'.tr, lo.discrepancyNote),
                SalesFact(
                  'dsp.returnDocument'.tr,
                  lo.returnDocument?.number,
                  onTap: lo.returnDocument == null || !_erp.can('inventory.view')
                      ? null
                      : () => Get.toNamed(Routes.erpDocument, arguments: lo.returnDocument!.id),
                ),
              ],
            ),
          ),
        ],
        erpGap,
        VouchFlowPanel(
          title: 'dsp.transport'.tr,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SalesFact(
                'sal.order'.tr,
                lo.order?.number,
                onTap: lo.order == null || !_erp.has('sales') || !_erp.can('sales.view')
                    ? null
                    : () => Get.toNamed(Routes.salesOrder, arguments: lo.order!.id),
              ),
              SalesFact('dsp.vehicle'.tr, lo.vehicleNumber),
              SalesFact('dsp.driver'.tr, lo.driverName),
              SalesFact('dsp.destination'.tr, lo.destination ?? lo.customer?.place),
              SalesFact('sal.phone'.tr, lo.customer?.phone),
              SalesFact('sal.deliveryNote'.tr, lo.deliveryNoteNumber),
              SalesFact('dsp.gatePass'.tr, lo.gatePassNumber),
              SalesFact(
                'dsp.stockIssue'.tr,
                lo.stockDocument?.number,
                onTap: lo.stockDocument == null || !_erp.can('inventory.view')
                    ? null
                    : () => Get.toNamed(Routes.erpDocument, arguments: lo.stockDocument!.id),
              ),
              SalesFact('sal.notes'.tr, lo.notes),
            ],
          ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'sal.timeline'.tr,
          child: SalesTimeline(
            steps: [
              ('sal.step.created'.tr, lo.createdAt, lo.creator),
              ('dsp.step.loaded'.tr, lo.loadedAt, lo.loader),
              ('dsp.step.driver'.tr, lo.driverConfirmedAt, lo.driverConfirmedName),
              ('dsp.step.security'.tr, lo.securityConfirmedAt, lo.securityConfirmedName),
              ('dsp.step.deliveryNote'.tr, lo.deliveryNoteIssuedAt, lo.deliveryNoteNumber),
              ('dsp.step.gatePass'.tr, lo.gatePassIssuedAt, lo.gatePassIssuer),
              ('dsp.step.delivered'.tr, lo.podRecordedAt, lo.receivedByName),
              if (lo.discrepancyStatus != null && lo.discrepancyStatus != 'open')
                ('dsp.short.${lo.discrepancyStatus}'.tr, lo.discrepancyResolvedAt, lo.resolver),
            ],
          ),
        ),
      ],
    );
  }
}

/// A loading line: the product and its quantities, with the loaded field
/// while the truck is being loaded.
class _LineBlock extends StatelessWidget {
  const _LineBlock({required this.line, this.available, this.editor});

  final LoadingLine line;
  final double? available;
  final Widget? editor;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final l = line;
    String q(double? v) => v == null ? '-' : ErpFmt.qty(v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.productName, style: VfType.bodyStrong.copyWith(color: t.text, height: 1.3)),
        Text(
          [?l.sku, ?l.unitCode, if (available != null) 'dsp.onHandHere'.trParams({'n': ErpFmt.qty(available)})].join(' · '),
          style: VfType.meta.copyWith(color: t.muted),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final (label, value, bad) in [
              ('sal.qtyOrdered'.tr, q(l.ordered), false),
              ('sal.qtyApproved'.tr, q(l.approved), false),
              if (editor == null) ('sal.qtyLoaded'.tr, q(l.loaded), false),
              ('sal.qtyReceived'.tr, q(l.received), l.short),
            ])
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: VfType.meta.copyWith(color: t.muted, fontSize: 11.5)),
                    Text(
                      value,
                      style: VfType.small.copyWith(
                        color: bad ? t.dangerStrong : t.text,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (editor != null) ...[const SizedBox(height: 10), editor!],
      ],
    );
  }
}
