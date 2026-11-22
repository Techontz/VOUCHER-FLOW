import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/sales_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/sales_repository.dart';
import '../../data/services/session_service.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart' show showToast;
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate, dashDateTime;
import '../erp/erp_widgets.dart';
import 'sales_widgets.dart';

/// One customer receipt: the money, where it went, the invoices it pays;
/// and finance verification (Verify, Reject) by someone other than the
/// person who recorded it. Opened with the receipt id as the argument.
class SalesReceiptPage extends StatefulWidget {
  const SalesReceiptPage({super.key, this.receiptId});

  final int? receiptId;

  @override
  State<SalesReceiptPage> createState() => _SalesReceiptPageState();
}

class _SalesReceiptPageState extends State<SalesReceiptPage> {
  late final int _id = widget.receiptId ?? (Get.arguments as int);
  final _repo = SalesRepository.to;
  final _erp = ErpService.to;
  SalesReceipt? _receipt;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _repo.receipt(_id);
      if (mounted) setState(() { _receipt = r; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'state.offline'.tr);
    }
  }

  bool _mine(SalesReceipt r) {
    if (!Get.isRegistered<SessionService>()) return false;
    final me = Get.find<SessionService>().user.value?.id;
    return me != null && r.createdBy == me;
  }

  @override
  Widget build(BuildContext context) {
    final r = _receipt;
    return VouchFlowPushedScaffold(
      title: r?.number ?? 'sal.receipt'.tr,
      body: r == null
          ? (_error == null
                ? const VfLoadingView()
                : ErpPageBody(children: [VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)]))
          : _body(context, r),
      bottomBar: r == null || r.status != SalesStatus.recorded || !_erp.can('dispatch.verify') || _mine(r)
          ? null
          : SalesActionBar(
              children: [
                VouchFlowButton(
                  label: 'sal.reject'.tr,
                  variant: VfButtonVariant.secondary,
                  onPressed: () async {
                    final m = await rejectReceipt(context, r);
                    if (m != null) _load();
                  },
                ),
                VouchFlowButton(
                  label: 'sal.verify'.tr,
                  icon: PhosphorIconsRegular.shieldCheck,
                  onPressed: () async {
                    final m = await verifyReceipt(context, r);
                    if (m != null) _load();
                  },
                ),
              ],
            ),
    );
  }

  Widget _body(BuildContext context, SalesReceipt r) {
    final t = context.vf;
    return ErpPageBody(
      onRefresh: _load,
      children: [
        SalesDocHead(
          icon: PhosphorIconsRegular.handCoins,
          tint: t.successStrong,
          kind: 'sal.receipt'.tr,
          number: r.number,
          status: r.status,
          subtitle: [?r.customer?.name, if (r.receiptDate != null) dashDate(r.receiptDate)].join(' · '),
        ),
        VouchFlowFigureCard(
          label: 'sal.amount'.tr,
          value: salesMoney(r.amount),
          hint: [salesMethodLabel(r.method), ?r.reference].join(' · '),
          icon: PhosphorIconsRegular.coins,
          tone: r.status == SalesStatus.verified ? VfTone.ok : (r.status == SalesStatus.rejected ? VfTone.bad : VfTone.warn),
        ),
        erpGap,
        if (r.status == SalesStatus.recorded) ...[
          VouchFlowAlert(
            tone: VfTone.info,
            icon: PhosphorIconsRegular.shieldCheck,
            message: _mine(r) ? 'sal.verifyOther'.tr : 'sal.awaitsVerification'.tr,
          ),
          erpGap,
        ],
        if (r.status == SalesStatus.rejected && r.rejectionReason != null) ...[
          VouchFlowAlert(tone: VfTone.bad, icon: PhosphorIconsRegular.thumbsDown, message: r.rejectionReason!),
          erpGap,
        ],
        VouchFlowPanel(
          title: 'sal.appliedTo'.tr,
          padded: false,
          child: Column(
            children: [
              for (var n = 0; n < r.allocations.length; n++)
                VouchFlowListRow(
                  divider: n > 0,
                  icon: PhosphorIconsRegular.receipt,
                  iconColor: t.infoStrong,
                  title: r.allocations[n].invoice?.number ?? '-',
                  trailing: MoneyText(r.allocations[n].amount, style: VfType.small.copyWith(fontWeight: FontWeight.w600)),
                  onTap: r.allocations[n].invoice == null
                      ? null
                      : () => Get.toNamed(Routes.salesInvoice, arguments: r.allocations[n].invoice!.id),
                ),
            ],
          ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'sal.details'.tr,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SalesFact('sal.customer'.tr, r.customer?.name),
              SalesFact('sal.intoAccount'.tr, r.account == null ? null : [?r.account!.code, r.account!.name].join(' · ')),
              SalesFact('sal.method'.tr, salesMethodLabel(r.method)),
              SalesFact('sal.reference'.tr, r.reference),
              SalesFact('sal.recordedBy'.tr, [r.creator ?? '-', if (r.createdAt != null) dashDateTime(r.createdAt)].join(' · ')),
              if (r.verifiedAt != null)
                SalesFact('sal.verifiedBy'.tr, [r.verifier ?? '-', dashDateTime(r.verifiedAt)].join(' · ')),
              SalesFact('sal.notes'.tr, r.notes),
            ],
          ),
        ),
      ],
    );
  }
}

/// Verifies a receipt behind its confirmation sheet; the message, or null.
Future<String?> verifyReceipt(BuildContext context, SalesReceipt r) async {
  final m = await confirmSalesAction(
    context,
    icon: PhosphorIconsRegular.shieldCheck,
    tone: VfTone.ok,
    title: 'sal.verifyQ'.trParams({'number': r.number}),
    subtitle: 'sal.verifySub'.tr,
    summary: [
      VfSummaryRow('sal.customer'.tr, r.customer?.name ?? '-'),
      VfSummaryRow('sal.amount'.tr, salesMoney(r.amount)),
      VfSummaryRow('sal.method'.tr, [salesMethodLabel(r.method), ?r.reference].join(' · ')),
    ],
    confirmLabel: 'sal.verify'.tr,
    run: (_) => SalesRepository.to.verifyReceipt(r.id),
  );
  if (m != null) showToast(m.isEmpty ? salesStatusLabel(SalesStatus.verified) : m);
  return m;
}

/// Rejects a receipt with a reason; the message, or null.
Future<String?> rejectReceipt(BuildContext context, SalesReceipt r) async {
  final m = await confirmSalesAction(
    context,
    icon: PhosphorIconsRegular.thumbsDown,
    tone: VfTone.warn,
    title: 'sal.rejectReceiptQ'.trParams({'number': r.number}),
    subtitle: 'sal.rejectReceiptSub'.tr,
    confirmLabel: 'sal.reject'.tr,
    danger: true,
    reason: SalesReason(label: 'sal.reason'.tr),
    run: (reason) => SalesRepository.to.rejectReceipt(r.id, reason),
  );
  if (m != null) showToast(m.isEmpty ? salesStatusLabel(SalesStatus.rejected) : m);
  return m;
}
